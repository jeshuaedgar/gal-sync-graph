function New-GraphRequest {
    param (
        [parameter(Mandatory)][string]$Endpoint,
        [ValidateSet("Get", "Post", "Patch", "Delete")][string]$Method = "Get",
        [object]$Body,
        [hashtable]$Headers = @{},
        [switch]$All
    )
    $uri = "https://graph.microsoft.com/v1.0/$($Endpoint.TrimStart("/"))"
    $reqSplat = @{
        Method = $Method
    }
    if ($null -ne $Body) {
        $reqSplat.Body = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 20 -Compress))
        $reqSplat.ContentType = "application/json; charset=utf-8"
    }

    $output = New-Object System.Collections.Generic.List[object]
    while ($uri) {
        $reqSplat.Uri = $uri
        $reqSplat.Headers = @{ Authorization = "Bearer $((Get-AccessToken).Value)" } + $Headers
        $response = Send-HttpRequest -Request $reqSplat
        if ($response.StatusCode -eq 401) {
            $reqSplat.Headers = @{ Authorization = "Bearer $((Get-AccessToken -Renew).Value)" } + $Headers
            $response = Send-HttpRequest -Request $reqSplat
        }
        if ($response.StatusCode -ge 400) {
            $exception = New-Object System.Exception "Graph request $Method $(([System.Uri]$uri).AbsolutePath) failed: $(Format-ErrorCode -StatusCode $response.StatusCode -ErrorBody $response.Body)"
            $exception.Data["GraphErrorCode"] = $response.Body.error.code
            throw $exception
        }
        if (-not $All) {
            return $response.Body
        }
        $output.AddRange(@($response.Body.value))
        $uri = $response.Body."@odata.nextLink"
    }
    return $output
}
