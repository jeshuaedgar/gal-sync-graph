BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph
}

AfterAll {
    Remove-FakeGraph
}

Describe "Get-GALDirectoryUser" {
    BeforeEach {
        Reset-FakeGraph
        Connect-FakeGraph
        Add-FakeUser -Id "ann" -Name "Ann Lee" -Upn "a.lee@contoso.onmicrosoft.com" | Out-Null
        Add-FakeUser -Id "biz" -Name "Bea Biz" -Mobile "" -Business "+31 20 1" | Out-Null
        Add-FakeUser -Id "off" -Name "Dis Abled" -Disabled | Out-Null
        Add-FakeUser -Id "ext" -Name "Gus Guest" -Mail "gus@fabrikam.com" -Guest | Out-Null
        Add-FakeUser -Id "nomail" -Name "No Mail" -Mail "" | Out-Null
        Add-FakeUser -Id "nophone" -Name "No Phone" -Mobile "" | Out-Null
    }

    It "Should return enabled members that have an email address and a phone number" {
        (Get-GALDirectoryUser).id | Should -Be @("ann", "biz")
    }

    It "Should include <Expected> with -<Switch>" -ForEach @(
        @{ Switch = "IncludeDisabledUsers"; Expected = "off" }
        @{ Switch = "IncludeGuests"; Expected = "ext" }
        @{ Switch = "IncludeUsersWithoutEmail"; Expected = "nomail" }
        @{ Switch = "IncludeUsersWithoutPhone"; Expected = "nophone" }
    ) {
        $parameters = @{ $Switch = $true }
        (Get-GALDirectoryUser @parameters).id | Should -Be @("ann", "biz", $Expected)
    }

    It "Should leave out users by <By>" -ForEach @(
        @{ By = "object ID"; Value = "ann" }
        @{ By = "user principal name"; Value = "A.LEE@contoso.onmicrosoft.com" }
        @{ By = "email address"; Value = "ann@contoso.com" }
    ) {
        (Get-GALDirectoryUser -ExcludeUser $Value).id | Should -Be @("biz")
    }

    It "Should only return members of the source group, including nested groups" {
        Add-FakeGroup -Id "11111111-1111-1111-1111-111111111111" -Name "All Staff" -Members "ann", "22222222-2222-2222-2222-222222222222"
        Add-FakeGroup -Id "22222222-2222-2222-2222-222222222222" -Name "Sales" -Members "biz"
        Add-FakeUser -Id "outside" -Name "Out Side" | Out-Null

        (Get-GALDirectoryUser -SourceGroup "All Staff").id | Should -Be @("ann", "biz")
        (Get-GALDirectoryUser -SourceGroup "22222222-2222-2222-2222-222222222222").id | Should -Be @("biz")
    }

    It "Should find a source group with a quote in its name" {
        Add-FakeGroup -Id "33333333-3333-3333-3333-333333333333" -Name "O'Brien's team" -Members "biz"
        (Get-GALDirectoryUser -SourceGroup "O'Brien's team").id | Should -Be @("biz")
    }

    It "Should pass a user filter to Microsoft Graph as an advanced query" {
        Get-GALDirectoryUser -UserFilter "companyName eq 'R&D #1'" | Out-Null
        $query = $Graph.UserQueries[-1]
        $query.Query['$filter'] | Should -Be "companyName eq 'R&D #1'"
        $query.Query['$count'] | Should -Be "true"
        $query.Headers["ConsistencyLevel"] | Should -Be "eventual"
    }

    It "Should leave out users that are hidden from the address list when asked" {
        Add-FakeUser -Id "hidden" -Name "Hid Den" -Properties @{ showInAddressList = $false } | Out-Null
        Add-FakeUser -Id "shown" -Name "Sho Wn" -Properties @{ showInAddressList = $true } | Out-Null
        (Get-GALDirectoryUser).id | Should -Contain "hidden"
        (Get-GALDirectoryUser -ExcludeHiddenFromAddressList).id | Should -Be @("ann", "biz", "shown")
    }

    It "Should show a business number as the mobile number when asked" {
        Add-FakeUser -Id "desk" -Name "Desk Phone" -Mobile "" -Business "+31 20 5", "+31 20 6" | Out-Null
        $desk = Get-GALDirectoryUser -BusinessPhoneAsMobile | Where-Object { $_.id -eq "desk" }
        $desk.mobilePhone | Should -Be "+31 20 5"
        $desk.businessPhones | Should -Be @("+31 20 6")
        (Get-GALDirectoryUser -BusinessPhoneAsMobile | Where-Object { $_.id -eq "ann" }).mobilePhone | Should -Be "+31 6 ann"
    }

    It "Should use the email address when a user has no display name" {
        Add-FakeUser -Id "noname" -Name "No Name" -Properties @{ displayName = $null } | Out-Null
        (Get-GALDirectoryUser | Where-Object { $_.id -eq "noname" }).displayName | Should -Be "no@contoso.com"
    }

    It "Should fill every synced contact field for users and mail contacts" {
        Add-FakeOrgContact -Id "oc1" -Name "Vera Vendor" -Mail "vera@vendor.com" -Phones @(@{ type = "mobile"; number = "+44 7 1" }) | Out-Null
        $fields = & (Get-Module GAL-Sync) { $script:contactFields.Keys }
        $entries = @(Get-GALDirectoryUser -IncludeOrgContacts)
        $entries.id | Should -Contain "oc1"
        foreach ($entry in $entries) {
            $fields | Where-Object { $_ -notin $entry.PSObject.Properties.Name } | Should -BeNullOrEmpty
        }
    }

    Context "Mail contacts" {
        BeforeEach {
            Add-FakeOrgContact -Id "oc1" -Name "Vera Vendor" -Mail "vera@vendor.com" -Phones @(
                @{ type = "mobile"; number = "+44 7 1" }
                @{ type = "business"; number = "+44 20 1" }
                @{ type = "businessFax"; number = "+44 20 9" }
            ) | Out-Null
            Add-FakeOrgContact -Id "oc2" -Name "No Number" -Mail "none@vendor.com" | Out-Null
        }

        It "Should only include mail contacts when asked" {
            (Get-GALDirectoryUser).id | Should -Be @("ann", "biz")
            (Get-GALDirectoryUser -IncludeOrgContacts).id | Should -Be @("ann", "biz", "oc1")
        }

        It "Should map mobile and business phones of mail contacts" {
            $contact = Get-GALDirectoryUser -IncludeOrgContacts | Where-Object { $_.id -eq "oc1" }
            $contact.mobilePhone | Should -Be "+44 7 1"
            $contact.businessPhones | Should -Be @("+44 20 1")
        }

        It "Should follow the source group for mail contacts" {
            Add-FakeGroup -Id "33333333-3333-3333-3333-333333333333" -Name "Partners" -Members "ann", "oc1"
            (Get-GALDirectoryUser -IncludeOrgContacts -SourceGroup "Partners").id | Should -Be @("ann", "oc1")
        }
    }

    Context "Microsoft Graph behaviour" {
        BeforeEach {
            Mock Start-Sleep -ModuleName GAL-Sync
        }

        It "Should read every page of a large directory" {
            $Graph.PageSize = 2
            1..5 | ForEach-Object { Add-FakeUser -Id "p$_" -Name "Page User$_" -Mail "page$_@contoso.com" | Out-Null }
            @(Get-GALDirectoryUser).Count | Should -Be 7
        }

        It "Should wait as long as Microsoft Graph asks when it is throttled" {
            Add-FakeFault -Match "^GET /users$" -Status 429 -RetryAfter 7
            (Get-GALDirectoryUser).id | Should -Be @("ann", "biz")
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }

        It "Should retry HTTP <_>" -ForEach 429, 500, 502, 503, 504 {
            Add-FakeFault -Match "^GET /users$" -Status $_ -Code "Transient"
            (Get-GALDirectoryUser).id | Should -Be @("ann", "biz")
            @($Graph.Calls | Where-Object { $_ -like "GET https://graph.microsoft.com/v1.0/users?*" }).Count | Should -Be 2
        }

        It "Should back off and retry server errors and network failures" {
            Add-FakeFault -Match "^GET /users$" -Status 503 -Code "ServiceUnavailable"
            Add-FakeFault -Match "^GET /users$" -Status 0
            (Get-GALDirectoryUser).id | Should -Be @("ann", "biz")
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 2 -Exactly -ParameterFilter { $Seconds -ge 2 }
        }

        It "Should wait at most five minutes" {
            Add-FakeFault -Match "^GET /users$" -Status 429 -RetryAfter 3600
            Get-GALDirectoryUser | Out-Null
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 1 -Exactly -ParameterFilter { $Seconds -eq 300 }
        }

        It "Should give up after five retries" {
            Add-FakeFault -Match "^GET /users$" -Status 503 -Code "ServiceUnavailable" -Times 20
            { Get-GALDirectoryUser } | Should -Throw "*ServiceUnavailable*503*"
            @($Graph.Calls | Where-Object { $_ -like "GET https://graph.microsoft.com/v1.0/users?*" }).Count | Should -Be 6
        }

        It "Should report the Graph error code and message" {
            Add-FakeFault -Match "^GET /users$" -Status 403 -Code "Authorization_RequestDenied"
            { Get-GALDirectoryUser } | Should -Throw "*Authorization_RequestDenied*Injected fault*403*"
        }

        It "Should never write the access token to the verbose stream" {
            Add-FakeFault -Match "^GET /users$" -Status 429 -RetryAfter 1
            $verbose = Get-GALDirectoryUser -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verbose | Should -Not -BeNullOrEmpty
            ($verbose | Out-String) | Should -Not -Match ([regex]::Escape($Graph.LastToken))
        }
    }
}

