# GAL (Global Address List) Sync using Graph | [![CI](https://github.com/JeshuaEdgar/gal-sync-graph/actions/workflows/ci.yml/badge.svg)](https://github.com/JeshuaEdgar/gal-sync-graph/actions/workflows/ci.yml)

Ever wondered who called you from your organisation on your iPhone/Android device? Microsoft makes it unnecessarily hard to sync Global Address List contacts to your phone. Yes Outlook works great... but it does not sync with your native contacts app, so pretty useless when it comes to resolving the caller ID.

GAL-Sync puts your colleagues in a contact folder in every mailbox, and keeps that folder up to date. The folder syncs to phones like any other contacts.

## [Changelog](CHANGELOG.md)

## How it works

- Users from the directory (enabled members with an email address and a phone number) become contacts. Name, job title, department, company, office, phone numbers, business address and email address are synced.
- Every target mailbox gets a contact folder (for example "Global Address List"). New colleagues are added, changes are updated and people that left are removed.
- Contacts and the folder are tagged, so GAL-Sync knows which ones it created. The folder belongs to GAL-Sync: contacts added to it by hand are removed on the next run.
- Everything goes through Microsoft Graph v1.0, no other modules are needed.

## How to use

### Azure Automation (recommended)

No secrets to look after: the Automation account signs in with its managed identity.

1. Make sure you have [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) with Bicep (`az bicep install`), Contributor on a resource group, and Privileged Role Administrator in Entra ID to grant the Graph permissions.
2. Copy [deploy/main.bicepparam](deploy/main.bicepparam) and fill in your values.
3. Deploy:

   ```sh
   az group create --name rg-galsync --location westeurope
   az deployment group create --resource-group rg-galsync --template-file deploy/main.bicep --parameters deploy/main.bicepparam
   ```

4. The example parameters start with `reportOnly = true`. Start the `GAL-Sync` runbook and check the output, it shows what would change per mailbox.
5. Set `reportOnly = false` and deploy again.

