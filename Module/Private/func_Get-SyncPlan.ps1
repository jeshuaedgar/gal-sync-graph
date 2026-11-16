function Get-SyncPlan {
    param (
        [parameter(Mandatory)][AllowEmptyCollection()][object[]]$DirectoryUser,
        [parameter(Mandatory)][AllowEmptyCollection()][object[]]$FolderContact
    )
    $contacts = @{}
    $remove = New-Object System.Collections.Generic.List[object]
    foreach ($contact in $FolderContact) {
        if ($contact.sourceId -and -not $contacts.ContainsKey($contact.sourceId)) {
            $contacts[$contact.sourceId] = $contact
        }
        else {
            $remove.Add($contact)
        }
    }

    $create = New-Object System.Collections.Generic.List[object]
    $update = New-Object System.Collections.Generic.List[object]
    $unchanged = 0
    foreach ($user in $DirectoryUser) {
        $body = [ordered]@{}
        foreach ($field in $script:contactFields.Keys) {
            $body[$field] = $user.$field
        }
        $body.singleValueExtendedProperties = @(@{ id = $script:sourceIdProperty; value = $user.id })

        $contact = $contacts[$user.id]
        $contacts.Remove($user.id)
        if (-not $contact) {
            $create.Add($body)
            continue
        }
        $changes = @(Compare-Contact -Desired $body -Current $contact)
        if ($changes) {
            $update.Add([pscustomobject]@{
                    Contact = $contact
                    Body    = $body
                    Changes = $changes
                })
        }
        else {
            $unchanged++
        }
    }
    $remove.AddRange(@($contacts.Values))

    return [pscustomobject]@{
        Create    = $create.ToArray()
        Update    = $update.ToArray()
        Remove    = $remove.ToArray()
        Unchanged = $unchanged
    }
}
