[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "CredentialPath", Justification = "File path, not a secret.")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "", Justification = "Parameters are read through PSBoundParameters.")]
param (
    [string]$ConfigFile,
    [string]$LogPath,

    [string]$TenantId,
    [string]$ClientId,
    [string]$CertificateThumbprint,
    [string]$CredentialPath,

    [string]$ContactFolderName,
    [switch]$AllUsers,
    [string]$TargetGroup,
    [string[]]$TargetMailbox,
    [string]$SourceGroup,
    [string[]]$ExcludeUser,
    [string]$UserFilter,
    [switch]$ExcludeHiddenFromAddressList,
    [switch]$IncludeOrgContacts,
    [switch]$BusinessPhoneAsMobile,
    [switch]$IncludeUsersWithoutPhone,
    [switch]$IncludeUsersWithoutEmail,
    [switch]$IncludeDisabledUsers,
    [switch]$IncludeGuests,
    [int]$ThrottleLimit
)

$ErrorActionPreference = "Stop"
$exitCode = 0
$transcript = $false

try {
    $settings = @{}
    if ($ConfigFile) {
        $fileSettings = Get-Content -Path $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        foreach ($key in $fileSettings.Keys) {
            if ($MyInvocation.MyCommand.Parameters.ContainsKey($key)) { $settings[$key] = $fileSettings[$key] }
            else { Write-Warning "Ignoring unknown setting $key in $ConfigFile" }
        }
    }
    foreach ($key in $PSBoundParameters.Keys) { $settings[$key] = $PSBoundParameters[$key] }

    if ($settings.LogPath) {
        Start-Transcript -OutputDirectory $settings.LogPath -WhatIf:$false | Out-Null
        $transcript = $true
    }
    # settings can come from -ConfigFile, so check them here instead of making the parameters mandatory
    if (-not $settings.TenantId -or -not $settings.ContactFolderName) {
        throw "TenantId and ContactFolderName are required"
    }
    if (@($settings.AllUsers, $settings.TargetGroup, $settings.TargetMailbox | Where-Object { $_ }).Count -ne 1) {
        throw "Use exactly one of AllUsers, TargetGroup or TargetMailbox"
    }

    Import-Module (Join-Path $PSScriptRoot "Module/GAL-Sync.psd1") -Force
    $connectParameters = (Get-Command Connect-GALSync).Parameters.Keys
    $syncParameters = (Get-Command Invoke-GALSync).Parameters.Keys
    $connect = @{}
    $sync = @{}
    foreach ($key in $settings.Keys) {
        # a switch that is turned off would still select a parameter set
        if ($settings[$key] -is [bool] -and -not $settings[$key]) { continue }
        if ($key -in $syncParameters) { $sync[$key] = $settings[$key] }
        elseif ($key -in $connectParameters) { $connect[$key] = $settings[$key] }
    }

    $connection = Connect-GALSync @connect
    Write-Output "Connected to tenant $($connection.TenantId) as $($connection.ClientId)"
    $results = @(Invoke-GALSync @sync)
    $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
    if ($results | Where-Object { $_.Status -eq "Failed" }) {
        $exitCode = 1
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
}
finally {
    if ($transcript) {
        Stop-Transcript -WhatIf:$false | Out-Null
    }
}
exit $exitCode
