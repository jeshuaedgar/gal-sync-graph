# GAL (Global Address List) Sync using Graph | [![CI](https://github.com/JeshuaEdgar/gal-sync-graph/actions/workflows/ci.yml/badge.svg)](https://github.com/JeshuaEdgar/gal-sync-graph/actions/workflows/ci.yml) [![PowerShell Gallery](https://img.shields.io/powershellgallery/v/GAL-Sync?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/GAL-Sync)

Outlook knows your colleagues, your phone's contacts app doesn't, so you can't see who's calling. GAL-Sync puts your colleagues in a contact folder in every mailbox and keeps it up to date. The folder syncs to phones like any other contacts.

## [Changelog](CHANGELOG.md)

## Install

```powershell
Install-PSResource GAL-Sync -Prerelease   # 1.0 is in beta
```

## How it works

- Enabled members with an email address and a phone number become contacts: name, job title, department, company, office, phones, business address and email.
- Every target mailbox gets a contact folder. New colleagues are added, changes updated, leavers removed.
- GAL-Sync tags its folder and contacts. The folder is GAL-Sync's: contacts added by hand are removed on the next run.
- Microsoft Graph v1.0 only, no other modules.

## How to use

### Azure Automation (recommended)

Signs in with the Automation account's managed identity, so there are no secrets to manage.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FJeshuaEdgar%2Fgal-sync-graph%2Fmaster%2Fdeploy%2Fazuredeploy.json)

You need Contributor on the resource group and Privileged Role Administrator to grant the Graph permissions (or set **Grant Graph Permissions** to false and grant them yourself). Deploy with **Report Only** on, check the `GAL-Sync` runbook output, then redeploy with it off.

From the command line, fill in a copy of [deploy/main.bicepparam](deploy/main.bicepparam) (it starts with `reportOnly = true`) and run:

```sh
az group create --name rg-galsync --location westeurope
az deployment group create --resource-group rg-galsync --template-file deploy/main.bicep --parameters deploy/main.bicepparam
```

