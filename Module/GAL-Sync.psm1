#region discover module name
$ScriptPath = $PSScriptRoot
$ModuleName = $MyInvocation.MyCommand.Module.Name
$ModuleName = $ExecutionContext.SessionState.Module
Write-Verbose "Loading module $ModuleName..."
#endregion discover module name

#load variables for module
Write-Verbose "Creating modules variables..."
$script:galSyncData = @{
    Tenant          = $null
    GraphAuthHeader = $null
    TokenExpiration = $null
}

#load functions
try {
    foreach ($Scope in 'Private', 'Public') {
        Get-ChildItem (Join-Path -Path $ScriptPath -ChildPath $Scope) -Recurse -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
            if ($Scope -eq 'Public') {
                Export-ModuleMember -Function ($_.BaseName -Split "_")[1] -ErrorAction Stop
            }
        }
    }
}
catch {
    throw
}