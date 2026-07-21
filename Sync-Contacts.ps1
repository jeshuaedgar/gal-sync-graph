param (
    [CmdletBinding()]
    [parameter(Mandatory)][System.IO.FileInfo]$CredentialPath,
    [parameter(Mandatory)][string]$Tenant,
    [parameter(Mandatory)][string]$ContactFolderName,
    [string]$AzureADGroup,
    [string[]]$MailboxList,
    [switch]$Directory,
    [string]$LogPath,
    [switch]$ContactsWithoutPhoneNumber,
    [switch]$ContactsWithoutEmail,
    [switch]$UseGraphSDK
)

Set-Variable -Name UseGraphSDK -Value $UseGraphSDK -Scope Global -Option ReadOnly -Force

if ($LogPath) {
    Start-Transcript -OutputDirectory $LogPath
}

Write-Verbose "Using $(If ($UseGraphSDK) {"Graph SDK"} Else {"raw REST requests"}) for connection"
If ($UseGraphSDK) { Import-Module Microsoft.Graph.PersonalContacts }

Import-Module .\Module\GAL-Sync.psm1 -Force
Connect-GALSync -CredentialFile $CredentialPath -Tenant $Tenant

# Get users based on input
if ($Directory) { $mailBoxesToSync = (Get-GALContacts -ContactsWithoutPhoneNumber $true).emailaddresses | Select-Object -ExpandProperty address }
elseif ($AzureADGroup) { $mailBoxesToSync = Get-GALAADGroupMembers -Name $AzureADGroup | Select-Object -ExpandProperty mail }
elseif ($MailboxList -is [array]) { $mailBoxesToSync = $MailboxList }
else { Write-Error "No valid mailbox input"; exit 1 }

$GALContacts = Get-GALContacts -ContactsWithoutPhoneNumber $ContactsWithoutPhoneNumber -ContactsWithoutEmail $ContactsWithoutEmail

foreach ($mailBox in $mailBoxesToSync) {
    try {
        Sync-GALContacts -Mailbox $mailBox -ContactList $GALContacts -ContactFolderName $ContactFolderName
    }
    catch {
        Write-LogEvent -Level Error -Message $_.Exception.Message
        Write-LogEvent -Level Error -Message "Failed to sync mailbox: $($mailBox)"
    }
}
if ($LogPath) {
    Stop-Transcript
}