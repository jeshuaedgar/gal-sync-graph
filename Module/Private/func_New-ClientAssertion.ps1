function New-ClientAssertion {
    param (
        [parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [parameter(Mandatory)][string]$ClientId,
        [parameter(Mandatory)][string]$Audience
    )
    function ConvertTo-Base64Url ($Bytes) {
        return [System.Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
    }
    function ConvertTo-JwtPart ($Object) {
        return ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes(($Object | ConvertTo-Json -Compress)))
    }

    $now = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = [ordered]@{
        alg        = "PS256"
        typ        = "JWT"
        "x5t#S256" = ConvertTo-Base64Url $Certificate.GetCertHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    }
    $payload = [ordered]@{
        aud = $Audience
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        iat = $now
        nbf = $now
        exp = $now + 600
    }
    $unsigned = (ConvertTo-JwtPart $header), (ConvertTo-JwtPart $payload) -join "."

    $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    $signature = $privateKey.SignData([System.Text.Encoding]::UTF8.GetBytes($unsigned), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pss)
    return $unsigned, (ConvertTo-Base64Url $signature) -join "."
}
