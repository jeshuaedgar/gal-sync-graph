BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph
}

AfterAll {
    Remove-FakeGraph
}

Describe "ConvertTo-RedactedText" {
    It "Should redact <Name>" -ForEach @(
        @{ Name = "email addresses"; Text = "failed for ann@contoso.com today"; Gone = "ann@contoso.com"; Kept = "<email>" }
        @{ Name = "URL-encoded email addresses"; Text = "GET /v1.0/users/ann%40contoso.com/contactFolders"; Gone = "ann%40"; Kept = "<email>" }
        @{ Name = "guest UPNs"; Text = "user ann_fabrikam.com#EXT#@contoso.onmicrosoft.com"; Gone = "fabrikam"; Kept = "<email>" }
        @{ Name = "GUIDs"; Text = "app 3f2504e0-4f89-11d3-9a0c-0305e82c3301 not found"; Gone = "3f2504e0"; Kept = "<guid>" }
        @{ Name = "JWTs"; Text = "token eyJhbGciOi.eyJ0aWQiOiJ4In0.c2ln rejected"; Gone = "eyJ"; Kept = "<token>" }
        @{ Name = "bearer tokens"; Text = "Authorization: Bearer abc.def-123"; Gone = "abc.def"; Kept = "Bearer <token>" }
        @{ Name = "secrets"; Text = "client_secret=s3cr3t-value&grant_type=x"; Gone = "s3cr3t-value"; Kept = "client_secret=<redacted>" }
        @{ Name = "mailbox item IDs"; Text = "folder AAMkAGI2TG93AAA0ZWQtMjMzYy00ZDM4LWI3ZGUtYTk2 missing"; Gone = "AAMkAGI2"; Kept = "<id>" }
    ) {
        $result = InModuleScope GAL-Sync -Parameters @{ Text = $Text } { ConvertTo-RedactedText -Text $Text }
        $result | Should -Not -BeLike "*$Gone*"
        $result | Should -BeLike "*$Kept*"
    }

    It "Should leave ordinary text alone" {
        InModuleScope GAL-Sync { ConvertTo-RedactedText -Text "Graph request GET /v1.0/users failed: 403 ErrorAccessDenied" } |
        Should -Be "Graph request GET /v1.0/users failed: 403 ErrorAccessDenied"
    }

    It "Should pass empty text through" {
        InModuleScope GAL-Sync { ConvertTo-RedactedText -Text "" } | Should -Be ""
    }
}

Describe "Get-GALDiagnostic" {
    BeforeEach {
        Reset-FakeGraph
        Mock Start-Sleep -ModuleName GAL-Sync
    }

    It "Should say that it is not connected" {
        Get-GALDiagnostic | Should -BeLike "*Connected: no*"
    }

    It "Should report versions and the connection without identifiers" {
        Connect-FakeGraph
        $text = Get-GALDiagnostic
        $body = ($text -split "\r?\n" | Where-Object { -not $_.StartsWith("_") }) -join "`n"
        $text | Should -BeLike "*GAL-Sync: *1.0.0*"
        $text | Should -BeLike "*PowerShell: $($PSVersionTable.PSVersion)*"
        $text | Should -BeLike "*Connected: yes*"
        $text | Should -BeLike "*Sign-in method:*"
        $text | Should -BeLike "*Contacts.ReadWrite: present*"
        $body | Should -Not -Match "\bsecret\b"
        foreach ($leak in "contoso.onmicrosoft.com", "app-id", "tenant-id", "eyJ") {
            $body | Should -Not -BeLike "*$leak*"
        }
    }

    It "Should report roles that are not in the token" {
        $Graph.TokenClaims.roles = @("User.Read.All")
        Connect-FakeGraph
        $text = Get-GALDiagnostic
        $text | Should -BeLike "*User.Read.All: present*"
        $text | Should -BeLike "*Contacts.ReadWrite: not in the token*"
        $text | Should -BeLike "*GroupMember.Read.All: not in the token*"
    }

    It "Should check a mailbox without printing the address" {
        Connect-FakeGraph
        Add-FakeUser -Id "ann" -Name "Ann Lee" | Out-Null
        Add-FakeFolder -Mailbox "ann@contoso.com" -Name "GAL" -Managed | Out-Null
        $text = Get-GALDiagnostic -Mailbox "ann@contoso.com"
        $text | Should -BeLike "*Read access: OK, 1 contact folder(s), 1 created by GAL-Sync*"
        $text | Should -Not -BeLike "*ann@contoso.com*"
        $text | Should -Not -BeLike "*ann%40*"
    }

    It "Should report a failed mailbox check without printing the address" {
        Connect-FakeGraph
        Add-FakeUser -Id "ann" -Name "Ann Lee" | Out-Null
        $Graph.AccessDenied = $true
        $text = Get-GALDiagnostic -Mailbox "ann@contoso.com"
        $text | Should -BeLike "*Read access: failed (ErrorAccessDenied)*"
        $text | Should -Not -BeLike "*ann@contoso.com*"
        $text | Should -Not -BeLike "*ann%40*"
    }

    It "Should summarize and redact sync results" {
        $results = @(
            [pscustomobject]@{ Status = "Failed"; Created = 0; Updated = 0; Removed = 0; Unchanged = 0; Failed = 1; Message = "GET /v1.0/users/ann%40contoso.com/x failed for 3f2504e0-4f89-11d3-9a0c-0305e82c3301 with eyJhbGciOi.eyJ0aWQiOiJ4In0.c2ln" }
            [pscustomobject]@{ Status = "Failed"; Created = 0; Updated = 0; Removed = 0; Unchanged = 0; Failed = 1; Message = "GET /v1.0/users/bob%40contoso.com/x failed for 3f2504e0-4f89-11d3-9a0c-0305e82c3301 with eyJhbGciOi.eyJ0aWQiOiJ4In0.c2ln" }
            [pscustomobject]@{ Status = "Synced"; Created = 5; Updated = 2; Removed = 0; Unchanged = 3; Failed = 0; Message = $null }
        )
        $text = Get-GALDiagnostic -Result $results
        $text | Should -BeLike "*Mailboxes: 3 (Failed 2, Synced 1)*"
        $text | Should -BeLike "*created 5, updated 2, removed 0, unchanged 3, failed 2*"
        $text | Should -BeLike "*2x GET*"
        foreach ($leak in "ann%40", "bob%40", "contoso.com", "3f2504e0", "eyJ") {
            $text | Should -Not -BeLike "*$leak*"
        }
    }

    It "Should accept results from the pipeline" {
        $results = @(
            [pscustomobject]@{ Status = "Synced"; Created = 1; Updated = 0; Removed = 0; Unchanged = 0; Failed = 0; Message = $null }
            [pscustomobject]@{ Status = "Skipped"; Created = 0; Updated = 0; Removed = 0; Unchanged = 0; Failed = 0; Message = "no mailbox" }
        )
        $results | Get-GALDiagnostic | Should -BeLike "*Mailboxes: 2 (Skipped 1, Synced 1)*"
    }
}