- Settings live in the `GALSyncConfig` variable, using the names from the [settings table](#settings). To test a change once, start the runbook with `WhatIfMode` set to true.
- Job output is one JSON line with a result per mailbox. With **Log verbose records** on (`verboseLogging = true`, or the runbook's Logging and tracing setting), the verbose stream has the same as a table.
- The module comes from the GitHub release. Use `moduleSource = 'PSGallery'` for the PowerShell Gallery, or `modulePackageUri` for your own copy.
- Jobs stop after 3 hours. Raise `throttleLimit` if a run gets close.

#### Another tenant

A managed identity only works in its own tenant. For another tenant, [register an app](#on-a-server-or-workstation) there with the [permissions](#azure-application-permissions-needed), then deploy with `signInMethod = 'Connection'`, `tenantId`, `clientId` and either `clientSecret` or `certificateName` (a .pfx you uploaded under **Certificates**). These are kept in the `GAL-Sync` connection, where you can renew them without redeploying.

### On a server or workstation

1. [Register an app](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app) with the [permissions below](#azure-application-permissions-needed).
2. Add a certificate (recommended) to the app. On Windows:

    ```powershell
    $cert = New-SelfSignedCertificate -Subject "CN=GAL-Sync" -CertStoreLocation Cert:\CurrentUser\My -KeySpec Signature -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(2)
    Export-Certificate -Cert $cert -FilePath .\GAL-Sync.cer   # upload this file to the app
    ```

    For a client secret, store it as the account that runs the sync, and set `CredentialPath` instead of `ClientId` and `CertificateThumbprint`:

    ```powershell
    Get-Credential -UserName <app id> -Message "Client secret" | Export-Clixml C:\GAL-Sync\credential.cred
    ```

    The file is only encrypted on Windows (for that user on that computer).

3. Install [PowerShell 7.6](https://learn.microsoft.com/powershell/scripting/install/installing-powershell), then clone this repository, or [install the module](#install) and download only [Sync-Contacts.ps1](Sync-Contacts.ps1).
4. Fill in a copy of [Sync-Contacts.settings.example.json](Sync-Contacts.settings.example.json) and do a dry run:

    ```powershell
    ./Sync-Contacts.ps1 -ConfigFile .\Sync-Contacts.settings.json -WhatIf
    ```

5. Schedule it in Task Scheduler. Run the task as the account that holds the certificate or credential file:

    ```powershell
    $action = New-ScheduledTaskAction -Execute pwsh.exe -Argument '-NoProfile -NonInteractive -File C:\GAL-Sync\Sync-Contacts.ps1 -ConfigFile C:\GAL-Sync\Sync-Contacts.settings.json'
    $user = Get-Credential
    Register-ScheduledTask -TaskName GAL-Sync -Action $action -Trigger (New-ScheduledTaskTrigger -Daily -At 3am) -User $user.UserName -Password $user.GetNetworkCredential().Password
    ```

    The script exits with 1 when a mailbox fails.

Command-line parameters override the settings file.

### From PowerShell

```powershell
Start-GALSync -ConfigFile .\Sync-Contacts.settings.json -WhatIf   # connect and sync in one go

Connect-GALSync -TenantId contoso.onmicrosoft.com -ClientId <app id> -CertificateThumbprint <thumbprint>
Get-GALDirectoryUser | Select-Object displayName, mail, mobilePhone
Invoke-GALSync -ContactFolderName "Global Address List" -TargetMailbox adele@contoso.com -WhatIf
Get-GALContactFolder -Mailbox adele@contoso.com -Name "Global Address List" | Get-GALFolderContact
Remove-GALContactFolder -Mailbox adele@contoso.com -Name "Global Address List"
```

## Settings

The same names work in the settings file, the `GALSyncConfig` variable and `Start-GALSync -Settings`. An unknown setting stops the run.

| Setting                                                                                         | Description                                                                                                                                  |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `TenantId`                                                                                      | Tenant ID or `contoso.onmicrosoft.com`. Not needed with a managed identity.                                                                  |
| `ClientId` + `CertificateThumbprint`                                                            | Sign in with a certificate from the CurrentUser or LocalMachine store.                                                                       |
| `CredentialPath`                                                                                | Sign in with a client secret stored with `Export-Clixml`.                                                                                    |
| `ContactFolderName`                                                                             | Contact folder name in every mailbox.                                                                                                        |
| `TargetGroup`                                                                                   | Sync to this group's members, nested groups included (name or object ID).                                                                    |
| `TargetMailbox`                                                                                 | Sync to these mailboxes, for example `"adele@contoso.com,alex@contoso.com"`.                                                                 |
| `AllUsers`                                                                                      | Sync to every enabled member with a mailbox address.                                                                                         |
| `SourceGroup`                                                                                   | Only members of this group become contacts.                                                                                                  |
| `ExcludeUser`                                                                                   | Users (UPN, email or object ID) to leave out as contact and as target.                                                                       |
| `UserFilter`                                                                                    | Graph filter for who becomes a contact, for example `"companyName eq 'Contoso'"`.                                                            |
| `ExcludeHiddenFromAddressList`                                                                  | Leave out users hidden from the address list. Graph isn't always accurate here, so use `ExcludeUser` or `SourceGroup` when it must be exact. |
| `IncludeOrgContacts`                                                                            | Also sync mail contacts. Needs `OrgContact.Read.All`.                                                                                        |
| `BusinessPhoneAsMobile`                                                                         | Use the business number as mobile when a user has none.                                                                                      |
| `IncludeUsersWithoutPhone`, `IncludeUsersWithoutEmail`, `IncludeDisabledUsers`, `IncludeGuests` | Also sync these users.                                                                                                                       |
| `ThrottleLimit`                                                                                 | Mailboxes synced at the same time (default 4).                                                                                               |
| `LogPath`                                                                                       | Transcript folder (`Sync-Contacts.ps1` only).                                                                                                |

## Azure Application Permissions needed

Microsoft Graph application permissions:

- `User.Read.All`: list users
- `GroupMember.Read.All`: list groups and their members (only with `TargetGroup` or `SourceGroup`)
- `Contacts.ReadWrite`: manage the contact folder and contacts
- `OrgContact.Read.All`: list mail contacts (only with `IncludeOrgContacts`)

The Bicep deployment only grants the roles the settings need. `TargetGroup` reads its members through an index that can lag a few minutes behind recent group changes. `SourceGroup` reads them directly.

A mailbox in `TargetMailbox` that does not exist or has no Exchange Online mailbox is reported as `Failed`, so typos are noticed. With `AllUsers` or `TargetGroup` those mailboxes are `Skipped`, because directory users without a mailbox are expected.

### Limit access to some mailboxes

`Contacts.ReadWrite` granted in Entra covers every mailbox in the tenant. To limit the app to a set of mailboxes, use [Role Based Access Control for Applications](https://learn.microsoft.com/exchange/permissions-exo/application-rbac) in Exchange Online instead:

1. Deploy with `grantContactsAccess = false` (or do not consent to `Contacts.ReadWrite`). Remove the Entra grant if it exists, because Entra and Exchange grants add up.
2. Connect to Exchange Online PowerShell and register the app, tag the mailboxes and assign the role to a scope:

```powershell
New-ServicePrincipal -AppId <app id> -ObjectId <service principal object id> -DisplayName "GAL-Sync"
New-ManagementScope -Name "GAL-Sync mailboxes" -RecipientRestrictionFilter "CustomAttribute1 -eq 'GALSync'"
New-ManagementRoleAssignment -App <service principal object id> -Role "Application Contacts.ReadWrite" -CustomResourceScope "GAL-Sync mailboxes"
Test-ServicePrincipalAuthorization -Identity <service principal object id> -Resource <mailbox>
```

Changes can take 30 minutes to 2 hours to apply. A mailbox outside the scope answers 403 and is reported as `Failed` with a hint about the permission, so keep the targets inside the scope.

## Trying the beta

Start small, and check what would change before anything is written:

1. Run with `-TargetMailbox` for your own mailbox, or a small test group. Do not start with the whole tenant.
2. Add `-WhatIf` first. It reports the planned changes and writes nothing.
3. To undo, run `Remove-GALContactFolder -Mailbox <address> -Name <folder>`. It only removes folders that GAL-Sync created.

To report a problem or share how it went, open an [issue](https://github.com/JeshuaEdgar/gal-sync-graph/issues/new/choose) and paste the output of `Get-GALDiagnostic`.

**In Azure Automation**, start the `GAL-Sync` runbook with `Diagnostic` set to true, and optionally `DiagnosticMailbox` set to a mailbox that fails. It signs in the same way as the sync, writes nothing, and puts the diagnostics in the job **Output**. If reading the settings or signing in fails, the reason is part of the output instead of a failed job. Copy the output into the issue.

**From PowerShell**:

```powershell
Get-GALDiagnostic -Mailbox adele@contoso.com -Result $results | Set-Clipboard
```

It shows the versions, how you are signed in, the roles in the token, whether the mailbox can be read, and a summary of the results. It leaves out secrets, tokens, tenant and application IDs, names and email addresses, and filters text from Graph for them. It is best effort, so read it before you post. On Linux, `Set-Clipboard` needs `xclip` or `wl-clipboard`; otherwise drop it and copy the output.

## Moving from 0.x

Version 1 is a rewrite and reuses nothing from 0.x. A mailbox that still has a 0.x folder with the same name fails with a message. Remove those folders first (0.x's `Delete-ContactFolder` or Outlook), or use a new `ContactFolderName`.

| 0.x                           | 1.0                                                             |
| ----------------------------- | --------------------------------------------------------------- |
| `-Tenant`                     | `-TenantId`                                                     |
| `-CredentialPath`             | `-CredentialPath`, or `-ClientId` with `-CertificateThumbprint` |
| `-Directory`                  | `-AllUsers`                                                     |
| `-AzureADGroup`               | `-TargetGroup`                                                  |
| `-MailboxList`                | `-TargetMailbox`                                                |
| `-ContactsWithoutPhoneNumber` | `-IncludeUsersWithoutPhone`                                     |
| `-ContactsWithoutEmail`       | `-IncludeUsersWithoutEmail`                                     |
| `-UseGraphSDK`                | removed                                                         |

## Development

Run `just setup` once, then `just` lists the recipes. Without [just](https://github.com/casey/just):

```powershell
Install-PSResource Pester -Version 6.2.0
Install-PSResource PSScriptAnalyzer -Version 1.25.0
./scripts/build.ps1   # -Task Format to fix formatting
```

Tests run against a fake Microsoft Graph. For a real tenant, set `GALSYNC_TENANT_ID`, `GALSYNC_CLIENT_ID`, `GALSYNC_CLIENT_SECRET` and `GALSYNC_TEST_MAILBOX` and run `./scripts/build.ps1 -Task Test -Integration`. See [TESTING.md](TESTING.md) for the unit tests, the integration tests and the manual Dev Proxy check.

## Credits

- [@jussihi](https://github.com/jussihi): some of the original sync modules
