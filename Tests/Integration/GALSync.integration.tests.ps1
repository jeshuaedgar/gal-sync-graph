# Runs against a real test tenant
BeforeDiscovery {
    $script:Configured = $env:GALSYNC_TENANT_ID -and $env:GALSYNC_CLIENT_ID -and $env:GALSYNC_CLIENT_SECRET -and $env:GALSYNC_TEST_MAILBOX
}

Describe "GAL-Sync against a live tenant" -Tag "Integration" -Skip:(-not $Configured) {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot "../../Module/GAL-Sync.psd1") -Force
        $secret = ConvertTo-SecureString $env:GALSYNC_CLIENT_SECRET -AsPlainText -Force
        $script:Connection = Connect-GALSync -TenantId $env:GALSYNC_TENANT_ID -Credential ([pscredential]::new($env:GALSYNC_CLIENT_ID, $secret))
        $script:Mailbox = $env:GALSYNC_TEST_MAILBOX
        $script:FolderName = "GAL-Sync test $([guid]::NewGuid().ToString("N").Substring(0, 8))"
        $script:Users = @(Get-GALDirectoryUser | Select-Object -First 5)
    }

    AfterAll {
        if ($Mailbox -and $FolderName) {
            Remove-GALContactFolder -Mailbox $Mailbox -Name $FolderName -Confirm:$false
        }
        Disconnect-GALSync
    }

    It "Should have the permissions it needs" {
        $Connection.Roles | Where-Object { $_ -in "User.Read.All", "User.ReadWrite.All", "Directory.Read.All", "Directory.ReadWrite.All" } | Should -Not -BeNullOrEmpty
    }

    It "Should find directory users" {
        $Users.Count | Should -BeGreaterThan 0
    }

    It "Should create a tagged contact for every user" {
        $result = Sync-GALMailbox -Mailbox $Mailbox -ContactFolderName $FolderName -DirectoryUser $Users
        $result.Status | Should -Be "Succeeded"
        $result.Created | Should -Be $Users.Count

        $folder = Get-GALContactFolder -Mailbox $Mailbox -Name $FolderName
        $folder.isManaged | Should -BeTrue
        ($folder | Get-GALFolderContact).sourceId | Sort-Object | Should -Be ($Users.id | Sort-Object)
    }

    It "Should report no changes on the next run" {
        $result = Sync-GALMailbox -Mailbox $Mailbox -ContactFolderName $FolderName -DirectoryUser $Users
        $result.Unchanged | Should -Be $Users.Count
        ($result.Created + $result.Updated + $result.Removed) | Should -Be 0
    }

    It "Should remove contacts of users that are no longer synced" {
        $result = Sync-GALMailbox -Mailbox $Mailbox -ContactFolderName $FolderName -DirectoryUser @($Users | Select-Object -First 1)
        $result.Removed | Should -Be ($Users.Count - 1)
    }
}
