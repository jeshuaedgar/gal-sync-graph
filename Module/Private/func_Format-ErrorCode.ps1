function Format-ErrorCode {
    param (
        [parameter(Mandatory)][int]$StatusCode,
        [object]$ErrorBody
    )
    if ($ErrorBody.error.code) {
        return "Error $($ErrorBody.error.code)! $($ErrorBody.error.message) (HTTP $StatusCode)"
    }
    return "HTTP $StatusCode"
}
