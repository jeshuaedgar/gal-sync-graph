function New-GraphBatchRequest {
    param (
        [parameter(Mandatory)][AllowEmptyCollection()][object[]]$Requests
    )
    $responses = New-Object object[] $Requests.Count
    $pending = @(for ($index = 0; $index -lt $Requests.Count; $index++) { $index })
    $attempt = 0
    while ($pending.Count) {
        $attempt++
        $retry = New-Object System.Collections.Generic.List[int]
        $delay = 0
        for ($offset = 0; $offset -lt $pending.Count; $offset += 20) {
            $batchRequests = foreach ($index in $pending[$offset..([System.Math]::Min($offset + 19, $pending.Count - 1))]) {
                $request = $Requests[$index]
                $entry = [ordered]@{
                    id     = [string]$index
                    method = $request.method
                    url    = $request.url
                }
                if ($null -ne $request.body) {
                    $entry.body = $request.body
                    $entry.headers = @{ "Content-Type" = "application/json" }
                }
                $entry
            }
            $batch = New-GraphRequest -Method Post -Endpoint "/`$batch" -Body @{ requests = @($batchRequests) }
            foreach ($response in $batch.responses) {
                $index = [int]$response.id
                $itemDelay = Get-RetryDelay -StatusCode $response.status -RetryAfter $response.headers."Retry-After" -Attempt $attempt
                if ($null -eq $itemDelay) {
                    $responses[$index] = $response
                }
                else {
                    $retry.Add($index)
                    $delay = [System.Math]::Max($delay, $itemDelay)
                }
            }
        }
        $pending = $retry.ToArray()
        if ($pending.Count) {
            Write-VerboseEvent "$($pending.Count) batched request(s) were throttled, retrying in $delay seconds"
            Start-Sleep -Seconds $delay
        }
    }
    return $responses
}
