BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph

    function Sync-Adele {
        param ([object[]]$Users = @(Get-GALDirectoryUser), [hashtable]$Options = @{})
        return Sync-GALMailbox -Mailbox "adele@contoso.com" -ContactFolderName "GAL" -DirectoryUser $Users @Options -WarningAction SilentlyContinue
    }

    function Get-AdeleContact ($SourceId) {
        return Get-FakeContact -Mailbox "adele@contoso.com" -SourceId $SourceId
    }
}

AfterAll {
    Remove-FakeGraph
}

Describe "Sync-GALMailbox" {
    BeforeEach {
        Reset-FakeGraph
        Connect-FakeGraph
        Mock Start-Sleep -ModuleName GAL-Sync
        $script:Ann = Add-FakeUser -Id "ann" -Name "Ann Lee" -Business "+31 20 1" -Properties @{
            jobTitle       = "Engineer"
            department     = "R&D"
            companyName    = "Contoso"
            officeLocation = "Amsterdam"
            streetAddress  = "Main 1"
            city           = "Amsterdam"
            state          = "NH"
            postalCode     = "1000 AA"
            country        = "Netherlands"
        }
        $script:Bob = Add-FakeUser -Id "bob" -Name "Bob Ray"
        Add-FakeUser -Id "adele" -Name "Adele Vance" -Mobile "" | Out-Null
    }

    It "Should create the folder and a tagged contact for every user" {
        $result = Sync-Adele

        $result.Status | Should -Be "Succeeded"
        $result.Created | Should -Be 2
        $folder = Get-FakeFolder -Mailbox "adele@contoso.com"
        $folder.Count | Should -Be 1
        Test-FakeManaged $folder[0] | Should -BeTrue
        $contact = Get-AdeleContact "ann"
        $contact.displayName | Should -Be "Ann Lee"
        $contact.givenName | Should -Be "Ann"
        $contact.surname | Should -Be "Lee"
        $contact.mobilePhone | Should -Be "+31 6 ann"
        $contact.businessPhones | Should -Be @("+31 20 1")
        $contact.jobTitle | Should -Be "Engineer"
        $contact.department | Should -Be "R&D"
        $contact.companyName | Should -Be "Contoso"
        $contact.officeLocation | Should -Be "Amsterdam"
        $contact.businessAddress.street | Should -Be "Main 1"
        $contact.businessAddress.city | Should -Be "Amsterdam"
        $contact.businessAddress.state | Should -Be "NH"
        $contact.businessAddress.postalCode | Should -Be "1000 AA"
        $contact.businessAddress.countryOrRegion | Should -Be "Netherlands"
        $contact.emailAddresses[0].address | Should -Be "ann@contoso.com"
    }

    It "Should make no changes when the folder is up to date" {
        Sync-Adele | Out-Null
        $Graph.Calls.Clear()

        $result = Sync-Adele

        $result.Unchanged | Should -Be 2
        ($result.Created + $result.Updated + $result.Removed) | Should -Be 0
        $Graph.Calls | Where-Object { $_ -notlike "GET *" } | Should -BeNullOrEmpty
    }

    It "Should apply a changed <Property>" -ForEach @(
        @{ Property = "mobilePhone"; Value = "+31 6 99" }
        @{ Property = "jobTitle"; Value = "Architect" }
        @{ Property = "displayName"; Value = "Ann LEE" }
        @{ Property = "businessPhones"; Value = @("+31 20 2") }
        @{ Property = "mail"; Value = "ann.lee@contoso.com" }
        @{ Property = "streetAddress"; Value = "Side 2" }
        @{ Property = "postalCode"; Value = "2000 BB" }
    ) {
        Sync-Adele | Out-Null
        $Ann[$Property] = $Value

        $result = Sync-Adele

        $result.Updated | Should -Be 1
        $contact = Get-AdeleContact "ann"
        switch ($Property) {
            "mail" { $contact.emailAddresses[0].address | Should -Be $Value }
            "streetAddress" { $contact.businessAddress.street | Should -Be $Value }
            "postalCode" { $contact.businessAddress.postalCode | Should -Be $Value }
            default { $contact[$Property] | Should -Be $Value }
        }
    }

    It "Should clear a value that was removed from the directory" {
        Sync-Adele | Out-Null
        $Ann.jobTitle = $null
        $Ann.businessPhones = @()

        Sync-Adele | Out-Null

        (Get-AdeleContact "ann").jobTitle | Should -BeNullOrEmpty
        (Get-AdeleContact "ann").businessPhones | Should -BeNullOrEmpty
    }

    It "Should ignore spaces around values" {
        Sync-Adele | Out-Null
        $Ann.jobTitle = " Engineer "
        (Sync-Adele).Updated | Should -Be 0
    }

    It "Should ignore differences in email address case" {
        Sync-Adele | Out-Null
        (Get-AdeleContact "ann").emailAddresses[0].address = "ANN@CONTOSO.COM"
        (Sync-Adele).Updated | Should -Be 0
    }

    It "Should remove contacts of users that left and duplicate contacts" {
        Sync-Adele | Out-Null
        $folder = (Get-FakeFolder -Mailbox "adele@contoso.com")[0]
        $folder.contacts["copy"] = New-FakeContact -Id "copy" -SourceId "ann" -From $Ann
        $Graph.Users.Remove($Bob) | Out-Null

        $result = Sync-Adele

        $result.Removed | Should -Be 2
        @(Get-FakeContact -Mailbox "adele@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Should -Be @("ann")
    }

    It "Should keep two people with the same name apart" {
        Add-FakeUser -Id "j1" -Name "John Smith" -Mail "john.smith@contoso.com" | Out-Null
        Add-FakeUser -Id "j2" -Name "John Smith" -Mail "john.smith2@contoso.com" | Out-Null
        Sync-Adele | Out-Null
        $result = Sync-Adele
        $result.Unchanged | Should -Be 4
        @(Get-FakeContact -Mailbox "adele@contoso.com" | Where-Object { $_.displayName -eq "John Smith" }).Count | Should -Be 2
    }

    It "Should remove contacts before creating new ones" {
        Sync-Adele | Out-Null
        $Graph.Users.Remove($Bob) | Out-Null
        Add-FakeUser -Id "cat" -Name "Cat Lin" | Out-Null
        $Graph.Calls.Clear()

        Sync-Adele | Out-Null

        $changes = @($Graph.Calls | Where-Object { $_ -like "BATCH *" })
        $changes[0] | Should -BeLike "BATCH DELETE *"
        $changes[-1] | Should -BeLike "BATCH POST *"
    }

    It "Should sync a mailbox whose address needs escaping" {
        Add-FakeUser -Id "hash" -Name "Jo Hash" -Mail "jo#1@contoso.com" | Out-Null
        $result = Sync-GALMailbox -Mailbox "jo#1@contoso.com" -ContactFolderName "GAL" -DirectoryUser @(Get-GALDirectoryUser)
        $result.Status | Should -Be "Succeeded"
        @(Get-FakeContact -Mailbox "jo#1@contoso.com").Count | Should -Be 3
    }

    It "Should sync mail contacts with their address" {
        Add-FakeOrgContact -Id "oc1" -Name "Vera Vendor" -Mail "vera@vendor.com" -Phones @(@{ type = "mobile"; number = "+44 7 1" }) -Addresses @(
            @{ street = "1 Road"; city = "London"; postalCode = "E1"; countryOrRegion = "UK"; officeLocation = "HQ" }
        ) | Out-Null
        Sync-Adele -Users @(Get-GALDirectoryUser -IncludeOrgContacts) | Out-Null
        $contact = Get-AdeleContact "oc1"
        $contact.mobilePhone | Should -Be "+44 7 1"
        $contact.officeLocation | Should -Be "HQ"
        $contact.businessAddress.city | Should -Be "London"
    }

    It "Should remove contacts that were not created by GAL-Sync" {
        Sync-Adele | Out-Null
        $folder = (Get-FakeFolder -Mailbox "adele@contoso.com")[0]
        $folder.contacts["by/hand"] = New-FakeContact -Id "by/hand" -From $Ann

        $result = Sync-Adele

        $result.Removed | Should -Be 1
        $result.Unchanged | Should -Be 2
        $folder.contacts.Contains("by/hand") | Should -BeFalse
    }

    It "Should read every page of a large contact folder" {
        Sync-Adele | Out-Null
        1..5 | ForEach-Object { Add-FakeUser -Id "p$_" -Name "Page User$_" -Mail "page$_@contoso.com" | Out-Null }
        Sync-Adele | Out-Null
        $Graph.PageSize = 2

        $result = Sync-Adele

        $result.Unchanged | Should -Be 7
        @(Get-FakeContact -Mailbox "adele@contoso.com").Count | Should -Be 7
    }

    Context "Folders" {
        It "Should remove duplicate GAL-Sync folders but never the user's own" {
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" -Id "mine/1" -Managed | Out-Null
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" -Id "users+own" | Out-Null
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" -Id "mine=2" -Managed | Out-Null

            Sync-Adele | Out-Null

            (Get-FakeFolder -Mailbox "adele@contoso.com").id | Should -Be @("mine/1", "users+own")
            @((Get-FakeFolder -Mailbox "adele@contoso.com")[0].contacts.Values).Count | Should -Be 2
        }

        It "Should remove a duplicate GAL-Sync folder when nothing else changed" {
            Sync-Adele | Out-Null
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" -Managed | Out-Null
            Sync-Adele | Out-Null
            (Get-FakeFolder -Mailbox "adele@contoso.com").Count | Should -Be 1
        }

        It "Should fail when the mailbox has its own folder with the same name" {
            $own = Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" -Contacts (New-FakeContact -Id "mum" -From @{ displayName = "Mum" })

            $result = Sync-Adele

            $result.Status | Should -Be "Failed"
            $result.Message | Should -BeLike "*not created by GAL-Sync*"
            Test-FakeManaged $own | Should -BeFalse
            @($own.contacts.Values).Count | Should -Be 1
            (Get-FakeFolder -Mailbox "adele@contoso.com").Count | Should -Be 1
        }

        It "Should leave a folder with another name alone" {
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "Family" -Contacts (New-FakeContact -Id "mum" -From @{ displayName = "Mum" }) | Out-Null
            Sync-Adele | Out-Null
            @((Get-FakeFolder -Mailbox "adele@contoso.com" -Name "Family")[0].contacts.Values).Count | Should -Be 1
        }

        It "Should remove the folder with Remove-GALContactFolder" {
            Sync-Adele | Out-Null
            Remove-GALContactFolder -Mailbox "adele@contoso.com" -Name "GAL" -WhatIf
            (Get-FakeFolder -Mailbox "adele@contoso.com").Count | Should -Be 1
            Remove-GALContactFolder -Mailbox "adele@contoso.com" -Name "GAL" -Confirm:$false
            (Get-FakeFolder -Mailbox "adele@contoso.com").Count | Should -Be 0
        }

        It "Should not remove a folder it did not create" {
            Add-FakeFolder -Mailbox "adele@contoso.com" -Name "GAL" | Out-Null
            Remove-GALContactFolder -Mailbox "adele@contoso.com" -Name "GAL" -Confirm:$false
            (Get-FakeFolder -Mailbox "adele@contoso.com").Count | Should -Be 1
        }

        It "Should list the folder and its contacts" {
            Sync-Adele | Out-Null
            $folder = Get-GALContactFolder -Mailbox "adele@contoso.com" -Name "GAL"
            $folder.isManaged | Should -BeTrue
            ($folder | Get-GALFolderContact).sourceId | Sort-Object | Should -Be @("ann", "bob")
        }
    }

    Context "Results" {
        It "Should plan without writing with -WhatIf" {
            $result = Sync-Adele -Options @{ WhatIf = $true }
            $result.Status | Should -Be "WhatIf"
            $result.Created | Should -Be 2
            $Graph.Calls | Where-Object { $_ -notlike "GET *" -and $_ -notlike "POST https://login*" } | Should -BeNullOrEmpty
        }

        It "Should skip a mailbox without Exchange Online" {
            $Graph.Unlicensed = @("adele@contoso.com")
            (Sync-Adele).Status | Should -Be "Skipped"
        }

        It "Should skip a mailbox when Graph answers <_>" -ForEach "MailboxNotEnabledForRESTAPI", "MailboxNotSupportedForRESTAPI", "ErrorNonExistentMailbox", "ErrorInvalidUser", "ResourceNotFound" {
            Add-FakeFault -Match "^GET /users/.+/contactFolders$" -Status 404 -Code $_
            (Sync-Adele).Status | Should -Be "Skipped"
        }

        It "Should skip a mailbox that does not exist" {
            (Sync-GALMailbox -Mailbox "nobody@contoso.com" -ContactFolderName "GAL" -DirectoryUser @(Get-GALDirectoryUser)).Status | Should -Be "Skipped"
        }

        It "Should fail a mailbox the app may not access" {
            $Graph.AccessDenied = @("adele@contoso.com")
            $result = Sync-Adele
            $result.Status | Should -Be "Failed"
            $result.Message | Should -BeLike "*ErrorAccessDenied*"
        }

        It "Should report contacts that could not be <Action>" -ForEach @(
            @{ Action = "created"; Match = "^POST /users/.+/contacts$"; Prepare = $false }
            @{ Action = "updated"; Match = "^PATCH /users/.+/contacts/.+$"; Prepare = $true }
            @{ Action = "removed"; Match = "^DELETE /users/.+/contacts/.+$"; Prepare = $true }
        ) {
            if ($Prepare) {
                Sync-Adele | Out-Null
                $Ann.jobTitle = "Changed"
                $Graph.Users.Remove($Bob) | Out-Null
            }
            Add-FakeFault -Match $Match -Status 400 -Code "ErrorInvalidProperty"

            $result = Sync-GALMailbox -Mailbox "adele@contoso.com" -ContactFolderName "GAL" -DirectoryUser @(Get-GALDirectoryUser) -WarningVariable warnings -WarningAction SilentlyContinue

            $result.Status | Should -Be "CompletedWithErrors"
            $result.Failed | Should -Be 1
            $warnings.Message | Should -BeLike "*ErrorInvalidProperty*400*"
        }

        It "Should send contact changes in batches and retry throttled and failed ones" {
            1..43 | ForEach-Object { Add-FakeUser -Id "bulk$_" -Name "Bulk User$_" -Mail "bulk$_@contoso.com" | Out-Null }
            Add-FakeFault -Match "^POST /users/.+/contacts$" -Status 429 -RetryAfter 3 -Times 2
            Add-FakeFault -Match "^POST /users/.+/contacts$" -Status 503 -Code "ServiceUnavailable" -Times 1

            $result = Sync-Adele

            $result.Created | Should -Be 45
            $result.Failed | Should -Be 0
            @(Get-FakeContact -Mailbox "adele@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Sort-Object | Should -Be ($Graph.Users | Where-Object { $_.mobilePhone } | ForEach-Object { $_.id } | Sort-Object)
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -ParameterFilter { $Seconds -eq 3 }
        }

        It "Should wait for the longest Retry-After in a batch" {
            Add-FakeFault -Match "^POST /users/.+/contacts$" -Status 429 -RetryAfter 3
            Add-FakeFault -Match "^POST /users/.+/contacts$" -Status 429 -RetryAfter 7
            (Sync-Adele).Created | Should -Be 2
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 1 -Exactly
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }

        It "Should count contacts that stay throttled as failed" {
            Add-FakeFault -Match "^POST /users/.+/contacts$" -Status 429 -RetryAfter 1 -Times 100

            $result = Sync-Adele

            $result.Created | Should -Be 0
            $result.Failed | Should -Be 2
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 5 -Exactly
        }
    }
}
