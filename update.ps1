#####################################################
# HelloID-Conn-Prov-Target-SDBHR-Update
# PowerShell V2
# Version: 1.0.0
# See https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_Put for supported properties
#####################################################

# Set to false at start, set to true when no error occured
$outputContext.Success = $false

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Define account properties to update # delete after creation of update script
$updateAccountFields = $actionContext.Data.PSObject.Properties.Name

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ""
        }
        if ($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") -or $($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException")) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

try {
    Write-Verbose "Creating SDBHR hash with Customer Number [$($actionContext.Configuration.CustomerNumber)]"

    $currentDateTime = (Get-Date).ToString("dd-MM-yyyy HH:mm:ss.fff")

    $baseString = "$($CurrentDateTime.Substring(0,10))|$($CurrentDateTime.Substring(11,12))|$($actionContext.Configuration.CustomerNumber)"
    $key = [System.Text.Encoding]::UTF8.GetBytes($actionContext.Configuration.ApiKey)
    $hmac256 = [System.Security.Cryptography.HMACSHA256]::new()
    $hmac256.key = $key
    $hash = $hmac256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseString))
    $hashedString = [System.Convert]::ToBase64String($hash)

    Write-Verbose "Creating Headers for SDBHR API calls"

    $headers = @{
        "Klantnummer"    = $actionContext.Configuration.CustomerNumber
        "Authentication" = "$($actionContext.Configuration.ApiUser):$($hashedString)"
        "Timestamp"      = $currentDateTime
        "Content-Type"   = "application/json"
        "Api-Version"    = "2.0"
    }
    $accountId = $actionContext.References.Account.Id
    Write-Verbose "Querying account where [Id] = [$($accountId)]"
    if ($null -eq $accountId) {
        throw "Not correlated"
    }
    $splatWebRequest = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/medewerkersbasic/$($AccountId)"
        Headers         = $headers
        Method          = "GET"
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
    }
    $currentAccount = $null
    $currentAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false
    Write-Verbose -verbose $currentAccount
    if ($null -eq $currentAccount) {
        throw "No account found where  [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]"
    }
    else {
        # Create previous account object to compare current data with specified account data
        $previousAccount = $currentAccount | Select-Object $updateAccountFields
        $outputContext.PreviousData = $previousAccount
        
        # Calculate changes between current data and provided data
        $splatCompareProperties = @{
            ReferenceObject  = @($previousAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
            #DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update

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
            Write-Verbose "Changed properties: $($changedPropertiesObject | ConvertTo-Json)"

            $updateAction = 'Update'
        }
        else {
            Write-Verbose "No changed properties"

            $updateAction = 'NoChanges'
        }
    }
    
    # Process
    switch ($updateAction) {
        #region Update account
        "Update" {
            # Update account
            $uri = "$($actionContext.Configuration.BaseUri)/medewerkers/$($currentAccount.Id)/$($MutationDate)"
       
            try {
                # Create custom account object for update and set with default properties and values
                $updateAccountObject = [PSCustomObject]@{}

                # Add the updated properties to the custom account object for update
                foreach ($newProperty in $newProperties) {
                    $updateAccountObject | Add-Member -MemberType NoteProperty -Name $newProperty.Name -Value $newProperty.Value -Force
                }

                $body = ($updateAccountObject | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = $uri
                    Headers         = $headers
                    Method          = "PUT"
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    #ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                Write-Verbose "Updating account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]. Account object: $($updateAccountObject | ConvertTo-Json -Depth 10)"

                if (-not($actionContext.DryRun -eq $true)) {
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    $outputContext.success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Successfully updated account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($updatedAccount.Id))]. Updated properties: $($changedPropertiesObject | ConvertTo-Json -Depth 10)"
                            #Message = 'Update account was successful'
                            IsError = $false
                        })
                    
                }
                else {
                    Write-Warning "DryRun: Would update account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]. Updated properties: $($changedPropertiesObject | ConvertTo-Json -Depth 10)"
                }

                break
            }
            catch {
                $ex = $PSItem
                $errorMessage = Get-ErrorMessage -ErrorObject $ex

                Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
                $outputContext.Success = $false
                $auditMessage = "Could not update SDB account. Error: $($errorMessage)"
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $auditMessage
                        IsError = $true
                    })
                
            }

            break
        }
        #endregion Update account
        #region No changes to account
        "NoChanges" {
            Write-Verbose "No changes needed for account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"
            
            $outputContext.success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })



            break
        }
        #endregion No changes to account
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-not($outputContext.success -eq $false)) {
        $success = $true
    }
}