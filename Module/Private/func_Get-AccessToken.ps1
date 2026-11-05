function Get-AccessToken {
    param (
        [switch]$Renew
    )
    if (-not $script:galSyncData) {
        throw "Not connected, please use Connect-GALSync first"
    }
    $token = $script:galSyncData.Token
    if ($Renew -or $token.ExpiresOn -le [System.DateTimeOffset]::UtcNow.AddMinutes(5)) {
        Write-VerboseEvent "Getting a new access token"
        $token = Request-AccessToken -SignIn $script:galSyncData.SignIn
        $script:galSyncData.Token = $token
    }
    return $token
}
