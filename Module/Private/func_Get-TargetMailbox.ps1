function Get-TargetMailbox {
    param (
        [switch]$AllUsers,
        [string]$TargetGroup,
        [string[]]$TargetMailbox,
        [string[]]$ExcludeUser
    )
    $mailboxes = if ($TargetMailbox) {
        $TargetMailbox | Where-Object { $_ -notin $ExcludeUser }
    }
    else {
        $candidates = if ($AllUsers) {
            New-GraphRequest -Endpoint "/users?`$select=id,mail,userPrincipalName,accountEnabled,userType&`$top=999" -All
        }
        else {
            Get-GALGroupMember -Group $TargetGroup
        }
        $candidates | Where-Object {
            $_.accountEnabled -and $_.mail -and $_.userType -ne "Guest" -and -not (Test-ExcludedUser -User $_ -ExcludeUser $ExcludeUser)
        } | ForEach-Object { $_.userPrincipalName }
    }
    return $mailboxes | Sort-Object -Unique
}
