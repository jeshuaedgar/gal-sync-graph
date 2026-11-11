function Get-GALDiagnostic {
    <#
    .SYNOPSIS
        Collects support information that is safe to paste into a GitHub issue.
    .DESCRIPTION
        Reports the module and PowerShell versions, how you are signed in, which Microsoft Graph roles the
        token has, an optional read-only check of one mailbox, and a summary of earlier sync results.

        It never includes secrets, tokens, tenant or application IDs, email addresses or names. Text that comes
        from Microsoft Graph is filtered for tokens, secrets, email addresses and GUIDs. This is best effort,
        read the output before you post it.
    .PARAMETER Mailbox
        Read the contact folders of this mailbox to check access. Nothing is written, and the address is not
        part of the output.
    .PARAMETER Result
        The output of Invoke-GALSync or Start-GALSync, to summarize.
    .PARAMETER Problem
        An error message to include, for example why signing in failed. It is filtered like other text from Graph.
    .EXAMPLE
        Get-GALDiagnostic -Mailbox adele@contoso.com | Set-Clipboard
    .EXAMPLE
        $results = Start-GALSync -Settings $settings
        Get-GALDiagnostic -Result $results
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$Mailbox,
        [parameter(ValueFromPipeline)][object[]]$Result,
        [string]$Problem
    )
    begin {
        $results = New-Object System.Collections.Generic.List[object]
    }
    process {
        foreach ($item in $Result) {
            if ($null -ne $item) { $results.Add($item) }
        }
    }
    end {
        $manifest = Import-PowerShellDataFile -Path (Join-Path $MyInvocation.MyCommand.Module.ModuleBase "GAL-Sync.psd1")
        $version = $manifest.ModuleVersion
        if ($manifest.PrivateData.PSData.Prerelease) { $version += "-$($manifest.PrivateData.PSData.Prerelease)" }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("### GAL-Sync diagnostics")
        $lines.Add("")
        $lines.Add("- GAL-Sync: $version")
        $lines.Add("- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")
        $lines.Add("- OS: $($PSVersionTable.OS)")
        $lines.Add("- Azure Automation managed identity endpoint: $(if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) { "yes" } else { "no" })")
        $lines.Add("")
        $lines.Add("#### Connection")

        $connection = $script:galSyncData
        if (-not $connection) {
            $lines.Add("- Connected: no (run Connect-GALSync first, or use Start-GALSync)")
        }
        else {
            $token = $connection.Token
            $minutes = [int][System.Math]::Floor(($token.ExpiresOn - [System.DateTimeOffset]::UtcNow).TotalMinutes)
            $lines.Add("- Connected: yes")
            $lines.Add("- Sign-in method: $($connection.SignIn.Method)")
            $lines.Add("- Token valid for another: $(if ($minutes -gt 0) { "$minutes minute(s)" } else { "no time, it is renewed on the next request" })")
            $lines.Add("- Roles in the token: $(if ($token.Roles) { $token.Roles -join ", " } else { "none" })")
            $needed = [ordered]@{
                "User.Read.All"        = "always"
                "Contacts.ReadWrite"   = "always, unless granted with Exchange RBAC for Applications"
                "GroupMember.Read.All" = "only with TargetGroup or SourceGroup"
                "OrgContact.Read.All"  = "only with IncludeOrgContacts"
            }
            foreach ($role in $needed.Keys) {
                $state = if ($role -in $token.Roles) { "present" } else { "not in the token" }
                $lines.Add("  - ${role}: $state (needed $($needed[$role]))")
            }
        }

        if ($Problem) {
            $lines.Add("")
            $lines.Add("#### Problem")
            $lines.Add("- $(ConvertTo-RedactedText $Problem)")
        }

        if ($Mailbox) {
            $lines.Add("")
            $lines.Add("#### Mailbox check")
            if (-not $connection) {
                $lines.Add("- Skipped: not connected")
            }
            else {
                try {
                    $folders = @(Get-GALContactFolder -Mailbox $Mailbox)
                    $lines.Add("- Read access: OK, $($folders.Count) contact folder(s), $(@($folders | Where-Object { $_.isManaged }).Count) created by GAL-Sync")
                }
                catch {
                    $code = $_.Exception.Data["GraphErrorCode"]
                    $lines.Add("- Read access: failed$(if ($code) { " ($code)" })")
                    $lines.Add("- Message: $(ConvertTo-RedactedText $_.Exception.Message)")
                }
            }
        }

        if ($results.Count) {
            $lines.Add("")
            $lines.Add("#### Sync results")
            $statuses = $results | Group-Object -Property Status | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }
            $lines.Add("- Mailboxes: $($results.Count) ($($statuses -join ", "))")
            $totals = foreach ($counter in "Created", "Updated", "Removed", "Unchanged", "Failed") {
                $sum = ($results | ForEach-Object { [int]$_.$counter } | Measure-Object -Sum).Sum
                "$($counter.ToLower()) $([int]$sum)"
            }
            $lines.Add("- Contacts: $($totals -join ", ")")
            $messages = @($results | Where-Object { $_.Message } | Group-Object -Property { ConvertTo-RedactedText $_.Message } | Sort-Object Count -Descending)
            foreach ($group in $messages | Select-Object -First 10) {
                $text = $group.Name
                if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + "..." }
                $lines.Add("  - $($group.Count)x $text")
            }
            if ($messages.Count -gt 10) {
                $lines.Add("  - and $($messages.Count - 10) more message(s)")
            }
        }

        $lines.Add("")
        $lines.Add("_Secrets, tokens, tenant and application IDs, names and email addresses are left out. Check the text before you post it._")
        return ($lines -join [System.Environment]::NewLine)
    }
}
