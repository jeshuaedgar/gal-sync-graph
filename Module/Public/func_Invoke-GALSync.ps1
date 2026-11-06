function Invoke-GALSync {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "TargetGroup")]
    param (
        [parameter(Mandatory)][string]$ContactFolderName,

        [parameter(Mandatory, ParameterSetName = "AllUsers")][switch]$AllUsers,
        [parameter(Mandatory, ParameterSetName = "TargetGroup")][string]$TargetGroup,
        [parameter(Mandatory, ParameterSetName = "TargetMailbox")][string[]]$TargetMailbox,

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

        [ValidateRange(1, 16)][int]$ThrottleLimit = 4
    )
    function Split-List ($Values) {
        return $Values | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    Assert-Permission -GroupMember:([bool]($TargetGroup -or $SourceGroup)) -OrgContact:$IncludeOrgContacts

    $excluded = @(Split-List $ExcludeUser)
    $directorySplat = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -in (Get-Command Get-GALDirectoryUser).Parameters.Keys) {
            $directorySplat[$key] = $PSBoundParameters[$key]
        }
    }
    $directorySplat.ExcludeUser = $excluded
    $directoryUsers = @(Get-GALDirectoryUser @directorySplat)
    if (-not $directoryUsers) {
        throw "No directory users match the filters, stopping because syncing an empty list would remove every contact"
    }

    $mailboxes = @(Get-TargetMailbox -AllUsers:$AllUsers -TargetGroup $TargetGroup -TargetMailbox @(Split-List $TargetMailbox) -ExcludeUser $excluded)
    if (-not $mailboxes) {
        Write-Warning "No target mailboxes found"
        return
    }
    Write-VerboseEvent "Syncing $($directoryUsers.Count) contacts to $($mailboxes.Count) mailbox(es), $ThrottleLimit at a time"

    $syncSplat = @{
        ContactFolderName = $ContactFolderName
        DirectoryUser     = $directoryUsers
        WhatIf            = [bool]$WhatIfPreference
    }
    $manifest = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath "GAL-Sync.psd1"
    $session = $script:galSyncData
    $verbose = $VerbosePreference
    $results = $mailboxes | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $VerbosePreference = $using:verbose
        $module = Get-Module -Name GAL-Sync
        if (-not $module) {
            # share the connection (and token refreshes) with the runspace that started the sync
            $module = Import-Module -Name $using:manifest -PassThru -Verbose:$false
            & $module { param ($session) $script:galSyncData = $session } $using:session
        }
        $syncSplat = $using:syncSplat
        Sync-GALMailbox -Mailbox $_ @syncSplat
    }
    return $results
}