Describe "Get-GALGroupMember" {
    BeforeAll {
        Reset-FakeGraph
        Connect-FakeGraph
        Add-FakeUser -Id "ann" -Name "Ann Lee" | Out-Null
        Add-FakeUser -Id "bob" -Name "Bob Ray" | Out-Null
        Add-FakeGroup -Id "11111111-1111-1111-1111-111111111111" -Name "All Staff" -Members "ann", "22222222-2222-2222-2222-222222222222"
        Add-FakeGroup -Id "22222222-2222-2222-2222-222222222222" -Name "Sales" -Members "bob"
        Add-FakeGroup -Id "44444444-4444-4444-4444-444444444444" -Name "Sales" -Members @()
    }

    It "Should return users from nested groups" {
        (Get-GALGroupMember -Group "All Staff").id | Should -Be @("ann", "bob")
        (Get-GALGroupMember -Group "11111111-1111-1111-1111-111111111111").userPrincipalName | Should -Be @("ann@contoso.com", "bob@contoso.com")
    }

    It "Should explain a group that does not exist" {
        { Get-GALGroupMember -Group "Nobody" } | Should -Throw "*Nobody*not found*"
    }

    It "Should ask for the object ID when the name is ambiguous" {
        { Get-GALGroupMember -Group "Sales" } | Should -Throw "*object ID*"
    }
}
