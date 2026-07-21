function New-GraphRequest {
    param (
        [CmdletBinding()]
        [parameter (Mandatory)][string]$Endpoint,
        [ValidateSet("Delete", "Get", "Patch", "Post", "Put")]$Method = "Get",
        [array]$Body,
        [switch]$Beta
    )
    if (-not $script:galSyncData.GraphAuthHeader) {
        throw "Not authenticated, please use 'Connect-GALSync' or re-run script"
    }
    $tokenLifeTime = New-TimeSpan -Start (Get-Date) -End $script:galSyncData.TokenExpiration
    if ($tokenLifeTime.TotalMinutes -le 0) {
        throw "Token expired! Please reconnect using 'Connect-GALSync'..."
    }
    elseif ($tokenLifeTime.TotalMinutes -le 30) {
        Write-Warning "Token will expire in $($tokenLifeTime.TotalMinutes) minutes, consider getting a new one by using 'Connect-GALSync'"
    }

    if ($Beta) {
        $baseURL = "https://graph.microsoft.com/{0}/" -f "beta"
    }
    else {
        $baseURL = "https://graph.microsoft.com/{0}/" -f "v1.0"
    }
    if ($Endpoint.StartsWith("/")) {
        $Endpoint = $Endpoint.Substring(1)
    }
    #create the splat first
    $reqSplat = @{
        Method  = $Method
        URI     = $baseUrl + $Endpoint
        Headers = $script:galSyncData.GraphAuthHeader
    }
    if ($Body) {
        $reqSplat.Body = $Body | ConvertTo-Json -Depth 10
    }

    $reqSplat.GetEnumerator() | ForEach-Object {
        if ($_.value -is [System.Collections.Hashtable]) {
            $_.Value.GetEnumerator() | ForEach-Object {
                Write-VerboseEvent "Parameter : $($_.Key)"
                Write-VerboseEvent "Value     : $($_.Value)"
            }
        }
        Write-VerboseEvent "Parameter : $($_.Key)"
        Write-VerboseEvent "Value     : $($_.Value)"
    }
    try {
        function Check-OutputData ($data) {
            if ($data.PsObject.Members.Name -contains "value") { $output = $data.value }
            else { $output = $data }
            return $output
        }
        $output = @()
        $request = Invoke-RestMethod -ContentType "application/json; charset=UTF-8" @reqSplat
        $output += (Check-OutputData $request)
        if ($request.'@odata.nextLink') {
            Write-VerboseEvent "Found @odata.nextLink"
            Write-VerboseEvent $request.'@odata.nextLink'
            do {
                $request = Invoke-RestMethod -ContentType "application/json; charset=UTF-8" $request.'@odata.nextLink' -Headers $script:galSyncData.GraphAuthHeader
                $output += (Check-OutputData $request)
            } until (
                (-not $request.'@odata.nextLink')
            )
        }
        return $output 
    }
    catch {
        throw (Format-ErrorCode $_).ErrorMessage
    }
}