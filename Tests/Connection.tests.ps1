BeforeAll {
    . (Join-Path $PSScriptRoot "FakeGraph.ps1")
    $script:Graph = New-FakeGraph

    function Get-Query ($Uri) {
        $query = @{}
        foreach ($pair in ([System.Uri]$Uri).Query.TrimStart("?").Split("&")) {
            $key, $value = $pair.Split("=", 2)
            $query[$key] = [System.Uri]::UnescapeDataString($value)
        }
        return $query
    }
}

AfterAll {
    Remove-FakeGraph
}

Describe "Connect-GALSync" {
    BeforeEach {
        Reset-FakeGraph
        Disconnect-GALSync
        Add-FakeUser -Id "u1" -Name "Ann Lee" | Out-Null
    }

    It "Should connect with a client secret and report the tenant, app and roles" {
        $credential = New-Object System.Management.Automation.PSCredential ("app-id", (ConvertTo-SecureString "secret-value" -AsPlainText -Force))
        $connection = Connect-GALSync -TenantId "contoso.onmicrosoft.com" -Credential $credential

        $connection.TenantId | Should -Be "tenant-id"
        $connection.ClientId | Should -Be "app-id"
        $connection.Roles | Should -Contain "User.Read.All"
        $Graph.Calls[0] | Should -Be "POST https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token"
        $Graph.LastLogin.client_id | Should -Be "app-id"
        $Graph.LastLogin.client_secret | Should -Be "secret-value"
        $Graph.LastLogin.scope | Should -Be "https://graph.microsoft.com/.default"
        $Graph.LastLogin.grant_type | Should -Be "client_credentials"
    }

    It "Should send the token with every Graph request" {
        Connect-FakeGraph
        @(Get-GALDirectoryUser).Count | Should -Be 1
        $Graph.Requests | Where-Object { $_.Uri -like "https://graph.microsoft.com/*" } | ForEach-Object {
            $_.Headers.Authorization | Should -Be "Bearer $($Graph.LastToken)"
        }
    }

    It "Should read a stored credential file" {
        $path = Join-Path $TestDrive "credential.cred"
        New-Object System.Management.Automation.PSCredential ("stored-app", (ConvertTo-SecureString "stored-secret" -AsPlainText -Force)) | Export-Clixml -Path $path
        Connect-GALSync -TenantId "contoso.onmicrosoft.com" -CredentialPath $path | Out-Null
        $Graph.LastLogin.client_id | Should -Be "stored-app"
        $Graph.LastLogin.client_secret | Should -Be "stored-secret"
    }

    It "Should explain a missing credential file" {
        { Connect-GALSync -TenantId "contoso.onmicrosoft.com" -CredentialPath (Join-Path $TestDrive "missing.cred") } | Should -Throw "*New-StoredCredential.ps1*"
    }

    It "Should use the Azure Automation managed identity endpoint when it is available" {
        $env:IDENTITY_ENDPOINT = "http://127.0.0.1:41000/oauth2/token"
        $env:IDENTITY_HEADER = "identity-header-value"
        try {
            Connect-GALSync -ManagedIdentity | Out-Null
        }
        finally {
            Remove-Item Env:\IDENTITY_ENDPOINT, Env:\IDENTITY_HEADER
        }
        $request = $Graph.Requests[0]
        $request.Method | Should -Be "GET"
        $request.Uri | Should -BeLike "http://127.0.0.1:41000/oauth2/token?*"
        $query = Get-Query $request.Uri
        $query.resource | Should -Be "https://graph.microsoft.com/"
        $request.Headers["X-IDENTITY-HEADER"] | Should -Be "identity-header-value"
        $request.Headers["Metadata"] | Should -Be "True"
    }

    It "Should fall back to the instance metadata service outside Azure Automation" {
        Connect-GALSync -ManagedIdentity | Out-Null
        $request = $Graph.Requests[0]
        $request.Uri | Should -BeLike "http://169.254.169.254/metadata/identity/oauth2/token?*"
        $query = Get-Query $request.Uri
        $query."api-version" | Should -Be "2018-02-01"
        $query.resource | Should -Be "https://graph.microsoft.com/"
        $request.Headers["Metadata"] | Should -Be "true"
    }

    It "Should report why sign-in failed and drop the previous connection" {
        Connect-FakeGraph
        $Graph.LoginError = "AADSTS7000215: Invalid client secret provided."
        $credential = New-Object System.Management.Automation.PSCredential ("app-id", (ConvertTo-SecureString "bad" -AsPlainText -Force))
        { Connect-GALSync -TenantId "contoso.onmicrosoft.com" -Credential $credential } | Should -Throw "*AADSTS7000215*"
        { Get-GALDirectoryUser } | Should -Throw "*Connect-GALSync*"
    }

    It "Should require a connection" {
        { Get-GALDirectoryUser } | Should -Throw "*Connect-GALSync*"
    }

    Context "Certificates" {
        BeforeAll {
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest ("CN=GAL-Sync test", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $script:Certificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddMinutes(-5), [System.DateTimeOffset]::UtcNow.AddDays(1))
            function ConvertFrom-Base64Url ($Part) {
                $padded = $Part.Replace("-", "+").Replace("_", "/")
                $padded += "=" * ((4 - $padded.Length % 4) % 4)
                return , [System.Convert]::FromBase64String($padded)
            }
        }

        It "Should sign a PS256 client assertion that Entra ID can verify" {
            Connect-GALSync -TenantId "contoso.onmicrosoft.com" -ClientId "app-id" -Certificate $Certificate | Out-Null

            $Graph.LastLogin.client_assertion_type | Should -Be "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            $header, $payload, $signature = $Graph.LastLogin.client_assertion.Split(".")
            $headerJson = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $header)) | ConvertFrom-Json
            $claims = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $payload)) | ConvertFrom-Json
            $thumbprint = [System.Convert]::ToBase64String($Certificate.GetCertHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
            $now = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

            $headerJson.alg | Should -Be "PS256"
            $headerJson."x5t#S256" | Should -Be $thumbprint
            $claims.aud | Should -Be "https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token"
            $claims.iss | Should -Be "app-id"
            $claims.sub | Should -Be "app-id"
            $claims.nbf | Should -BeLessOrEqual $now
            $claims.exp | Should -BeGreaterThan $now
            ($claims.exp - $claims.nbf) | Should -BeLessOrEqual 600
            $publicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
            $publicKey.VerifyData([System.Text.Encoding]::UTF8.GetBytes("$header.$payload"), (ConvertFrom-Base64Url $signature),
                [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pss) | Should -BeTrue
        }

        It "Should reject a certificate without a private key" {
            $publicOnly = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 (, $Certificate.Export("Cert"))
            { Connect-GALSync -TenantId "contoso.onmicrosoft.com" -ClientId "app-id" -Certificate $publicOnly } | Should -Throw "*private key*"
        }
    }

    Context "Token lifetime" {
        It "Should reuse a token that is still valid" {
            Connect-FakeGraph
            Get-GALDirectoryUser | Out-Null
            Get-GALDirectoryUser | Out-Null
            $Graph.TokenRequests | Should -Be 1
        }

        It "Should get a new token shortly before the old one expires" {
            $Graph.TokenLifetime = 240
            Connect-FakeGraph
            Get-GALDirectoryUser | Out-Null
            $Graph.TokenRequests | Should -Be 2
        }

        It "Should get a new token once when Graph rejects the current one" {
            Connect-FakeGraph
            Add-FakeFault -Match "^GET /users$" -Status 401 -Code "InvalidAuthenticationToken"
            @(Get-GALDirectoryUser).Count | Should -Be 1
            $Graph.TokenRequests | Should -Be 2
        }

        It "Should give up when Graph keeps rejecting new tokens" {
            Connect-FakeGraph
            Add-FakeFault -Match "^GET /users$" -Status 401 -Code "InvalidAuthenticationToken" -Times 5
            { Get-GALDirectoryUser } | Should -Throw "*InvalidAuthenticationToken*401*"
            $Graph.TokenRequests | Should -Be 2
        }

        It "Should keep using the renewed token" {
            Connect-FakeGraph
            Get-GALDirectoryUser | Out-Null
            $Graph.RevokedTokens = @($Graph.LastToken)
            Get-GALDirectoryUser | Out-Null
            Get-GALDirectoryUser | Out-Null
            $Graph.TokenRequests | Should -Be 2
        }

        It "Should retry a token request when the identity endpoint is busy" {
            Mock Start-Sleep -ModuleName GAL-Sync
            Add-FakeFault -Match "^GET /metadata/identity/oauth2/token$" -Status 503 -Code "ServiceUnavailable"
            Add-FakeFault -Match "^GET /metadata/identity/oauth2/token$" -Status 0
            Connect-GALSync -ManagedIdentity | Out-Null
            $Graph.TokenRequests | Should -Be 1
            Should -Invoke Start-Sleep -ModuleName GAL-Sync -Times 2 -Exactly
        }
    }
}
