function Get-GroupId {
    param (
        [parameter(Mandatory)][string]$Group
    )
    $groupId = [guid]::Empty
    if ([guid]::TryParse($Group, [ref]$groupId)) {
        return $groupId.ToString()
    }
    $filter = [uri]::EscapeDataString("displayName eq '$($Group.Replace("'", "''"))'")
    $groups = @(New-GraphRequest -Endpoint "/groups?`$filter=$filter&`$select=id" -All)
    if (-not $groups) {
        throw "Group $Group was not found"
    }
    if ($groups.Count -gt 1) {
        throw "Found $($groups.Count) groups named $Group, please use the object ID of the group instead"
    }
    return $groups[0].id
}
