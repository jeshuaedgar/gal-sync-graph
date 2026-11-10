BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph

    function Add-Staff {
        Add-FakeUser -Id "ann" -Name "Ann Lee" | Out-Null
        Add-FakeUser -Id "bob" -Name "Bob Ray" -Mobile "" -Business "+31 20 2" | Out-Null
        Add-FakeUser -Id "off" -Name "Dis Abled" -Disabled | Out-Null
        Add-FakeUser -Id "ext" -Name "Gus Guest" -Mail "gus@fabrikam.com" -Guest | Out-Null
        Add-FakeUser -Id "nomail" -Name "No Mail" -Mail "" | Out-Null
        Add-FakeUser -Id "svc" -Name "Scan Service" -Mail "scanner@contoso.com" | Out-Null
        Add-FakeGroup -Id "11111111-1111-1111-1111-111111111111" -Name "GAL users" -Members "ann", "off", "ext", "nomail", "22222222-2222-2222-2222-222222222222"
        Add-FakeGroup -Id "22222222-2222-2222-2222-222222222222" -Name "Nested" -Members "bob", "svc"
    }

    function New-CredentialFile {
        $path = Join-Path $TestDrive "credential.cred"
        New-Object System.Management.Automation.PSCredential ("app-id", (ConvertTo-SecureString "secret" -AsPlainText -Force)) | Export-Clixml -Path $path
        return $path
    }
}

AfterAll {
    Remove-FakeGraph
}

