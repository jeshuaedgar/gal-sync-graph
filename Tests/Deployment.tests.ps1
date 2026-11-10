BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph
    $script:Bicep = Get-Content -Path (Join-Path $PSScriptRoot "../deploy/main.bicep") -Raw
    $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    $script:SyncParameters = @((Get-Command Invoke-GALSync).Parameters.Keys | Where-Object { $_ -notin $common })
    $script:AllowedSettings = @((Get-Command Start-GALSync).Parameters.Keys | Where-Object { $_ -notin $common -or $_ -eq "WhatIf" })
    # read by the runbook itself
    $script:RunbookSettings = @("AutomationConnection")

    function Get-BicepBlock ($Start) {
        return [regex]::Match($Bicep, "(?s)$([regex]::Escape($Start))(.+?)\r?\n\r?\n").Groups[1].Value
    }
}

AfterAll {
    Remove-FakeGraph
}

Describe "Deployment" {
    It "Should name the runbook settings after Start-GALSync parameters" {
        $keys = [regex]::Matches((Get-BicepBlock "var configuration = "), "(?m)\b([A-Z][A-Za-z]+):") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $keys | Should -Not -BeNullOrEmpty
        $keys | Where-Object { $_ -notin $AllowedSettings -and $_ -notin $RunbookSettings } | Should -BeNullOrEmpty
    }

    It "Should only pass runbook parameters from the schedule" {
        $runbookParameters = (Get-Command (Join-Path $PSScriptRoot "../runbook/GAL-Sync-Runbook.ps1")).Parameters.Keys
        $keys = [regex]::Matches((Get-BicepBlock "resource jobSchedule "), "(?m)^\s+([A-Z][A-Za-z]+):") | ForEach-Object { $_.Groups[1].Value }
        $keys | Should -Not -BeNullOrEmpty
        $keys | Where-Object { $_ -notin $runbookParameters } | Should -BeNullOrEmpty
    }

    It "Should deploy the release of the module in this repository" {
        $version = (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot "../Module/GAL-Sync.psd1")).ModuleVersion
        $Bicep | Should -Match "param releaseVersion string = '$([regex]::Escape($version))'"
    }

    It "Should grant every Microsoft Graph permission the sync can need" {
        Reset-FakeGraph
        $Graph.TokenClaims.roles = @([regex]::Matches($Bicep, "'([A-Za-z]+\.[A-Za-z]+(\.All)?)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        Connect-FakeGraph
        Add-FakeUser -Id "ann" -Name "Ann Lee" | Out-Null
        Add-FakeGroup -Id "11111111-1111-1111-1111-111111111111" -Name "GAL users" -Members "ann"

        { Invoke-GALSync -ContactFolderName "GAL" -TargetGroup "GAL users" -SourceGroup "GAL users" -IncludeOrgContacts -WarningAction Stop } | Should -Not -Throw
    }

    It "Should let Sync-Contacts.ps1 and Start-GALSync pass every Invoke-GALSync parameter" {
        $scriptParameters = (Get-Command (Join-Path $PSScriptRoot "../Sync-Contacts.ps1")).Parameters.Keys
        $SyncParameters | Where-Object { $_ -notin $scriptParameters } | Should -BeNullOrEmpty
        $SyncParameters | Where-Object { $_ -notin $AllowedSettings } | Should -BeNullOrEmpty
    }

    It "Should only use known settings in the example settings file" {
        $settings = Get-Content -Path (Join-Path $PSScriptRoot "../Sync-Contacts.settings.example.json") -Raw | ConvertFrom-Json -AsHashtable
        # signing in fails with the example values, which is fine as long as the settings themselves are accepted
        $message = try { Start-GALSync -Settings $settings -WhatIf -ErrorAction Stop } catch { $_.Exception.Message }
        $message | Should -Not -BeLike "*Unknown setting*"
    }
}
