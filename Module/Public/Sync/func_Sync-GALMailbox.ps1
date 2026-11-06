function Sync-GALMailbox {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory)][string]$Mailbox,
        [parameter(Mandatory)][string]$ContactFolderName,
        [parameter(Mandatory)][AllowEmptyCollection()][object[]]$DirectoryUser
    )
    # mailboxes without Exchange Online (no licence, deleted, not a user mailbox) can not be synced
    $skipCodes = "MailboxNotEnabledForRESTAPI", "MailboxNotSupportedForRESTAPI", "ErrorNonExistentMailbox", "ErrorInvalidUser", "ResourceNotFound"
    $result = [ordered]@{
        Mailbox    = $Mailbox
        Status     = "Succeeded"
        Created    = 0
        Updated    = 0
        Removed    = 0
        Unchanged  = 0
        Failed     = 0
        Message    = $null
    }

    try {
        $folders = @(Get-GALContactFolder -Mailbox $Mailbox -Name $ContactFolderName)
        $managed = @($folders | Where-Object { $_.isManaged })
        if ($folders -and -not $managed) {
            throw "$Mailbox already has a contact folder named $ContactFolderName that was not created by GAL-Sync"
        }
        $folder = $managed | Select-Object -First 1
        $contacts = @(if ($folder) { Get-GALFolderContact -Mailbox $Mailbox -FolderId $folder.id })
        $plan = Get-SyncPlan -DirectoryUser $DirectoryUser -FolderContact $contacts
        $result.Unchanged = $plan.Unchanged
        $action = "Create $($plan.Create.Count), update $($plan.Update.Count) and remove $($plan.Remove.Count) contact(s) in $ContactFolderName"

        if (-not ($plan.Create -or $plan.Update -or $plan.Remove -or -not $folder -or $managed.Count -gt 1)) {
            Write-VerboseEvent "$Mailbox is up to date"
        }
        elseif (-not $PSCmdlet.ShouldProcess($Mailbox, $action)) {
            $result.Status = "WhatIf"
            $result.Created = $plan.Create.Count
            $result.Updated = $plan.Update.Count
            $result.Removed = $plan.Remove.Count
        }
        else {
            if (-not $folder) {
                Write-VerboseEvent "Creating contact folder $ContactFolderName for $Mailbox"
                $folder = New-GraphRequest -Method Post -Endpoint (Get-FolderEndpoint -Mailbox $Mailbox) -Body @{
                    displayName                   = $ContactFolderName
                    singleValueExtendedProperties = @($script:folderMarker)
                }
            }
            # two runs at the same time can both create the folder
            foreach ($duplicate in $managed | Select-Object -Skip 1) {
                Write-Warning "Removing duplicate contact folder $ContactFolderName from $Mailbox"
                New-GraphRequest -Method Delete -Endpoint (Get-FolderEndpoint -Mailbox $Mailbox -FolderId $duplicate.id) | Out-Null
            }

            $contactsEndpoint = "$(Get-FolderEndpoint -Mailbox $Mailbox -FolderId $folder.id)/contacts"
            $phases = [ordered]@{
                Removed = foreach ($contact in $plan.Remove) {
                    @{
                        action = "remove"
                        name   = $contact.displayName
                        method = "DELETE"
                        url    = "$contactsEndpoint/$([System.Uri]::EscapeDataString($contact.id))"
                    }
                }
                Updated = foreach ($change in $plan.Update) {
                    Write-VerboseEvent "Updating $($change.Body.displayName) in $($Mailbox): $($change.Changes -join ", ")"
                    @{
                        action = "update"
                        name   = $change.Body.displayName
                        method = "PATCH"
                        url    = "$contactsEndpoint/$([System.Uri]::EscapeDataString($change.Contact.id))"
                        body   = $change.Body
                    }
                }
                Created = foreach ($body in $plan.Create) {
                    @{
                        action = "create"
                        name   = $body.displayName
                        method = "POST"
                        url    = $contactsEndpoint
                        body   = $body
                    }
                }
            }
            foreach ($counter in $phases.Keys) {
                $requests = @($phases[$counter])
                $responses = @(New-GraphBatchRequest -Requests $requests)
                for ($index = 0; $index -lt $requests.Count; $index++) {
                    $status = $responses[$index].status
                    if ($status -ge 200 -and $status -lt 300) {
                        $result[$counter]++
                        continue
                    }
                    $result.Failed++
                    Write-Warning "Failed to $($requests[$index].action) contact $($requests[$index].name) in $($Mailbox): $(Format-ErrorCode -StatusCode $status -ErrorBody $responses[$index].body)"
                }
            }
            if ($result.Failed) {
                $result.Status = "CompletedWithErrors"
                $result.Message = "$($result.Failed) contact change(s) failed"
            }
        }
    }
    catch {
        $result.Message = $_.Exception.Message
        if ($_.Exception.Data["GraphErrorCode"] -in $skipCodes) {
            $result.Status = "Skipped"
            Write-VerboseEvent "Skipped $($Mailbox): $($result.Message)"
        }
        else {
            $result.Status = "Failed"
            Write-Warning "Failed to sync mailbox $($Mailbox): $($result.Message)"
        }
    }
    return [pscustomobject]$result
}
