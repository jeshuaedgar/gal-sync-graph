function Get-GALContactFolder {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)][string]$Mailbox,
        [string]$Name
    )
    Write-VerboseEvent "Getting contact folders for $Mailbox"
    $expand = [System.Uri]::EscapeDataString("singleValueExtendedProperties(`$filter=id eq '$($script:folderMarker.id)')")
    $folders = New-GraphRequest -Endpoint "$(Get-FolderEndpoint -Mailbox $Mailbox)?`$select=displayName&`$expand=$expand&`$top=100" -All | Where-Object {
        -not $Name -or $_.displayName -eq $Name
    } | ForEach-Object {
        [pscustomobject]@{
            id          = $_.id
            displayName = $_.displayName
            mailBox     = $Mailbox
            isManaged   = [bool]($_.singleValueExtendedProperties | Where-Object { $_.value -eq $script:folderMarker.value })
        }
    }
    return $folders
}
