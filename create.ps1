#####################################################
# HelloID-Conn-Prov-Target-SDBHR-Create
# PowerShell V2
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
            throw  "Correlation is enabled but not configured correctly"
        }

        if ([string]::IsNullOrEmpty($correlationValue)) {
            throw "The correlation value for [$correlationProperty] is empty. This is likely a mapping issue"
        }
    }
    else {
        throw "Configuration of correlation is mandatory"
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
        throw = "Error querying account where [$correlationProperty)] = [$correlationValue]"
    }
    Write-Verbose "Correlating to account [$($currentAccount.RoepNaam) $($currentAccount.AchterNaam) ($($currentAccount.Id))]"

    $outputContext.AccountReference = [PSCustomObject]@{
        Id = $currentAccount.Id
    }
    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Warning "DryRun: Would correlate to account on field [$correlationProperty] with value: [$($correlationValue)]"
    }
    # Process
    if (-not($actionContext.DryRun -eq $true)) {  
        Write-Verbose 'Correlating user account'
       
        $auditLogMessage = "Successfully correlated account on field [$correlationProperty] with value: [$($correlationValue)]" #"$action account was successful. AccountReference is: [$($outputContext.AccountReference)"
        $outputContext.success = $true
        $outputContext.AccountCorrelated = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = 'CorrelateAccount'
                Message = $auditLogMessage
                IsError = $false
            })  
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Warning "Error correlating account on field [$($correlationField)] with value: [$($correlationValue)] at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "CorrelateAccount"
            Message = "Error correlating account on field [$($correlationField)] with value: [$($correlationValue)]: $($errorMessage.AuditErrorMessage)"
            IsError = $true
        })
}