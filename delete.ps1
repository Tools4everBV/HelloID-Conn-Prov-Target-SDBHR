#################################################
# HelloID-Conn-Prov-Target-SDBHR-Delete
# Update account
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-SDBHRError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            # TODO Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion functions

#region account
# Define correlation
$correlationField = "Id"
$correlationValue = $actionContext.References.Account

$account = [PSCustomObject]$actionContext.Data

# Define properties to compare for update
$accountPropertiesToCompare = $account.PsObject.Properties.Name
#endRegion account

try {
    #region Verify account reference
    $actionMessage = "verifying account reference"
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }
    #endregion Verify account reference

    #region Create authentication hash
    $actionMessage = "creating authentication hash with Customer Number [$($actionContext.Configuration.CustomerNumber)]"

    $currentDateTime = (Get-Date).ToString("dd-MM-yyyy HH:mm:ss.fff")

    $baseString = "$($CurrentDateTime.Substring(0,10))|$($CurrentDateTime.Substring(11,12))|$($actionContext.Configuration.CustomerNumber)"
    $key = [System.Text.Encoding]::UTF8.GetBytes($actionContext.Configuration.ApiKey)
    $hmac256 = [System.Security.Cryptography.HMACSHA256]::new()
    $hmac256.key = $key
    $hash = $hmac256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseString))
    $hashedString = [System.Convert]::ToBase64String($hash)

    Write-Information "Created authentication hash with Customer Number [$($actionContext.Configuration.CustomerNumber)]."
    #endregion Create authentication hash

    #region Create headers
    $actionMessage = "creating headers"

    $headers = @{
        "Klantnummer"    = $actionContext.Configuration.CustomerNumber
        "Authentication" = "$($actionContext.Configuration.ApiUser):$($hashedString)"
        "Timestamp"      = $currentDateTime
        "Content-Type"   = "application/json;charset=utf-8"
        "Api-Version"    = "2.0"
    }

    Write-Information "Created headers."
    #endregion Create headers

    #region Get account
    # SDBHR docs: https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_GetMedewerkerV2

    $getSDBHRAccountSplatParams = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/medewerkersbasic/$correlationValue"
        Headers         = $headers
        Method          = "GET"
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
        Verbose         = $false
        ErrorAction     = "Stop"
    }
    
    $correlatedAccount = Invoke-RestMethod @getSDBHRAccountSplatParams

    Write-Information "Queried SDBHR account where [$($correlationField)] = [$($correlationValue)]. Result: $($correlatedAccount | ConvertTo-Json)"
    #endregion Get account

    #region Account
    #region Calulate action
    $actionMessage = "calculating action"
    if (($correlatedAccount | Measure-Object).count -eq 0) {
        $actionAccount = "NotFound"
    }
    elseif (($correlatedAccount | Measure-Object).count -eq 1) {
        # Create previous account object to compare current data with specified account data
        $previousAccount = $correlatedAccount | Select-Object $accountPropertiesToCompare
        $outputContext.PreviousData = $previousAccount

        # Calculate changes between current data and provided data
        $splatCompareProperties = @{
            ReferenceObject  = @($previousAccount.PSObject.Properties)
            DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }) # Only select the properties to update
        }
        $changedProperties = $null
        $changedProperties = (Compare-Object @splatCompareProperties -PassThru)
        $oldProperties = $changedProperties.Where( { $_.SideIndicator -eq "<=" })
        $newProperties = $changedProperties.Where( { $_.SideIndicator -eq "=>" })

        if (($newProperties | Measure-Object).Count -ge 1) {
            # and update is enabled
            # Create custom object with old and new values
            $changedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }

            # Add the old properties to the custom object with old and new values
            foreach ($oldProperty in $oldProperties) {
                $changedPropertiesObject.OldValues.$($oldProperty.Name) = $oldProperty.Value
            }

            # Add the new properties to the custom object with old and new values
            foreach ($newProperty in $newProperties) {
                $changedPropertiesObject.NewValues.$($newProperty.Name) = $newProperty.Value
            }
            Write-Information "Changed properties: $($changedPropertiesObject | ConvertTo-Json)"

            $actionAccount = 'Update'
        }
        else {
            Write-Information "No changed properties"

            $actionAccount = 'NoChanges'
        }
    }
    elseif (($correlatedAccount | Measure-Object).count -gt 1) {
        $actionAccount = "MultipleFound"
    }
    #endregion Calulate action

    #region Process
    switch ($actionAccount) {
        "Update" {
            #region Update account
            # SDBHR docs: https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_Put
            $actionMessage = "updating account"

            # Create custom account object for update and set with default properties and values
            $updateAccountBody = [PSCustomObject]@{}

            # Add the updated properties to the custom account object for update
            foreach ($newProperty in $newProperties) {
                $updateAccountBody | Add-Member -MemberType NoteProperty -Name $newProperty.Name -Value $newProperty.Value -Force
            }

            $MutationDate = (Get-Date).ToString("yyyy-MM-dd") # Current Date
            $updateAccountSplatParams = @{
                Uri         = "$($actionContext.Configuration.BaseUri)/medewerkers/$($correlatedAccount.Id)/$($MutationDate)"
                Method      = "PUT"
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(($updateAccountBody | ConvertTo-Json -Depth 10)))
                ContentType = 'application/json; charset=utf-8'
                Verbose     = $false
                ErrorAction = "Stop"
            }

            Write-Information "SplatParams: $($updateAccountSplatParams | ConvertTo-Json)"

            if (-Not($actionContext.DryRun -eq $true)) {
                # Add header after printing splat
                $createAccountSplatParams['Headers'] = $headers

                $createAccountResponse = Invoke-RestMethod @createAccountSplatParams
                $createdAccount = $createAccountResponse

                $outputContext.AccountReference = "$($createdAccount.id)"
                $outputContext.Data = $createdAccount

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Updated account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Updated properties: $($changedPropertiesObject | ConvertTo-Json -Depth 10)."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would update account with AccountReference: $($outputContext.AccountReference | ConvertTo-Json). Updated properties: $($changedPropertiesObject | ConvertTo-Json -Depth 10)."
            }
            #endregion Update account
    
            break
        }

        "NoChanges" {
            #region No changes
            $actionMessage = "skipping updating account"

            $outputContext.Data = $correlatedAccount

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Skipped updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Reason: No changes."
                    IsError = $false
                })
            #endregion No changes

            break
        }

        "MultipleFound" {
            #region Multiple accounts found
            $actionMessage = "updating account"
    
            # Throw terminal error
            throw "Multiple accounts found where [$($correlationField)] = [$($correlationValue)]. Please correct this so the persons are unique."
            #endregion Multiple accounts found
    
            break
        }

        "NotFound" {
            #region No account found
            $actionMessage = "updating account"
        
            # Throw terminal error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "No account found where [$($correlationField)] = [$($correlationValue)] action skipped. Possibly indicating that it could be deleted, or not correlated."
                    IsError = $false
                })
            #endregion No account found

            break
        }
    }
    #endregion Process
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SDBHRError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    if ($auditMessage -like "No account found where [$($correlationField)] = [$($correlationValue)]") {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Skipped updating account with AccountReference: $($actionContext.References.Account | ConvertTo-Json). Reason: No changes. Reason: No account found where [$($correlationField)] = [$($correlationValue)]."
                IsError = $false
            })
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = $auditMessage
                IsError = $true
            })     
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
    else {
        $outputContext.Success = $true
    }

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}
