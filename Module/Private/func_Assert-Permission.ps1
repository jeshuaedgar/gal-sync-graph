function Assert-Permission {
    param (
        [switch]$GroupMember,
        [switch]$OrgContact
    )
    $roles = (Get-AccessToken).Roles
    $required = [ordered]@{
        "User.Read.All" = "User.Read.All", "User.ReadWrite.All", "Directory.Read.All", "Directory.ReadWrite.All"
    }
    if ($GroupMember) {
        $required["GroupMember.Read.All"] = "GroupMember.Read.All", "GroupMember.ReadWrite.All", "Group.Read.All", "Group.ReadWrite.All", "Directory.Read.All", "Directory.ReadWrite.All"
    }
    if ($OrgContact) {
        $required["OrgContact.Read.All"] = "OrgContact.Read.All", "Directory.Read.All", "Directory.ReadWrite.All"
    }
    $missing = $required.Keys | Where-Object { -not ($required[$_] | Where-Object { $_ -in $roles }) }
    if ($missing) {
        throw "Missing the $($missing -join ", ") role(s), please update your application and rerun the script"
    }
    # not a hard requirement: Exchange RBAC for Applications can grant mailbox access without an Entra role
    if ($roles -notcontains "Contacts.ReadWrite") {
        Write-VerboseEvent "The token has no Contacts.ReadWrite role, assuming mailbox access is granted through Exchange RBAC for Applications"
    }
}
