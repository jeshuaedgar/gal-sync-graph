[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "", Justification = "Get-AutomationConnection returns encrypted connection fields as plain strings.")]
param (
    [string]$ConfigurationVariable = "GALSyncConfig",
    [bool]$WhatIfMode = $false,
    # print support information for a GitHub issue instead of syncing, optionally checking read access to one mailbox
    [bool]$Diagnostic = $false,
    [string]$DiagnosticMailbox
)

$ErrorActionPreference = "Stop"
# Azure Automation keeps verbose records only when "Log verbose records" is on for the runbook
$VerbosePreference = "Continue"

$problem = $null
$signIn = @{ ManagedIdentity = $true }
try {
    $settings = Get-AutomationVariable -Name $ConfigurationVariable | ConvertFrom-Json -AsHashtable
    $settings.WhatIf = $settings.WhatIf -or $WhatIfMode

    # sign in with the managed identity, or with the app registration in the GALSync connection that AutomationConnection names
    if ($name = $settings.AutomationConnection) {
        $settings.Remove("AutomationConnection")
        $c = Get-AutomationConnection -Name $name
        if (-not ($c.TenantId -and $c.ClientId -and ($c.ClientSecret -or $c.CertificateName))) {
            throw "Connection $name needs TenantId, ClientId and a ClientSecret or CertificateName"
        }
        $signIn = @{ TenantId = $c.TenantId }
        if ($c.CertificateName) {
            $signIn.ClientId = $c.ClientId
            $signIn.Certificate = Get-AutomationCertificate -Name $c.CertificateName
        }
        else {
            $signIn.Credential = [pscredential]::new($c.ClientId, (ConvertTo-SecureString $c.ClientSecret -AsPlainText -Force))
        }
    }
}
catch {
    if (-not $Diagnostic) { throw }
    $problem = "Reading the settings or the connection failed: $($_.Exception.Message)"
}

if ($Diagnostic) {
    if (-not $problem) {
        try { Connect-GALSync @signIn | Out-Null }
        catch { $problem = "Signing in failed: $($_.Exception.Message)" }
    }
    # one string in the job output, to copy into the issue
    Get-GALDiagnostic -Mailbox $DiagnosticMailbox -Problem $problem
    return
}

$results = @(Start-GALSync -Settings $settings @signIn)

# a table for people in the verbose stream, one JSON line for scripts in the output
Write-Verbose ($results | Format-Table -AutoSize | Out-String -Width 200)
ConvertTo-Json -InputObject $results -Compress -Depth 2

$failed = @($results | Where-Object Status -eq "Failed")
if ($failed) {
    throw "$($failed.Count) of $($results.Count) mailbox(es) failed to sync"
}
