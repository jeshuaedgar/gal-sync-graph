function Invoke-HttpRequest {
    param (
        [parameter(Mandatory)][hashtable]$Request
    )
    $body = Invoke-RestMethod @Request -TimeoutSec 100 -SkipHttpErrorCheck -StatusCodeVariable statusCode -ResponseHeadersVariable responseHeaders
    return [pscustomobject]@{
        StatusCode = [int]$statusCode
        Headers    = $responseHeaders
        Body       = $body
    }
}
