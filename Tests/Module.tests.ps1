BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot "../Module"
    $script:ManifestPath = Join-Path $ModuleRoot "GAL-Sync.psd1"
    Import-Module $ManifestPath -Force
}

Describe "GAL-Sync module" {
    It "Should have a valid manifest" {
        { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It "Should export exactly the functions in Public, as listed in the manifest" {
        $manifest = Import-PowerShellDataFile -Path $ManifestPath
        $publicFunctions = Get-ChildItem -Path (Join-Path $ModuleRoot "Public") -Filter "*.ps1" -Recurse | ForEach-Object { ($_.BaseName -Split "_")[1] }
        (Get-Command -Module GAL-Sync).Name | Sort-Object | Should -Be ($manifest.FunctionsToExport | Sort-Object)
        $publicFunctions | Sort-Object | Should -Be ($manifest.FunctionsToExport | Sort-Object)
    }

    It "Should import without warnings" {
        Import-Module $ManifestPath -Force -WarningVariable importWarnings -WarningAction SilentlyContinue
        $importWarnings | Should -BeNullOrEmpty
    }
}
