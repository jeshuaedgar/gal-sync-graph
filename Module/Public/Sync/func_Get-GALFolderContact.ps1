function Get-GALFolderContact {
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Mailbox,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias("id")][string]$FolderId
    )
    process {
        $select = $script:contactFields.Keys -join ","
        $expand = [System.Uri]::EscapeDataString("singleValueExtendedProperties(`$filter=id eq '$($script:sourceIdProperty)')")
        $contacts = New-GraphRequest -Endpoint "$(Get-FolderEndpoint -Mailbox $Mailbox -FolderId $FolderId)/contacts?`$select=$select&`$expand=$expand&`$top=999" -All | ForEach-Object {
            $contact = [ordered]@{
                id       = $_.id
                sourceId = ($_.singleValueExtendedProperties | Select-Object -First 1).value
            }
            foreach ($field in $script:contactFields.Keys) {
                $contact[$field] = $_.$field
            }
            [pscustomobject]$contact
        }
        Write-VerboseEvent "Found $(@($contacts).Count) contacts in $Mailbox"
        return $contacts
    }
}
