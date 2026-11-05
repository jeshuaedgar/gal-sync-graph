function Send-HttpRequest {
    param (
        [parameter(Mandatory)][hashtable]$Request
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $response = Invoke-HttpRequest -Request $Request
            $delay = Get-RetryDelay -StatusCode $response.StatusCode -RetryAfter $response.Headers["Retry-After"] -Attempt $attempt
            $reason = "HTTP $($response.StatusCode)"
        }
        catch [System.Net.Http.HttpRequestException], [System.OperationCanceledException] {
            $delay = Get-RetryDelay -Attempt $attempt
            if ($null -eq $delay) { throw }
            $reason = $_.Exception.Message
        }
        if ($null -eq $delay) {
            return $response
        }
        Write-VerboseEvent "$reason for $($Request.Method) $(([System.Uri]$Request.Uri).AbsolutePath), retrying in $delay seconds"
        Start-Sleep -Seconds $delay
    }
}
