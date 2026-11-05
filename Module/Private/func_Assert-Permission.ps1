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
}