Describe "Invoke-GALSync" {
    BeforeEach {
        Reset-FakeGraph
        Connect-FakeGraph
        Add-Staff
    }

    It "Should sync every target mailbox in parallel and report each one" {
        $Graph.Unlicensed = @("room@contoso.com")
        $results = @(Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com", "bob@contoso.com", "scanner@contoso.com", "room@contoso.com" -ThrottleLimit 3)

        $results.Count | Should -Be 4
        ($results | Where-Object { $_.Mailbox -eq "room@contoso.com" }).Status | Should -Be "Skipped"
        ($results | Where-Object { $_.Status -eq "Succeeded" }).Created | Should -Be @(3, 3, 3)
        (Get-FakeContact -Mailbox "bob@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Sort-Object | Should -Be @("ann", "bob", "svc")
    }

    It "Should accept comma-separated mailboxes and exclusions" {
        $results = @(Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "bob@contoso.com, ann@contoso.com,,ann@contoso.com" -ExcludeUser "bob@contoso.com,svc")
        $results.Mailbox | Should -Be @("ann@contoso.com")
        (Get-FakeContact -Mailbox "ann@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Should -Be @("ann")
    }

    It "Should target enabled members with an email address when syncing <Mode>" -ForEach @(
        @{ Mode = "all users"; Parameters = @{ AllUsers = $true } }
        @{ Mode = "a group"; Parameters = @{ TargetGroup = "GAL users" } }
    ) {
        $results = @(Invoke-GALSync -ContactFolderName "GAL" @Parameters)
        $results.Mailbox | Sort-Object | Should -Be @("ann@contoso.com", "bob@contoso.com", "scanner@contoso.com")
    }

    It "Should leave excluded users out as contacts and as targets of <Mode>" -ForEach @(
        @{ Mode = "all users"; Parameters = @{ AllUsers = $true } }
        @{ Mode = "a group"; Parameters = @{ TargetGroup = "GAL users" } }
    ) {
        $results = @(Invoke-GALSync -ContactFolderName "GAL" -ExcludeUser "scanner@contoso.com" @Parameters)
        $results.Mailbox | Sort-Object | Should -Be @("ann@contoso.com", "bob@contoso.com")
        (Get-FakeContact -Mailbox "ann@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Sort-Object | Should -Be @("ann", "bob")
    }

    It "Should warn when there is no mailbox to sync" {
        Invoke-GALSync -ContactFolderName "GAL" -TargetGroup "Nested" -ExcludeUser "bob", "svc" -SourceGroup "GAL users" -WarningVariable warnings -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        $warnings.Message | Should -BeLike "*No target mailboxes*"
    }

    It "Should pass contact options on to every mailbox" {
        Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com", "scanner@contoso.com" -BusinessPhoneAsMobile -ThrottleLimit 2 | Out-Null
        foreach ($mailbox in "ann@contoso.com", "scanner@contoso.com") {
            (Get-FakeContact -Mailbox $mailbox -SourceId "bob").mobilePhone | Should -Be "+31 20 2"
        }
    }

    It "Should write verbose output from every mailbox" {
        $verbose = Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com", "bob@contoso.com" -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        ($verbose | Out-String) | Should -Match "contact folders for ann@contoso\.com"
        ($verbose | Out-String) | Should -Match "contact folders for bob@contoso\.com"
    }

    It "Should write nothing with -WhatIf" {
        $results = @(Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com", "bob@contoso.com" -WhatIf)
        $results.Status | Should -Be @("WhatIf", "WhatIf")
        $Graph.Calls | Where-Object { $_ -notlike "GET *" -and $_ -notlike "POST https://login*" } | Should -BeNullOrEmpty
    }

    It "Should refuse to run when no directory users match, instead of emptying every folder" {
        { Invoke-GALSync -ContactFolderName "GAL" -TargetMailbox "ann@contoso.com" -SourceGroup "Nested" -ExcludeUser "bob", "svc" } | Should -Throw "*remove every contact*"
        $Graph.Calls | Where-Object { $_ -like "*contactFolders*" } | Should -BeNullOrEmpty
    }

    Context "Permissions" {
        It "Should fail early when <Permission> is missing for <Case>" -ForEach @(
            @{ Permission = "User.Read.All"; Case = "any sync"; Roles = @("Contacts.ReadWrite"); Parameters = @{ TargetMailbox = "ann@contoso.com" } }
            @{ Permission = "GroupMember.Read.All"; Case = "a target group"; Roles = @("User.Read.All", "Contacts.ReadWrite"); Parameters = @{ TargetGroup = "Nested" } }
            @{ Permission = "GroupMember.Read.All"; Case = "a source group"; Roles = @("User.Read.All", "Contacts.ReadWrite"); Parameters = @{ TargetMailbox = "ann@contoso.com"; SourceGroup = "Nested" } }
            @{ Permission = "OrgContact.Read.All"; Case = "mail contacts"; Roles = @("User.Read.All", "Contacts.ReadWrite"); Parameters = @{ TargetMailbox = "ann@contoso.com"; IncludeOrgContacts = $true } }
        ) {
            $Graph.TokenClaims.roles = $Roles
            Connect-FakeGraph
            { Invoke-GALSync -ContactFolderName "GAL" @Parameters } | Should -Throw "*$Permission*"
            $Graph.Calls | Where-Object { $_ -like "GET https://graph*" } | Should -BeNullOrEmpty
        }

        It "Should accept Directory.Read.All instead of the separate read permissions" {
            $Graph.TokenClaims.roles = @("Directory.Read.All", "Contacts.ReadWrite")
            Connect-FakeGraph
            @(Invoke-GALSync -ContactFolderName "GAL" -TargetGroup "GAL users" -IncludeOrgContacts).Count | Should -Be 3
        }
    }
}

Describe "Start-GALSync" {
    BeforeEach {
        Reset-FakeGraph
        Add-Staff
        $script:Settings = @{
            TenantId          = "contoso.onmicrosoft.com"
            CredentialPath    = New-CredentialFile
            ContactFolderName = "GAL"
            TargetMailbox     = "ann@contoso.com"
            AllUsers          = $false
        }
    }

    It "Should connect, sync and return the results with a settings hashtable" {
        $results = @(Start-GALSync -Settings $Settings)
        $results.Mailbox | Should -Be @("ann@contoso.com")
        $results.Status | Should -Be @("Succeeded")
    }

    It "Should read the same settings from a file" {
        $file = Join-Path $TestDrive "start.json"
        $Settings | ConvertTo-Json | Set-Content -Path $file -Encoding utf8
        @(Start-GALSync -ConfigFile $file).Status | Should -Be @("Succeeded")
    }

    It "Should let parameters override the settings" {
        $results = @(Start-GALSync -Settings $Settings -TargetMailbox "bob@contoso.com")
        $results.Mailbox | Should -Be @("bob@contoso.com")
    }

    It "Should honour WhatIf from the settings" {
        $Settings.WhatIf = $true
        @(Start-GALSync -Settings $Settings).Status | Should -Be @("WhatIf")
        $Graph.Calls | Where-Object { $_ -match "^(POST|PATCH|DELETE) https://graph" } | Should -BeNullOrEmpty
    }

    It "Should return failed mailboxes instead of throwing" {
        $Graph.AccessDenied = @("ann@contoso.com")
        @(Start-GALSync -Settings $Settings -WarningAction SilentlyContinue).Status | Should -Be @("Failed")
    }

    It "Should refuse <Case>" -ForEach @(
        @{ Case = "unknown settings"; Change = @{ Colour = "blue" }; Message = "*Unknown setting*Colour*" }
        @{ Case = "a missing contact folder name"; Change = @{ ContactFolderName = "" }; Message = "*ContactFolderName*" }
        @{ Case = "no target"; Change = @{ TargetMailbox = @() }; Message = "*exactly one*" }
        @{ Case = "two targets"; Change = @{ AllUsers = $true }; Message = "*exactly one*" }
        @{ Case = "a missing tenant"; Change = @{ TenantId = "" }; Message = "*TenantId*" }
    ) {
        foreach ($key in $Change.Keys) { $Settings[$key] = $Change[$key] }
        { Start-GALSync -Settings $Settings } | Should -Throw $Message
        $Graph.Calls | Should -BeNullOrEmpty
    }

    It "Should refuse -ConfigFile together with -Settings" {
        { Start-GALSync -Settings $Settings -ConfigFile "x.json" } | Should -Throw "*not both*"
    }
}

Describe "Azure Automation runbook" {
    BeforeEach {
        Reset-FakeGraph
        Add-Staff
        # shaped like the GALSyncConfig variable that deploy/main.bicep creates
        $global:GALSyncTestSettings = @{
            AllUsers                     = $false
            TargetMailbox                = "ann@contoso.com,room@contoso.com"
            ExcludeUser                  = "bob@contoso.com,svc"
            ContactFolderName            = "GAL"
            IncludeUsersWithoutPhone     = $false
            IncludeUsersWithoutEmail     = $false
            IncludeDisabledUsers         = $false
            IncludeGuests                = $false
            ExcludeHiddenFromAddressList = $false
            IncludeOrgContacts           = $false
            BusinessPhoneAsMobile        = $false
            ThrottleLimit                = 4
            WhatIf                       = $false
        }
        function global:Get-AutomationVariable {
            param ([string]$Name)
            if ($Name -ne "GALSyncSettings") { throw "Unexpected variable $Name" }
            return $global:GALSyncTestSettings | ConvertTo-Json -Compress
        }
        $script:ModulePath = $env:PSModulePath
        $env:PSModulePath = "{0}{1}{2}" -f (Join-Path $Graph.Root "modules"), [System.IO.Path]::PathSeparator, $env:PSModulePath
        $script:Runbook = Join-Path $Graph.Root "runbook/GAL-Sync-Runbook.ps1"
        $Graph.Unlicensed = @("room@contoso.com")
    }

    AfterEach {
        $env:PSModulePath = $ModulePath
        Remove-Item Function:\Get-AutomationVariable
        Remove-Variable -Name GALSyncTestSettings -Scope Global
    }

    It "Should sign in with the managed identity and sync with the settings variable" {
        $output = @(& $Runbook -ConfigurationVariable "GALSyncSettings" -WarningAction SilentlyContinue 4>$null)

        $Graph.Calls | Where-Object { $_ -like "GET http://169.254.169.254/*" } | Should -Not -BeNullOrEmpty
        $output.Count | Should -Be 1
        $results = $output[0] | ConvertFrom-Json
        ($results | Where-Object { $_.Mailbox -eq "ann@contoso.com" }).Status | Should -Be "Succeeded"
        ($results | Where-Object { $_.Mailbox -eq "room@contoso.com" }).Status | Should -Be "Skipped"
        (Get-FakeContact -Mailbox "ann@contoso.com" | ForEach-Object { Get-FakeSourceId $_ }) | Should -Be @("ann")
    }

    It "Should write a readable table to the verbose stream" {
        $verbose = & $Runbook -ConfigurationVariable "GALSyncSettings" -WarningAction SilentlyContinue 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        ($verbose.Message -join "`n") | Should -Match "ann@contoso\.com\s+Succeeded"
    }

    It "Should stop on unknown settings" {
        $global:GALSyncTestSettings.Colour = "blue"
        { & $Runbook -ConfigurationVariable "GALSyncSettings" 4>$null } | Should -Throw "*Unknown setting*Colour*"
        $Graph.Calls | Where-Object { $_ -like "*contactFolders*" } | Should -BeNullOrEmpty
    }

    Context "GALSync connection" {
        BeforeEach {
            $global:GALSyncTestSettings.AutomationConnection = "GAL-Sync"
            $global:GALSyncTestConnection = @{ TenantId = "contoso.onmicrosoft.com"; ClientId = "app-id"; ClientSecret = "secret"; CertificateName = "" }
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest ("CN=GAL-Sync test", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $global:GALSyncTestCertificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddMinutes(-5), [System.DateTimeOffset]::UtcNow.AddDays(1))
            function global:Get-AutomationConnection {
                param ([string]$Name)
                if ($Name -ne "GAL-Sync") { throw "Unexpected connection $Name" }
                return $global:GALSyncTestConnection
            }
            function global:Get-AutomationCertificate {
                param ([string]$Name)
                if ($Name -ne "GAL-Sync-Cert") { throw "Unexpected certificate $Name" }
                return $global:GALSyncTestCertificate
            }
        }

        AfterEach {
            Remove-Item Function:\Get-AutomationConnection, Function:\Get-AutomationCertificate
            Remove-Variable -Name GALSyncTestConnection, GALSyncTestCertificate -Scope Global
        }

        It "Should sign in with the client secret of the connection" {
            $output = & $Runbook -ConfigurationVariable "GALSyncSettings" -WarningAction SilentlyContinue 4>$null
            (($output | ConvertFrom-Json) | Where-Object { $_.Mailbox -eq "ann@contoso.com" }).Status | Should -Be "Succeeded"
            $Graph.Calls | Where-Object { $_ -like "POST https://login.microsoftonline.com/contoso.onmicrosoft.com/*" } | Should -Not -BeNullOrEmpty
            $Graph.Calls | Where-Object { $_ -like "GET http://169.254.169.254/*" } | Should -BeNullOrEmpty
        }

        It "Should sign in with the certificate asset named in the connection" {
            $GALSyncTestConnection.ClientSecret = ""
            $GALSyncTestConnection.CertificateName = "GAL-Sync-Cert"
            $output = & $Runbook -ConfigurationVariable "GALSyncSettings" -WarningAction SilentlyContinue 4>$null
            (($output | ConvertFrom-Json) | Where-Object { $_.Mailbox -eq "ann@contoso.com" }).Status | Should -Be "Succeeded"
            $Graph.Calls | Where-Object { $_ -like "POST https://login.microsoftonline.com/contoso.onmicrosoft.com/*" } | Should -Not -BeNullOrEmpty
        }

        It "Should explain a connection without <Missing>" -ForEach @(
            @{ Missing = "a secret or certificate"; Change = @{ ClientSecret = "" }; Message = "*needs TenantId, ClientId and a ClientSecret or CertificateName*" }
            @{ Missing = "a tenant"; Change = @{ TenantId = "" }; Message = "*needs TenantId, ClientId and a ClientSecret or CertificateName*" }
        ) {
            foreach ($key in $Change.Keys) { $GALSyncTestConnection[$key] = $Change[$key] }
            { & $Runbook -ConfigurationVariable "GALSyncSettings" 4>$null } | Should -Throw $Message
        }
    }

    It "Should fail the job when a mailbox fails" {
        $Graph.AccessDenied = @("ann@contoso.com")
        { & $Runbook -ConfigurationVariable "GALSyncSettings" -WarningAction SilentlyContinue 4>$null } | Should -Throw "*1 of 2*"
    }

    It "Should only report planned changes with -WhatIfMode" {
        $output = & $Runbook -ConfigurationVariable "GALSyncSettings" -WhatIfMode $true -WarningAction SilentlyContinue 4>$null
        (($output | ConvertFrom-Json) | Where-Object { $_.Mailbox -eq "ann@contoso.com" }).Status | Should -Be "WhatIf"
        $Graph.Calls | Where-Object { $_ -like "GET https://graph*contactFolders*" } | Should -Not -BeNullOrEmpty
        $Graph.Calls | Where-Object { $_ -match "^(POST|PATCH|DELETE) https://graph" } | Should -BeNullOrEmpty
    }
}

Describe "Sync-Contacts.ps1" {
    BeforeEach {
        Reset-FakeGraph
        Add-Staff
        $script:Script = Join-Path $Graph.Root "Sync-Contacts.ps1"
        $script:ConfigFile = Join-Path $TestDrive "settings.json"
        @{
            TenantId          = "contoso.onmicrosoft.com"
            CredentialPath    = New-CredentialFile
            ContactFolderName = "Collega's Zoë"
            TargetMailbox     = @("ann@contoso.com")
            AllUsers          = $false
        } | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding utf8
        $global:LASTEXITCODE = -1
    }

    It "Should sync with a settings file and keep accented characters" {
        & $Script -ConfigFile $ConfigFile | Out-Null
        $LASTEXITCODE | Should -Be 0
        @(Get-FakeContact -Mailbox "ann@contoso.com" -Name "Collega's Zoë").Count | Should -Be 3
    }

    It "Should let command-line parameters override the settings file" {
        & $Script -ConfigFile $ConfigFile -ContactFolderName "Override" -TargetMailbox "bob@contoso.com" | Out-Null
        $LASTEXITCODE | Should -Be 0
        @(Get-FakeContact -Mailbox "bob@contoso.com" -Name "Override").Count | Should -Be 3
        $Graph.Mailboxes.ContainsKey("ann@contoso.com") | Should -BeFalse
    }

    It "Should write nothing with -WhatIf" {
        & $Script -ConfigFile $ConfigFile -LogPath (Join-Path $TestDrive "whatif-logs") -WhatIf | Out-Null
        $LASTEXITCODE | Should -Be 0
        $Graph.Calls | Where-Object { $_ -match "^(POST|PATCH|DELETE) https://graph" } | Should -BeNullOrEmpty
    }

    It "Should keep a transcript in the log folder" {
        $logs = Join-Path $TestDrive "logs"
        & $Script -ConfigFile $ConfigFile -LogPath $logs | Out-Null
        Get-ChildItem -Path $logs -Filter "*.txt" | Should -Not -BeNullOrEmpty
    }

    It "Should stop on unknown settings" {
        @{ TenantId = "contoso.onmicrosoft.com"; CredentialPath = New-CredentialFile; ContactFolderName = "GAL"; TargetMailbox = "ann@contoso.com"; Colour = "blue" } |
        ConvertTo-Json | Set-Content -Path $ConfigFile
        & $Script -ConfigFile $ConfigFile -ErrorVariable errors -ErrorAction SilentlyContinue 2>$null | Out-Null
        ($errors | Out-String) | Should -BeLike "*Colour*"
        $LASTEXITCODE | Should -Be 1
        $Graph.Calls | Where-Object { $_ -like "*contactFolders*" } | Should -BeNullOrEmpty
    }

    It "Should read the log folder from the settings file" {
        $logs = Join-Path $TestDrive "file-logs"
        $settings = Get-Content $ConfigFile -Raw | ConvertFrom-Json -AsHashtable
        $settings.LogPath = $logs
        $settings | ConvertTo-Json | Set-Content -Path $ConfigFile
        & $Script -ConfigFile $ConfigFile | Out-Null
        $LASTEXITCODE | Should -Be 0
        Get-ChildItem -Path $logs -Filter "*.txt" | Should -Not -BeNullOrEmpty
    }

    It "Should exit with 1 when <Case>" -ForEach @(
        @{ Case = "a mailbox fails"; Arrange = { $Graph.AccessDenied = @("ann@contoso.com") }; Parameters = @{} }
        @{ Case = "no tenant is given"; Arrange = {}; Parameters = @{ TenantId = "" } }
        @{ Case = "no target is given"; Arrange = {}; Parameters = @{ TargetMailbox = @() } }
    ) {
        . $Arrange
        $settings = Get-Content $ConfigFile -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in $Parameters.Keys) { $settings[$key] = $Parameters[$key] }
        $settings | ConvertTo-Json | Set-Content -Path $ConfigFile
        & $Script -ConfigFile $ConfigFile -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}
