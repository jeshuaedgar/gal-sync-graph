param (
    [string]$ConfigurationVariable = "GALSyncConfig",
    [bool]$WhatIfMode = $false
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$settings = Get-AutomationVariable -Name $ConfigurationVariable | ConvertFrom-Json -AsHashtable
if ($WhatIfMode) {
    $settings.WhatIf = $true
}

Import-Module -Name GAL-Sync
$connectParameters = (Get-Command Connect-GALSync).Parameters.Keys
$syncParameters = (Get-Command Invoke-GALSync).Parameters.Keys
$connect = @{ ManagedIdentity = $true }
$sync = @{}
foreach ($key in $settings.Keys) {
    # a switch that is turned off would still select a parameter set
    if ($settings[$key] -is [bool] -and -not $settings[$key]) { continue }
    if ($key -in $syncParameters) { $sync[$key] = $settings[$key] }
    elseif ($key -in $connectParameters) { $connect[$key] = $settings[$key] }
    else { Write-Warning "Ignoring unknown setting $key in $ConfigurationVariable" }
}

$connection = Connect-GALSync @connect
Write-Output "Connected to tenant $($connection.TenantId) as $($connection.ClientId)"

$results = @(Invoke-GALSync @sync)
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$failed = @($results | Where-Object { $_.Status -eq "Failed" })
if ($failed) {
    throw "$($failed.Count) of $($results.Count) mailbox(es) failed to sync"
}
