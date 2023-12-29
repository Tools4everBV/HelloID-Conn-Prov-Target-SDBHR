#####################################################
# HelloID-Conn-Prov-Target-SDBHR-Create
#
# See https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_Put for supported properties
#####################################################

# AccountReference must have a value for dryRun
$outputContext.AccountReference = "Unknown"

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Define account properties to store in account data
$storeAccountFields = $actionContext.Data.PSObject.Properties.Name # all mapped fields

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
    # Correlation setup
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationProperty = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($correlationProperty)) {
            $message =  "Correlation is enabled but not configured correctly"
            Write-Warning $message
            throw $message
        }

        if ([string]::IsNullOrEmpty($correlationValue)) {
            $Message = "The correlation value for [$correlationProperty] is empty. This is likely a mapping issue"
            Write-Warning $message
            throw $message
        }
    }
    else {
        # should be a throw exception
        $message = "Configuration of correlation is mandatory"
        Write-Warning $message
        throw $message
    }

    Write-Verbose "Creating SDB HR hash with Customer Number [$($actionContext.Configuration.CustomerNumber)]"

    $currentDateTime = (Get-Date).ToString("dd-MM-yyyy HH:mm:ss.fff")

    $baseString = "$($CurrentDateTime.Substring(0,10))|$($CurrentDateTime.Substring(11,12))|$($actionContext.Configuration.CustomerNumber)"
    $key = [System.Text.Encoding]::UTF8.GetBytes($actionContext.Configuration.ApiKey)
    $hmac256 = [System.Security.Cryptography.HMACSHA256]::new()
    $hmac256.key = $key
    $hash = $hmac256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseString))
    $hashedString = [System.Convert]::ToBase64String($hash)

    Write-Verbose "Creating Headers for SDB HR API calls"

    $headers = @{
        "Klantnummer"    = $actionContext.Configuration.CustomerNumber
        "Authentication" = "$($actionContext.Configuration.ApiUser):$($hashedString)"
        "Timestamp"      = $currentDateTime
        "Content-Type"   = "application/json"
        "Api-Version"    = "2.0"
    }

    Write-Verbose "Querying account where [$correlationProperty] = [$correlationValue]"

    $splatWebRequest = @{
        Uri             = "$($actionContext.Configuration.BaseUri)/medewerkersbasic/$correlationValue"
        Headers         = $headers
        Method          = "GET"
        ContentType     = "application/json;charset=utf-8"
        UseBasicParsing = $true
    }
    $currentAccount = $null
    $currentAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

    if ($null -eq $currentAccount) {
        $message = "Error querying account where [$correlationProperty)] = [$correlationValue]"
        Write-Warning $message
        throw $message
    } else {
        Write-Verbose "Correlating to account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"

        $outputContext.AccountReference = [PSCustomObject]@{
            Id = $currentAccount.Id
        }

        if ($dryRun -eq $true) {
            Write-Warning "DryRun: Would correlate to account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"\
        }

        # Define ExportData with account fields and correlation property
        #$outputContext.Data = $currentAccount.PsObject.Copy() | Select-Object $storeAccountFields
        $outputContext.Data = $currentAccount | Select-Object $storeAccountFields # Test of this works ok
    }

    $auditLogs.Add([PSCustomObject]@{
        Action  = "CorrelateAccount"
        Message = "Successfully correlated account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"
        IsError = $false
    })
    $outputContext.AccountCorrelated = $true
    $outputContext.Success = $true
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Warning "Error correlating account at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "CorrelateAccount"
            Message = "Error correlating account: $($errorMessage.AuditErrorMessage)"
            IsError = $true
        })
}