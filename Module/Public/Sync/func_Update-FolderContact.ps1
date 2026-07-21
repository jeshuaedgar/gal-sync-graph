function Update-FolderContact {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)][object]$ContactFolder,
        [parameter(Mandatory)][object]$Contact
    )
    try {
        $updateContactBody = @{
            givenName      = $Contact.givenName
            surname        = $Contact.surname
            mobilePhone    = $Contact.mobilePhone
            jobTitle       = $Contact.jobTitle
            department     = $Contact.department
            emailAddresses = $Contact.emailAddresses
        }
        # add these based on pressence
        # if ($Contact.homePhones) { $updateContactBody.homePhones = $NewContact.homePhones }
        if ($Contact.businessPhones) { $updateContactBody.businessPhones = $Contact.businessPhones }
        if ($UseGraphSDK) {
            Update-MgUserContactFolderContact -UserId $ContactFolder.mailBox -ContactFolderId $ContactFolder.id -ContactId $Contact.id -BodyParameter $updateContactBody
        } else {
            New-GraphRequest -Method Patch -Endpoint "/users/$($ContactFolder.mailBox)/contactFolders/$($ContactFolder.id)/contacts/$($Contact.id)" -Body $updateContactBody | Out-Null
        }
        Write-VerboseEvent "Updated contact $($Contact.displayName)"
        return $true
    }
    catch {
        throw (Format-ErrorCode $_).ErrorMessage
    }
}