param (
    [ValidateSet("Format", "Analyze", "Test", "Package")][string[]]$Task = @("Analyze", "Test", "Package"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "out"),
    [switch]$Integration
)

$ErrorActionPreference = "Stop"
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$analyzerSettings = Join-Path $PSScriptRoot "PSScriptAnalyzerSettings.psd1"
$scripts = Get-ChildItem -Path $PSScriptRoot -Recurse -File -Include "*.ps1", "*.psm1", "*.psd1" | Where-Object { $_.FullName -notlike "$OutputPath*" }

if ("Format" -in $Task -or "Analyze" -in $Task) {
    Import-Module PSScriptAnalyzer -MinimumVersion 1.25.0
    $unformatted = foreach ($script in $scripts) {
        $text = [System.IO.File]::ReadAllText($script.FullName)
        $formatted = Invoke-Formatter -ScriptDefinition $text -Settings $analyzerSettings
        if ($formatted -cne $text) {
            if ("Format" -in $Task) {
                [System.IO.File]::WriteAllText($script.FullName, $formatted)
                Write-Output "Formatted $([System.IO.Path]::GetRelativePath($PSScriptRoot, $script.FullName))"
            }
            else {
                [System.IO.Path]::GetRelativePath($PSScriptRoot, $script.FullName)
            }
        }
    }
}

if ("Analyze" -in $Task) {
    if ($unformatted) {
        throw "Not formatted, run ./build.ps1 -Task Format: $($unformatted -join ", ")"
    }
    $paths = @("Module", "runbook", "deploy" | ForEach-Object { Join-Path $PSScriptRoot $_ }) + @(Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1").FullName
    $issues = @(foreach ($path in $paths) { Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $analyzerSettings })
    if ($issues) {
        $issues | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 220 | Write-Output
        throw "PSScriptAnalyzer found $($issues.Count) issue(s)"
    }
    Write-Output "PSScriptAnalyzer: no issues"
}

if ("Test" -in $Task) {
    Import-Module Pester -MinimumVersion 6.2.0
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "Tests") -Filter "*.tests.ps1" -Recurse).FullName
    $configuration.Run.PassThru = $true
    $configuration.Filter.ExcludeTag = if ($Integration) { @() } else { @("Integration") }
    $configuration.Output.Verbosity = "Detailed"
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = "NUnit3"
    $configuration.TestResult.OutputPath = Join-Path $OutputPath "testResults.xml"
    $result = Invoke-Pester -Configuration $configuration
    if ($result.Result -ne "Passed") {
        throw "Pester: $($result.FailedCount) test(s) and $($result.FailedContainersCount) container(s) failed"
    }
}

if ("Package" -in $Task) {
    $staging = Join-Path $OutputPath "GAL-Sync"
    Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $PSScriptRoot "Module") -Destination $staging -Recurse
    # Azure Automation expects GAL-Sync.zip to contain a GAL-Sync folder with the manifest in it
    Compress-Archive -Path $staging -DestinationPath (Join-Path $OutputPath "GAL-Sync.zip") -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "runbook/GAL-Sync-Runbook.ps1") -Destination $OutputPath -Force
    Write-Output "Packaged GAL-Sync $((Import-PowerShellDataFile (Join-Path $PSScriptRoot "Module/GAL-Sync.psd1")).ModuleVersion) to $OutputPath"
}
