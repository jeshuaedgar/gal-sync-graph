function Get-RetryDelay {
    param (
        [int]$StatusCode,
        [object]$RetryAfter,
        [parameter(Mandatory)][int]$Attempt
    )
    # without a status code the network failed, which is worth retrying as well
    if (($StatusCode -and $StatusCode -notin 429, 500, 502, 503, 504) -or $Attempt -gt 5) {
        return $null
    }
    $seconds = 0
    if ([int]::TryParse([string]@($RetryAfter)[0], [ref]$seconds) -and $seconds -gt 0) {
        return [System.Math]::Min($seconds, 300)
    }
    # without Retry-After, Microsoft Graph recommends an exponential backoff
    return [int][System.Math]::Pow(2, $Attempt) + (Get-Random -Minimum 0 -Maximum 2)
}
