param (
    [parameter(Mandatory)][string]$ClientId,
    [string]$Path = (Join-Path $PSScriptRoot "Credentials/credential.cred")
)

$ErrorActionPreference = "Stop"

# Export-Clixml encrypts with DPAPI on Windows only: the file works for this user on this computer
if (-not $IsWindows) {
    Write-Warning "On macOS and Linux the secret is stored unencrypted, protect the file or use a certificate instead"
}

$secret = Read-Host -AsSecureString -Prompt "Client secret for $ClientId"
if ($secret.Length -eq 0) {
    throw "No client secret entered"
}

$credentialFolder = Split-Path -Path $Path -Parent
if ($credentialFolder -and -not (Test-Path -Path $credentialFolder)) {
    New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
}
New-Object System.Management.Automation.PSCredential ($ClientId, $secret) | Export-Clixml -Path $Path -Force
Write-Output "Credentials are stored in $Path for $([Environment]::UserName) on $([Environment]::MachineName)"
