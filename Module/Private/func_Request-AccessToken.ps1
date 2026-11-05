function Request-AccessToken {
    param (
        [parameter(Mandatory)][pscustomobject]$SignIn
    )
    $tokenEndpoint = "https://login.microsoftonline.com/$($SignIn.TenantId)/oauth2/v2.0/token"
    $request = switch ($SignIn.Method) {
        "ManagedIdentity" {
            $query = "resource=$([System.Uri]::EscapeDataString("https://graph.microsoft.com/"))"
            if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
                # Azure Automation sandbox
                @{
                    Method  = "Get"
                    Uri     = "$($env:IDENTITY_ENDPOINT)?$query"
                    Headers = @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER; Metadata = "True" }
                }
            }
            else {
                # Azure Instance Metadata Service, for example a Hybrid Runbook Worker on an Azure VM
                @{
                    Method  = "Get"
                    Uri     = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&$query"
                    Headers = @{ Metadata = "true" }
                }
            }
        }
        "ClientSecret" {
            @{
                Method      = "Post"
                Uri         = $tokenEndpoint
                ContentType = "application/x-www-form-urlencoded"
                Body        = @{
                    client_id     = $SignIn.ClientId
                    scope         = "https://graph.microsoft.com/.default"
                    client_secret = (New-Object System.Net.NetworkCredential "", $SignIn.Secret).Password
                    grant_type    = "client_credentials"
                }
            }
        }
        "Certificate" {
            @{
                Method      = "Post"
                Uri         = $tokenEndpoint
                ContentType = "application/x-www-form-urlencoded"
                Body        = @{
                    client_id             = $SignIn.ClientId
                    scope                 = "https://graph.microsoft.com/.default"
                    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
                    client_assertion      = New-ClientAssertion -Certificate $SignIn.Certificate -ClientId $SignIn.ClientId -Audience $tokenEndpoint
                    grant_type            = "client_credentials"
                }
            }
        }
    }

    $response = Send-HttpRequest -Request $request
    $accessToken = $response.Body.access_token
    if (-not $accessToken) {
        $reason = $response.Body.error_description
        if (-not $reason) { $reason = "HTTP $($response.StatusCode)" }
        throw "Failed to get a token using $($SignIn.Method): $reason"
    }

    $tokenPayload = $accessToken.Split(".")[1].Replace("-", "+").Replace("_", "/")
    while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
    $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
    return [pscustomobject]@{
        Value     = $accessToken
        ExpiresOn = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
        TenantId  = $claims.tid
        ClientId  = $claims.appid
        Roles     = @($claims.roles | Where-Object { $_ })
    }
}
