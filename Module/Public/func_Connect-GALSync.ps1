function Connect-GALSync {
    [CmdletBinding(DefaultParameterSetName = "ManagedIdentity")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "CredentialPath", Justification = "File path, not a secret.")]
    param (
        [parameter(ParameterSetName = "ManagedIdentity", Mandatory)][switch]$ManagedIdentity,

        [parameter(ParameterSetName = "CertificateThumbprint", Mandatory)]
        [parameter(ParameterSetName = "Certificate", Mandatory)]
        [parameter(ParameterSetName = "ClientSecret", Mandatory)]
        [parameter(ParameterSetName = "CredentialFile", Mandatory)]
        [string]$TenantId,

        [parameter(ParameterSetName = "CertificateThumbprint", Mandatory)]
        [parameter(ParameterSetName = "Certificate", Mandatory)]
        [string]$ClientId,

        [parameter(ParameterSetName = "CertificateThumbprint", Mandatory)][string]$CertificateThumbprint,
        [parameter(ParameterSetName = "Certificate", Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [parameter(ParameterSetName = "ClientSecret", Mandatory)][pscredential]$Credential,
        [parameter(ParameterSetName = "CredentialFile", Mandatory)][string]$CredentialPath
    )
    switch ($PSCmdlet.ParameterSetName) {
        "CertificateThumbprint" {
            $thumbprint = $CertificateThumbprint -replace "\s", ""
            foreach ($location in "CurrentUser", "LocalMachine") {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "My", $location
                try {
                    $store.Open("ReadOnly")
                    $Certificate = $store.Certificates.Find("FindByThumbprint", $thumbprint, $false) | Select-Object -First 1
                }
                catch {
                    # macOS and Linux have no LocalMachine store
                    Write-VerboseEvent "Certificate store $location\My is not available: $($_.Exception.Message)"
                }
                finally {
                    $store.Close()
                }
                if ($Certificate) { break }
            }
            if (-not $Certificate) {
                throw "Certificate with thumbprint $thumbprint was not found in the CurrentUser or LocalMachine certificate store"
            }
        }
        "CredentialFile" {
            if (-not (Test-Path -Path $CredentialPath -PathType Leaf)) {
                throw "Credential file $CredentialPath does not exist, create one with New-StoredCredential.ps1"
            }
            $Credential = Import-Clixml -Path $CredentialPath
        }
    }
    if ($Certificate -and -not $Certificate.HasPrivateKey) {
        throw "Certificate $($Certificate.Thumbprint) has no private key"
    }

    $signIn = [pscustomobject]@{
        Method      = if ($ManagedIdentity) { "ManagedIdentity" } elseif ($Certificate) { "Certificate" } else { "ClientSecret" }
        TenantId    = $TenantId
        ClientId    = if ($Credential) { $Credential.UserName } else { $ClientId }
        Secret      = $Credential.Password
        Certificate = $Certificate
    }
    $script:galSyncData = $null
    $token = Request-AccessToken -SignIn $signIn
    $script:galSyncData = [hashtable]::Synchronized(@{
            SignIn = $signIn
            Token  = $token
        })

    return [pscustomobject]@{
        TenantId   = $token.TenantId
        ClientId   = $token.ClientId
        AuthMethod = $signIn.Method
        Roles      = $token.Roles
        ExpiresOn  = $token.ExpiresOn
    }
}
