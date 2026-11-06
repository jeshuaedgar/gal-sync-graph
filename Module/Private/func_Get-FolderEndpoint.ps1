function Get-FolderEndpoint {
    param (
        [parameter(Mandatory)][string]$Mailbox,
        [string]$FolderId
    )
    $endpoint = "/users/$([System.Uri]::EscapeDataString($Mailbox))/contactFolders"
    if ($FolderId) {
        $endpoint += "/$([System.Uri]::EscapeDataString($FolderId))"
    }
    return $endpoint
}
