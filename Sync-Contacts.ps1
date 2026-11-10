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
    if (-not $LogPath -and $ConfigFile) {
        $LogPath = (Get-Content -Path $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable).LogPath
    }
    if ($LogPath) {
        Start-Transcript -OutputDirectory $LogPath -WhatIf:$false | Out-Null
        $transcript = $true
    }

    # the repository copy when run from a clone, otherwise the module installed from the PowerShell Gallery
    $repositoryModule = Join-Path $PSScriptRoot "Module/GAL-Sync.psd1"
    Import-Module ((Test-Path $repositoryModule) ? $repositoryModule : "GAL-Sync") -Force

    $parameters = @{} + $PSBoundParameters
    $parameters.Remove("LogPath")
    $results = @(Start-GALSync @parameters)
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
