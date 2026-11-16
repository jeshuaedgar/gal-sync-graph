function Start-GALSync {
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "CredentialPath", Justification = "File path, not a secret.")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "", Justification = "Parameters are read through PSBoundParameters.")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "", Justification = "Invoke-GALSync calls ShouldProcess, through the inherited WhatIfPreference.")]
    param (
        [string]$ConfigFile,
        [System.Collections.IDictionary]$Settings,

        [switch]$ManagedIdentity,
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint,
        [string]$CredentialPath,
        [pscredential]$Credential,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

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
    $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    $parameterNames = @($MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -notin $common -and $_ -notin "ConfigFile", "Settings" })
    # Credential and Certificate are objects, so they can only be passed as parameters.
    # LogPath belongs to Sync-Contacts.ps1, so settings files written for it are accepted here too
    $known = @($parameterNames | Where-Object { $_ -notin "Credential", "Certificate" }) + @("WhatIf", "LogPath")

    if ($ConfigFile -and $Settings) {
        throw "Use -ConfigFile or -Settings, not both"
    }
    $source = $Settings
    $sourceName = "the settings"
    if ($ConfigFile) {
        $source = Get-Content -Path $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $sourceName = $ConfigFile
    }

    $merged = @{}
    if ($source) {
        # a typo would otherwise silently sync with the wrong settings
        $unknown = @($source.Keys | Where-Object { $_ -notin $known })
        if ($unknown) {
            throw "Unknown setting(s) in $($sourceName): $($unknown -join ", "). Valid settings are: $(($known | Sort-Object) -join ", ")"
        }
        foreach ($key in $source.Keys) { $merged[$key] = $source[$key] }
    }
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -in $parameterNames) { $merged[$key] = $PSBoundParameters[$key] }
    }

    $values = @{}
    foreach ($key in $merged.Keys) {
        $value = $merged[$key]
        if ($value -is [switch]) { $value = $value.IsPresent }
        # a switch that is turned off would still select a parameter set, and empty values mean "not set"
        if ($null -eq $value -or ($value -is [bool] -and -not $value) -or ($value -is [string] -and -not $value.Trim()) -or ($value -is [array] -and -not ($value | Where-Object { $_ }))) {
            continue
        }
        $values[$key] = $value
    }
    if ($values.WhatIf -and -not $PSBoundParameters.ContainsKey("WhatIf")) { $WhatIfPreference = $true }

    if (-not $values.ContactFolderName) {
        throw "ContactFolderName is required"
    }
    if (@("AllUsers", "TargetGroup", "TargetMailbox" | Where-Object { $values.ContainsKey($_) }).Count -ne 1) {
        throw "Use exactly one of AllUsers, TargetGroup or TargetMailbox"
    }
    if (-not $values.ManagedIdentity -and -not $values.TenantId) {
        throw "TenantId is required, unless you sign in with ManagedIdentity"
    }

    $syncParameters = (Get-Command Invoke-GALSync).Parameters.Keys
    $connect = @{}
    $sync = @{}
    foreach ($key in $values.Keys | Where-Object { $_ -notin "WhatIf", "LogPath" }) {
        if ($key -in $syncParameters) { $sync[$key] = $values[$key] }
        else { $connect[$key] = $values[$key] }
    }
    if ($connect.ManagedIdentity) {
        $connect = @{ ManagedIdentity = $true }
    }

    $connection = Connect-GALSync @connect
    Write-VerboseEvent "Connected to tenant $($connection.TenantId) as $($connection.ClientId)"
    Invoke-GALSync @sync
}
