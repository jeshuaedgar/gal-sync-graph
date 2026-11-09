set shell := ["pwsh", "-NoProfile", "-Command"]
set windows-shell := ["pwsh", "-NoProfile", "-Command"]

# list the recipes
default:
    @just --list

# install the tools the build needs
setup:
    Install-PSResource -Name Pester -Version 6.2.0 -Scope CurrentUser -TrustRepository -Quiet
    Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -Scope CurrentUser -TrustRepository -Quiet

# lint, test and package, like CI does
build:
    ./build.ps1

# format all PowerShell scripts
fmt:
    ./build.ps1 -Task Format

# check formatting and run PSScriptAnalyzer
lint:
    ./build.ps1 -Task Analyze

# run the tests
test:
    ./build.ps1 -Task Test

# run the tests against a test tenant as well (needs the GALSYNC_* variables)
test-integration:
    ./build.ps1 -Task Test -Integration

# build out/GAL-Sync.zip and the runbook
package:
    ./build.ps1 -Task Package

# build and lint the Bicep templates
bicep:
    az bicep build --file deploy/main.bicep --outdir out
    az bicep build-params --file deploy/main.bicepparam --outfile out/main.parameters.json
    az bicep lint --file deploy/main.bicep

# remove the build output
clean:
    Remove-Item -Path out -Recurse -Force -ErrorAction SilentlyContinue
