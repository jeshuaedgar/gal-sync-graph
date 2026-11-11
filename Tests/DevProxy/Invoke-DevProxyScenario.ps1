#Requires -Version 7.6
<#
.SYNOPSIS
    Manual check of the retry and throttling handling, using Dev Proxy.
.DESCRIPTION
    Starts Dev Proxy with Tests/DevProxy/devproxyrc.json (not as the system proxy), runs Invoke-GALSync
    through it for three mailboxes and checks the results. Dev Proxy answers instead of Microsoft Graph,
    so no tenant is needed. See README.md in this folder.
#>
[CmdletBinding()]
param (
    [int]$Port = 8000
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command devproxy -ErrorAction SilentlyContinue)) {
    throw "Dev Proxy is not installed or not on the PATH, see https://aka.ms/devproxy"
}
devproxy status *> $null
if ($LASTEXITCODE -eq 0) {
    throw "Dev Proxy is already running, stop it first with: devproxy stop"
}

Import-Module (Join-Path $PSScriptRoot "../../Module/GAL-Sync.psd1") -Force
$proxyUrl = "http://127.0.0.1:$Port"
$previousProxy = $env:HTTPS_PROXY
$failures = New-Object System.Collections.Generic.List[string]
try {
    devproxy --config-file (Join-Path $PSScriptRoot "devproxyrc.json") --port $Port --as-system-proxy false --detach | Out-Null
    $deadline = [datetime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        devproxy status *> $null
    } until ($LASTEXITCODE -eq 0 -or [datetime]::UtcNow -gt $deadline)
    if ($LASTEXITCODE -ne 0) { throw "Dev Proxy did not start within 30 seconds" }

    # only this process goes through the proxy
    $env:HTTPS_PROXY = $proxyUrl
    $credential = New-Object System.Management.Automation.PSCredential ("22222222-2222-2222-2222-222222222222", (ConvertTo-SecureString "secret" -AsPlainText -Force))
    Connect-GALSync -TenantId "contoso.onmicrosoft.com" -Credential $credential | Out-Null

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = @(Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com", "bob@contoso.com", "carl@contoso.com" -WarningAction SilentlyContinue)
    $seconds = [int]$stopwatch.Elapsed.TotalSeconds
    $results | Format-Table Mailbox, Status, Created, Failed, Message -Wrap | Out-Host

    function Test-Result ($Mailbox, $Status, $Message, $Created) {
        $result = $results | Where-Object { $_.Mailbox -eq $Mailbox }
        if ($result.Status -ne $Status) { $failures.Add("$Mailbox should be $Status but is $($result.Status)") }
        if ($Message -and $result.Message -notlike $Message) { $failures.Add("$Mailbox message should match $Message but is: $($result.Message)") }
        if ($null -ne $Created -and $result.Created -ne $Created) { $failures.Add("$Mailbox should have created $Created contact(s) but created $($result.Created)") }
    }
    # ann: throttled folder listing and a throttled batch item, then succeeds
    Test-Result -Mailbox "ann@contoso.com" -Status "Succeeded" -Created 2
    # bob: always throttled, gives up after the retries
    Test-Result -Mailbox "bob@contoso.com" -Status "Failed" -Message "*TooManyRequests*"
    # carl: access denied, with the hint about the permission
    Test-Result -Mailbox "carl@contoso.com" -Status "Failed" -Message "*ErrorAccessDenied*Exchange RBAC*"
    # Retry-After and the backoff are really waited for (bob alone takes 5 seconds)
    if ($seconds -lt 5) { $failures.Add("The run took $seconds seconds, the retries did not wait") }
}
finally {
    $env:HTTPS_PROXY = $previousProxy
    Disconnect-GALSync
    devproxy stop *> $null
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Host "Dev Proxy scenario passed in $seconds seconds"
