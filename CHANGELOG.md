# [v1.0.0]

A complete rewrite. It is not compatible with 0.x: folders created by 0.x are not reused, so remove them first or pick a new contact folder name (see [Moving from 0.x](README.md#moving-from-0x)).

## Added

- Azure Automation deployment in `deploy/main.bicep`: Automation account with a managed identity, PowerShell 7.6 runtime environment, runbook, settings and schedule. It can grant the Microsoft Graph permissions too.
- Sign in with a managed identity, a certificate or a client secret. Tokens are renewed automatically, so long runs keep working (#17)
- `Invoke-GALSync` syncs all mailboxes in parallel, `Sync-GALMailbox` syncs one
- Contacts are matched on the user's object ID, so renames and people with the same name are handled
- `-WhatIf` for a dry run, `Remove-GALContactFolder` to remove the folder again
- `-SourceGroup`, `-ExcludeUser` and `-UserFilter` to choose who shows up as a contact (#9)
- `-ExcludeHiddenFromAddressList` to leave out users hidden from the address list (#12). Microsoft Graph does not always know about this setting, so `-ExcludeUser` or `-SourceGroup` are the reliable options.
- `-IncludeOrgContacts` to also sync mail contacts (#11)
- `-BusinessPhoneAsMobile` to show the business number as the mobile number when a user has none (#13)
- Company, office and business address are synced (#9)
- `-ConfigFile` for `Sync-Contacts.ps1`, so settings with accented characters do not have to go through a .bat file (#9)
- Tests that run against a fake Microsoft Graph, so no tenant is needed

## Fixed

- Mobile numbers were not synced (#14)
- Syncing failed with "op_Addition" when one contact had to be removed (#10)
- `-AzureADGroup` found no users, and nested groups were not followed (#15)
- Changed or removed phone numbers, job titles and email addresses were not updated on existing contacts
- Contacts whose name did not match "first last" were recreated on every run
- The access token was written to the verbose output
- Scheduled runs failed when started from another folder, and could hang waiting for input

## Removed

- The Graph SDK option, all requests go to Microsoft Graph v1.0 directly
- Support for Windows PowerShell 5.1, PowerShell 7.6 or later is needed
- `OrgContact.Read.All` and `Group.Read.All` are no longer needed, use `GroupMember.Read.All` (and `OrgContact.Read.All` only with `-IncludeOrgContacts`)

Thanks to [@jussihi](https://github.com/jussihi), [@tknaller](https://github.com/tknaller), [@DJMEGA153](https://github.com/DJMEGA153), [@NGBIT-de](https://github.com/NGBIT-de) and everyone who reported issues.

# [v0.1.1-beta]

## Added

- `Delete-ContactFolder`
  - Courtesy of [@jussihi](https://github.com/jussihi) mentioned in #3 and #5, thanks!

# [v0.1.0-beta]

## Known Issues

- Accented characters are for some weird reason not returned in the API when querying them when inside of a contactFolder, please keep this in mind as this can create errors when doing a sync.

## Removed

- `homePhones` property is removed. This might be re-added in the future, for now only `mobilePhone`/`businessPhones` properties are syncable

## Fixed

- `New-GraphRequest`
  - Fixed a bug when there was `odata.nextLink` present it would not add to the output array
- `Get-ContactFolder` is now language independant
  - `wellKnownName` property seems to be filled with the default contacts folder
- `Update-FolderContact` now works properly
- `Department` property was missing from the new contacts
- `Sync-GALContacts`'s delta sync now works properly

# [v0.0.3-beta]

## Added

- Pagination and more verbose details for `New-GraphRequest`

## Fixed

- Azure AD Group name in sync script
- Sync script log path stop transcript

# [v0.0.2-beta]

## Fixed

- Connect-GALSync was still requiring `Applications.Read.All`

# [v0.0.1-beta]

## Added

- Sync GAL Contacts with either directory (all users), Azure AD group or a mailbox list
- Store credentials for unattended scheduled use
- Docs in [README](README.md)
- Create and get contact folders
- Get, create, update and remove contacts inside of folders
- Logging for debugging
- Unit tests (ran on Microsoft 365 Dev Environment)
