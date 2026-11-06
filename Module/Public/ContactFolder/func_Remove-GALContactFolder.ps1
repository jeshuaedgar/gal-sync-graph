function Remove-GALContactFolder {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory)][string]$Mailbox,
        [parameter(Mandatory)][string]$Name
    )
    foreach ($folder in Get-GALContactFolder -Mailbox $Mailbox -Name $Name | Where-Object { $_.isManaged }) {
        if ($PSCmdlet.ShouldProcess("$Mailbox\$Name", "Remove contact folder and all contacts in it")) {
            New-GraphRequest -Method Delete -Endpoint (Get-FolderEndpoint -Mailbox $Mailbox -FolderId $folder.id) | Out-Null
        }
    }
}
