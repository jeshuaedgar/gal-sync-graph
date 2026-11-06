function Get-GALGroupMember {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)][string]$Group
    )
    $groupId = Get-GroupId -Group $Group
    Write-VerboseEvent "Getting members of $Group"
    # casting transitiveMembers is an advanced query, which needs ConsistencyLevel and $count
    $members = New-GraphRequest -Endpoint "/groups/$($groupId)/transitiveMembers/microsoft.graph.user?`$count=true&`$top=999&`$select=id,displayName,mail,userPrincipalName,accountEnabled,userType" -Headers @{ ConsistencyLevel = "eventual" } -All
    return $members
}
