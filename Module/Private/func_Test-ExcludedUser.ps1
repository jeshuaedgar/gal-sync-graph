function Test-ExcludedUser {
    param (
        [parameter(Mandatory)][object]$User,
        [string[]]$ExcludeUser
    )
    return [bool](@($User.id, $User.mail, $User.userPrincipalName) | Where-Object { $_ -and $_ -in $ExcludeUser })
}