The deployment creates the Automation account, a PowerShell 7.6 runtime environment with the module, the runbook, a schedule and a `GALSyncConfig` variable with the settings. You can change the settings in that variable in the portal, the names are the same as in the [settings table](#settings) (except the sign-in settings and `LogPath`, which the deployment takes care of). To try a change once, start the runbook by hand with `WhatIfMode` set to true.

Azure Automation stops jobs after 3 hours. If a run gets close to that, raise `throttleLimit`.

### On a server or workstation

1. Please [register an app following Microsoft's guide](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app) and grant it the [permissions below](#azure-application-permissions-needed).
2. Add a certificate (recommended) or a client secret to the app. To create a certificate on Windows:

   ```powershell
   $cert = New-SelfSignedCertificate -Subject "CN=GAL-Sync" -CertStoreLocation Cert:\CurrentUser\My -KeySpec Signature -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(2)
   Export-Certificate -Cert $cert -FilePath .\GAL-Sync.cer   # upload this file to the app
   ```

   For a client secret use `New-StoredCredential.ps1 -ClientId <app id>` as the account that runs the script, the file only works for that account on that machine. Then use `CredentialPath` in the settings instead of `ClientId` and `CertificateThumbprint`.
3. Install [PowerShell 7.6](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) and download this repository (`git clone https://github.com/JeshuaEdgar/gal-sync-graph` or the green "Code" button > "Download ZIP").
4. Copy [Sync-Contacts.settings.example.json](Sync-Contacts.settings.example.json), fill in your values and do a dry run:

   ```powershell
   ./Sync-Contacts.ps1 -ConfigFile .\Sync-Contacts.settings.json -WhatIf
   ```

5. Schedule it, for example with [example.bat](example.bat) in Task Scheduler. The script exits with 1 when a mailbox failed.

Every setting can also be passed on the command line, which overrides the settings file.

### From PowerShell

```powershell
Import-Module ./Module/GAL-Sync.psd1
Connect-GALSync -TenantId contoso.onmicrosoft.com -ClientId <app id> -CertificateThumbprint <thumbprint>

Get-GALDirectoryUser | Select-Object displayName, mail, mobilePhone
Invoke-GALSync -ContactFolderName "Global Address List" -TargetMailbox adele@contoso.com -WhatIf
Get-GALContactFolder -Mailbox adele@contoso.com -Name "Global Address List" | Get-GALFolderContact
Remove-GALContactFolder -Mailbox adele@contoso.com -Name "Global Address List"
```

## Settings

| Setting | Description |
| --- | --- |
| `TenantId` | Tenant ID or `contoso.onmicrosoft.com` (not needed with a managed identity). |
| `ClientId` + `CertificateThumbprint` | Sign in with a certificate from the CurrentUser or LocalMachine store. |
| `CredentialPath` | Sign in with a client secret stored by `New-StoredCredential.ps1`. |
| `ContactFolderName` | Name of the contact folder in every mailbox. |
| `TargetGroup` | Sync to the members of this group, nested groups included (name or object ID). |
| `TargetMailbox` | Sync to these mailboxes, for example `"adele@contoso.com,alex@contoso.com"`. |
| `AllUsers` | Sync to every enabled member with a mailbox address. |
| `SourceGroup` | Only members of this group become contacts. |
| `ExcludeUser` | Users (UPN, email address or object ID) to leave out, as contact and as target. |
| `UserFilter` | Graph filter for the users that become contacts, for example `"companyName eq 'Contoso'"`. |
| `ExcludeHiddenFromAddressList` | Leave out users hidden from the address list. Graph does not always know about this setting, use `ExcludeUser` or `SourceGroup` when it has to be exact. |
| `IncludeOrgContacts` | Also sync mail contacts. Needs `OrgContact.Read.All`. |
| `BusinessPhoneAsMobile` | Show the business number as the mobile number when a user has none. |
| `IncludeUsersWithoutPhone`, `IncludeUsersWithoutEmail`, `IncludeDisabledUsers`, `IncludeGuests` | Also sync these users. |
| `ThrottleLimit` | Mailboxes synced at the same time (default 4). |
| `LogPath` | Folder for a transcript of every run (`Sync-Contacts.ps1` only). |

## Azure Application Permissions needed

All are application permissions in Microsoft Graph.

- User.Read.All
  - [List users](https://learn.microsoft.com/graph/api/user-list)
- GroupMember.Read.All
  - [List groups](https://learn.microsoft.com/graph/api/group-list)
  - [List group members](https://learn.microsoft.com/graph/api/group-list-transitivemembers)
- Contacts.ReadWrite
  - [Create contact folder](https://learn.microsoft.com/graph/api/user-post-contactfolders)
  - [Create](https://learn.microsoft.com/graph/api/user-post-contacts), [update](https://learn.microsoft.com/graph/api/contact-update) and [delete](https://learn.microsoft.com/graph/api/contact-delete) contacts
- OrgContact.Read.All (only with `IncludeOrgContacts`)
  - [List mail contacts](https://learn.microsoft.com/graph/api/orgcontact-list)

## Moving from 0.x

Version 1 is a rewrite and does not reuse anything from 0.x. A mailbox that still has a 0.x folder with the same name fails with a message about it. Remove those folders first (with 0.x's `Delete-ContactFolder` or in Outlook), or use a new `ContactFolderName`.

The parameters of `Sync-Contacts.ps1` changed as well:

| 0.x | 1.0 |
| --- | --- |
| `-Tenant` | `-TenantId` |
| `-CredentialPath` | `-CredentialPath`, or `-ClientId` with `-CertificateThumbprint` |
| `-Directory` | `-AllUsers` |
| `-AzureADGroup` | `-TargetGroup` |
| `-MailboxList` | `-TargetMailbox` |
| `-ContactsWithoutPhoneNumber` | `-IncludeUsersWithoutPhone` |
| `-ContactsWithoutEmail` | `-IncludeUsersWithoutEmail` |
| `-UseGraphSDK` | removed |

## Development

With [just](https://github.com/casey/just), run `just setup` once and then `just` to see the recipes (`just build`, `just fmt`, `just lint`, `just test`, `just bicep`). Without it:

```powershell
Install-PSResource Pester -Version 6.2.0
Install-PSResource PSScriptAnalyzer -Version 1.25.0
./build.ps1
```

`./build.ps1` fails when a script is not formatted, `./build.ps1 -Task Format` (or `just fmt`) formats them. The rules are in [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1): the Stroustrup preset of the VS Code PowerShell extension, with 4 spaces.

The tests run against a fake Microsoft Graph. To also run them against a test tenant, set `GALSYNC_TENANT_ID`, `GALSYNC_CLIENT_ID`, `GALSYNC_CLIENT_SECRET` and `GALSYNC_TEST_MAILBOX` and run `./build.ps1 -Task Test -Integration`.

## Credits

- [@jussihi](https://github.com/jussihi)
  - Creating some of the modules present for the sync
