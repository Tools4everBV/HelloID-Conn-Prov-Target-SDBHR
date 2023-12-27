#####################################################
# HelloID-Conn-Prov-Target-SDBHR-Delete
#
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Correlation values
$correlation = [PSCustomObject]@{
    CorrelationProperty = "personeelsNummer" # Has to match the name of the unique identifier
    CorrelationValue    = $aRef.Id # Has to match the value of the unique identifier
}

# Change mapping here
# See https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_Put for supported properties
$account = [PSCustomObject]@{
    EmailZakelijk = ""
}

# Define account properties to update
$updateAccountFields = @("EmailZakelijk")

# Define account properties to store in account data
$storeAccountFields = @("EmailZakelijk")

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
    #region Create access token and set as headers
    try {
        Write-Verbose "Creating SDBHR hash with Customer Number [$($c.CustomerNumber)]"

        $currentDateTime = (Get-Date).ToString("dd-MM-yyyy HH:mm:ss.fff")

        $baseString = "$($CurrentDateTime.Substring(0,10))|$($CurrentDateTime.Substring(11,12))|$($c.CustomerNumber)"
        $key = [System.Text.Encoding]::UTF8.GetBytes($c.ApiKey)
        $hmac256 = [System.Security.Cryptography.HMACSHA256]::new()
        $hmac256.key = $key
        $hash = $hmac256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseString))
        $hashedString = [System.Convert]::ToBase64String($hash)

        Write-Verbose "Creating Headers for SDBHR API calls"

        $headers = @{
            "Klantnummer"    = $c.CustomerNumber
            "Authentication" = "$($c.ApiUser):$($hashedString)"
            "Timestamp"      = $currentDateTime
            "Content-Type"   = "application/json"
            "Api-Version"    = "2.0"
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error creating Headers for SDBHR API calls with Customer Number [$($c.CustomerNumber)]. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Create access token and set as headers

    #region Get current account and verify if there are changes
    try {
        Write-Verbose "Querying account where [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]"

        $splatWebRequest = @{
            Uri             = "$($c.BaseUri)/medewerkersbasic/$($correlation.CorrelationValue)"
            Headers         = $headers
            Method          = "GET"
            ContentType     = "application/json;charset=utf-8"
            UseBasicParsing = $true
        }
        $currentAccount = $null
        $currentAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

        if ($null -eq $currentAccount) {
            throw "No account found where  [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]"
        }
        else {
            # Create previous account object to compare current data with specified account data
            $previousAccount = $currentAccount | Select-Object $updateAccountFields

            # Calculate changes between current data and provided data
            $splatCompareProperties = @{
                ReferenceObject  = @($previousAccount.PSObject.Properties)
                DifferenceObject = @($account.PSObject.Properties | Where-Object { $_.Name -in $updateAccountFields }) # Only select the properties to update
            }
            $changedProperties = $null
            $changedProperties = (Compare-Object @splatCompareProperties -PassThru)
            $oldProperties = $changedProperties.Where( { $_.SideIndicator -eq "<=" })
            $newProperties = $changedProperties.Where( { $_.SideIndicator -eq "=>" })

            if (($newProperties | Measure-Object).Count -ge 1) {
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
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        if ($errorMessage.AuditErrorMessage -Like "No account found where [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]") {
            $auditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "No account found where [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]. Possibly already deleted, skipped action."
                    IsError = $false
                })
        }
        else {
            $auditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Error querying account where [$($correlation.CorrelationProperty)] = [$($correlation.CorrelationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                    IsError = $true
                })
        }

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Get current account and verify if there are changes

    switch ($updateAction) {
        #region Update account
        "Update" {
            # Update account
            try {
                # Create custom account object for update and set with default properties and values
                $updateAccountObject = [PSCustomObject]@{}

                # Add the updated properties to the custom account object for update
                foreach ($newProperty in $newProperties) {
                    $updateAccountObject | Add-Member -MemberType NoteProperty -Name $newProperty.Name -Value $newProperty.Value -Force
                }

                $body = ($updateAccountObject | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = "$($c.BaseUri)/medewerkers/$($currentAccount.Id)"
                    Headers         = $headers
                    Method          = "PUT"
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                Write-Verbose "Updating account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]. Account object: $($updateAccountObject | ConvertTo-Json -Depth 10)"

                if (-not($dryRun -eq $true)) {
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    # Set aRef object for use in futher actions
                    $aRef = [PSCustomObject]@{
                        Id = $updatedAccount.Id
                    }

                    $auditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Successfully updated account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($updatedAccount.Id))]. Updated properties: $($changedPropertiesObject | ConvertTo-Json -Depth 10)"
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
        
                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Error updating account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]. Error Message: $($errorMessage.AuditErrorMessage). Account object: $($updateAccountObject | ConvertTo-Json -Depth 10)"
                        IsError = $true
                    })
            }

            break
        }
        #endregion Update account
        #region No changes to account
        "NoChanges" {
            Write-Verbose "No changes needed for account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"

            if (-not($dryRun -eq $true)) {
                # Set aRef object for use in futher actions
                $aRef = [PSCustomObject]@{
                    Id = $currentAccount.Id
                }

                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "No changes needed for account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: No changes needed for account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"
            }

            break
        }
        #endregion No changes to account
    }
    
    # Define ExportData with account fields and correlation property 
    $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
    # Add correlation property to exportdata
    $exportData | Add-Member -MemberType NoteProperty -Name $correlation.CorrelationProperty -Value $correlation.CorrelationValue -Force
    # Add aRef properties to exportdata
    foreach ($aRefProperty in $aRef.PSObject.Properties) {
        $exportData | Add-Member -MemberType NoteProperty -Name $aRefProperty.Name -Value $aRefProperty.Value -Force
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }
    
    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        PreviousAccount  = $previousAccount
        Account          = $account
    
        # Optionally return data for use in other systems
        ExportData       = $exportData
    }
    
    Write-Output ($result | ConvertTo-Json -Depth 10)  
}