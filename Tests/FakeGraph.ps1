$fakeHttpTemplate = @'
function Invoke-HttpRequest {
    param ([parameter(Mandatory)][hashtable]$Request)

    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    [System.Threading.Monitor]::Enter($graph)
    try {
        $uri = [System.Uri]$Request.Uri
        $method = ([string]$Request.Method).ToUpper()
        $graph.Calls.Add("$method $($Request.Uri)")
        $graph.Requests.Add(@{ Method = $method; Uri = $Request.Uri; Headers = $Request.Headers; Body = $Request.Body })

        $fault = Get-FakeFault -Graph $graph -Call "$method $($uri.AbsolutePath -replace '^/v1\.0', '')"
        if ($fault -and $fault.Status -eq 0) { throw [System.Net.Http.HttpRequestException]::new("Injected network failure") }
        if ($uri.Host -ne "graph.microsoft.com") {
            if ($fault) {
                return [pscustomobject]@{ StatusCode = $fault.Status; Headers = @{ "Retry-After" = @($fault.Headers["Retry-After"]) }; Body = [pscustomobject]@{ error = $fault.Body.error.code } }
            }
            if ($uri.Host -eq "login.microsoftonline.com") { $graph.LastLogin = $Request.Body }
            $graph.TokenRequests++
            if ($graph.LoginError) {
                return [pscustomobject]@{ StatusCode = 401; Headers = @{}; Body = [pscustomobject]@{ error = "invalid_client"; error_description = $graph.LoginError } }
            }
            $claims = @{} + $graph.TokenClaims
            $claims.exp = [System.DateTimeOffset]::UtcNow.AddSeconds($graph.TokenLifetime).ToUnixTimeSeconds()
            $encode = { param($text) [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text)).TrimEnd("=").Replace("+", "-").Replace("/", "_") }
            $token = "{0}.{1}.{2}" -f (& $encode '{"alg":"none"}'), (& $encode ($claims | ConvertTo-Json -Compress)), $graph.TokenRequests
            $graph.Tokens[$token] = [System.DateTimeOffset]::FromUnixTimeSeconds($claims.exp)
            $graph.LastToken = $token
            return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = [pscustomobject]@{ access_token = $token } }
        }

        $token = ([string]$Request.Headers.Authorization) -replace "^Bearer ", ""
        if ($fault) {
            $result = $fault
        }
        elseif (-not $graph.Tokens.ContainsKey($token) -or $graph.Tokens[$token] -lt [System.DateTimeOffset]::UtcNow -or $graph.RevokedTokens -contains $token) {
            $result = New-FakeError 401 "InvalidAuthenticationToken" "Access token is missing, unknown or expired."
        }
        else {
            $body = if ($Request.Body) { [System.Text.Encoding]::UTF8.GetString($Request.Body) | ConvertFrom-Json } else { $null }
            $result = if ($uri.AbsolutePath -eq '/v1.0/$batch') {
                Invoke-FakeBatch -Graph $graph -Body $body
            }
            else {
                Invoke-FakeGraphRoute -Graph $graph -Method $method -Uri $uri -Body $body -Headers $Request.Headers
            }
        }
        $json = if ($null -ne $result.Body) { $result.Body | ConvertTo-Json -Depth 20 | ConvertFrom-Json } else { $null }
        $headers = @{}
        foreach ($key in $result.Headers.Keys) { $headers[$key] = @([string]$result.Headers[$key]) }
        return [pscustomobject]@{ StatusCode = $result.Status; Headers = $headers; Body = $json }
    }
    finally {
        [System.Threading.Monitor]::Exit($graph)
    }
}

function New-FakeError ($Status, $Code, $Message) {
    return @{ Status = $Status; Headers = @{}; Body = @{ error = @{ code = $Code; message = $Message } } }
}

function Get-FakeFault ($Graph, $Call) {
    foreach ($fault in $Graph.Faults) {
        if ($fault.Remaining -gt 0 -and $Call -match $fault.Match) {
            $fault.Remaining--
            $result = New-FakeError $fault.Status $fault.Code "Injected fault"
            if ($fault.RetryAfter) { $result.Headers["Retry-After"] = [string]$fault.RetryAfter }
            return $result
        }
    }
}

function Invoke-FakeBatch ($Graph, $Body) {
    $Graph.BatchCalls++
    $requests = @($Body.requests)
    if ($requests.Count -gt 20) {
        return New-FakeError 400 "BadRequest" "A batch can contain at most 20 requests."
    }
    $responses = @(foreach ($item in $requests) {
        $itemUri = [System.Uri]"https://graph.microsoft.com/v1.0$($item.url)"
        $Graph.Calls.Add("BATCH $($item.method) $($itemUri.AbsolutePath -replace '^/v1\.0', '')")
        $result = Get-FakeFault -Graph $Graph -Call "$($item.method) $($itemUri.AbsolutePath -replace '^/v1\.0', '')"
        if (-not $result) {
            $result = if ($null -ne $item.body -and $item.headers.'Content-Type' -ne "application/json") {
                New-FakeError 400 "BadRequest" "Content-Type header is required for requests with a body."
            }
            else {
                Invoke-FakeGraphRoute -Graph $Graph -Method $item.method -Uri $itemUri -Body $item.body -Headers @{}
            }
        }
        [ordered]@{ id = $item.id; status = $result.Status; headers = $result.Headers; body = $result.Body }
    })
    [array]::Reverse($responses)
    return @{ Status = 200; Headers = @{}; Body = @{ responses = @($responses) } }
}

function Invoke-FakeGraphRoute {
    param ($Graph, $Method, [System.Uri]$Uri, $Body, $Headers)

    $segments = @($Uri.AbsolutePath.Trim("/").Split("/") | Select-Object -Skip 1 | ForEach-Object { [System.Uri]::UnescapeDataString($_) })
    $query = @{}
    foreach ($pair in $Uri.Query.TrimStart("?").Split("&") | Where-Object { $_ }) {
        $key, $value = $pair.Split("=", 2)
        $query[[System.Uri]::UnescapeDataString($key)] = [System.Uri]::UnescapeDataString($value)
    }
    $ok = { param($status, $value) @{ Status = $status; Headers = @{}; Body = $value } }
    $collection = {
        param ($items, $extra)
        $select = if ($query['$select']) { @("id") + $query['$select'].Split(",") }
        $expand = if ($query['$expand'] -match "id eq '(.+)'") { $Matches[1] }
        $projected = foreach ($item in $items) {
            $copy = [ordered]@{}
            foreach ($key in $item.Keys) {
                if ($key -eq "properties" -or ($select -and $key -notin $select)) { continue }
                $copy[$key] = $item[$key]
            }
            if ($expand) {
                $copy.singleValueExtendedProperties = @($item.properties | Where-Object { $_.id -eq $expand })
            }
            foreach ($key in $extra.Keys) { $copy[$key] = & $extra[$key] $item }
            $copy
        }
        $skip = if ($query['$skiptoken']) { [int]$query['$skiptoken'] } else { 0 }
        $size = if ($Graph.PageSize) { $Graph.PageSize } else { 100000 }
        $page = @($projected | Select-Object -Skip $skip -First $size)
        $value = @{ value = $page }
        if ($skip + $size -lt @($projected).Count) {
            $nextQuery = (@($Uri.Query.TrimStart("?").Split("&") | Where-Object { $_ -and $_ -notlike '$skiptoken=*' }) + "`$skiptoken=$($skip + $size)") -join "&"
            $value["@odata.nextLink"] = "https://graph.microsoft.com$($Uri.AbsolutePath)?$nextQuery"
        }
        return & $ok 200 $value
    }
    $advancedQuery = { $Headers.ConsistencyLevel -eq "eventual" -and $query['$count'] -eq "true" }

    if ($Method -eq "GET" -and $segments.Count -eq 1 -and $segments[0] -eq "users") {
        $Graph.UserQueries.Add(@{ Query = $query; Headers = $Headers })
        if ($query['$filter'] -and -not (& $advancedQuery)) { return New-FakeError 400 "Request_UnsupportedQuery" "Advanced query needs ConsistencyLevel and `$count." }
        return & $collection $Graph.Users
    }
    if ($Method -eq "GET" -and $segments.Count -eq 1 -and $segments[0] -eq "contacts") {
        return & $collection $Graph.OrgContacts
    }
    if ($Method -eq "GET" -and $segments.Count -eq 1 -and $segments[0] -eq "groups") {
        if ($query['$filter'] -notmatch "^displayName eq '((?:[^']|'')*)'$") { return New-FakeError 400 "BadRequest" "Invalid filter clause." }
        $name = $Matches[1].Replace("''", "'")
        $found = foreach ($id in $Graph.Groups.Keys) { if ($Graph.Groups[$id].DisplayName -eq $name) { @{ id = $id; displayName = $name } } }
        return & $collection @($found)
    }
    if ($Method -eq "GET" -and $segments[0] -eq "groups" -and $segments[2] -eq "transitiveMembers") {
        if (-not $Graph.Groups.ContainsKey($segments[1])) { return New-FakeError 404 "Request_ResourceNotFound" "Group not found." }
        if (($segments.Count -gt 3 -or $query['$select']) -and -not (& $advancedQuery)) { return New-FakeError 400 "Request_UnsupportedQuery" "Advanced query needs ConsistencyLevel and `$count." }
        $seen = @{}
        $queue = New-Object System.Collections.Generic.Queue[string]
        $queue.Enqueue($segments[1])
        while ($queue.Count) {
            foreach ($member in $Graph.Groups[$queue.Dequeue()].Members) {
                if ($seen.ContainsKey($member)) { continue }
                $seen[$member] = $true
                if ($Graph.Groups.ContainsKey($member)) { $queue.Enqueue($member) }
            }
        }
        $users = @($Graph.Users | Where-Object { $seen.ContainsKey($_.id) })
        if ($segments[3] -eq "microsoft.graph.user") { return & $collection $users }
        $contacts = @($Graph.OrgContacts | Where-Object { $seen.ContainsKey($_.id) })
        return & $collection ($users + $contacts) @{ "@odata.type" = { param($item) if ($item.Contains("userPrincipalName")) { "#microsoft.graph.user" } else { "#microsoft.graph.orgContact" } } }
    }
    if ($segments[0] -ne "users" -or $segments[2] -ne "contactFolders") {
        return New-FakeError 400 "BadRequest" "Unexpected $Method $($Uri.AbsolutePath)"
    }

    $mailbox = $segments[1].ToLower()
    if ($Graph.Unlicensed -contains $mailbox) { return New-FakeError 404 "MailboxNotEnabledForRESTAPI" "REST API is not yet supported for this mailbox." }
    $user = $Graph.Users | Where-Object { $_.id -eq $segments[1] -or $_.userPrincipalName -eq $mailbox } | Select-Object -First 1
    if (-not $user) { return New-FakeError 404 "ErrorInvalidUser" "The requested user '$($segments[1])' is invalid." }
    $mailbox = $user.userPrincipalName.ToLower()
    if ($Graph.AccessDenied -contains $mailbox) { return New-FakeError 403 "ErrorAccessDenied" "Access is denied." }
    if (-not $Graph.Mailboxes.ContainsKey($mailbox)) { $Graph.Mailboxes[$mailbox] = [ordered]@{} }
    $folders = $Graph.Mailboxes[$mailbox]
    $folder = if ($segments.Count -gt 3) { $folders[$segments[3]] }
    if ($segments.Count -gt 3 -and -not $folder) { return New-FakeError 404 "ErrorItemNotFound" "The specified object was not found in the store." }
    $contact = if ($segments.Count -gt 5) { $folder.contacts[$segments[5]] }
    if ($segments.Count -gt 5 -and -not $contact) { return New-FakeError 404 "ErrorItemNotFound" "The specified object was not found in the store." }

    $setProperties = {
        param ($target, $allowed)
        foreach ($property in $Body.PSObject.Properties) {
            if ($property.Name -eq "singleValueExtendedProperties") {
                foreach ($extended in $property.Value) {
                    $target.properties = @($target.properties | Where-Object { $_.id -ne $extended.id }) + @(@{ id = $extended.id; value = $extended.value })
                }
            }
            elseif ($property.Name -notin $allowed) {
                return New-FakeError 400 "ErrorInvalidProperty" "Could not find a property named '$($property.Name)'."
            }
            else {
                $target[$property.Name] = ConvertTo-Json -InputObject $property.Value -Depth 10 | ConvertFrom-Json -AsHashtable -NoEnumerate
            }
        }
    }

    switch ("$Method $($segments.Count)") {
        "GET 3" { return & $collection @($folders.Values) }
        "POST 3" {
            $new = [ordered]@{ id = "AAMk/f+$([guid]::NewGuid())="; displayName = $null; parentFolderId = "contacts"; properties = @(); contacts = [ordered]@{} }
            $invalid = & $setProperties $new @("displayName")
            if ($invalid) { return $invalid }
            $folders[$new.id] = $new
            return & $ok 201 @{ id = $new.id; displayName = $new.displayName; parentFolderId = "contacts" }
        }
        "PATCH 4" {
            $invalid = & $setProperties $folder @("displayName")
            if ($invalid) { return $invalid }
            return & $ok 200 @{ id = $folder.id }
        }
        "DELETE 4" {
            $folders.Remove($folder.id)
            return & $ok 204 $null
        }
        "GET 5" { return & $collection @($folder.contacts.Values | Where-Object { $_ }) }
        "POST 5" {
            $new = [ordered]@{ id = "AAMk/c+$([guid]::NewGuid())="; properties = @() }
            $invalid = & $setProperties $new $Graph.ContactProperties
            if ($invalid) { return $invalid }
            $folder.contacts[$new.id] = $new
            return & $ok 201 @{ id = $new.id }
        }
        "PATCH 6" {
            $invalid = & $setProperties $contact $Graph.ContactProperties
            if ($invalid) { return $invalid }
            return & $ok 200 @{ id = $contact.id }
        }
        "DELETE 6" {
            $folder.contacts.Remove($contact.id)
            return & $ok 204 $null
        }
    }
    return New-FakeError 400 "BadRequest" "Unexpected $Method $($Uri.AbsolutePath)"
}
'@

$script:SourceTag = "String {929243f2-3b50-4543-a72f-be8081616276} Name GALSyncSourceId"
$script:FolderMarker = "String {929243f2-3b50-4543-a72f-be8081616276} Name GALSyncFolder"

function New-FakeGraph {
    $copy = Join-Path $TestDrive "repository"
    Remove-Item $copy -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $copy -ItemType Directory | Out-Null
    $repository = Join-Path $PSScriptRoot ".."
    Copy-Item -Path (Join-Path $repository "Module"), (Join-Path $repository "runbook"), (Join-Path $repository "Sync-Contacts.ps1") -Destination $copy -Recurse
    Set-Content -Path (Join-Path $copy "Module/Private/func_Invoke-HttpRequest.ps1") -Value $fakeHttpTemplate
    New-Item -Path (Join-Path $copy "modules") -ItemType Directory | Out-Null
    Copy-Item -Path (Join-Path $copy "Module") -Destination (Join-Path $copy "modules/GAL-Sync") -Recurse

    Get-Module GAL-Sync | Remove-Module -Force
    Import-Module (Join-Path $copy "Module/GAL-Sync.psd1") -Force -Global

    $graph = [hashtable]::Synchronized(@{ Root = $copy })
    # every property of the Outlook contact resource in Microsoft Graph v1.0
    $graph.ContactProperties = @("assistantName", "birthday", "businessAddress", "businessHomePage", "businessPhones", "categories", "children",
        "companyName", "department", "displayName", "emailAddresses", "fileAs", "generation", "givenName", "homeAddress", "homePhones", "imAddresses",
        "initials", "jobTitle", "manager", "middleName", "mobilePhone", "nickName", "officeLocation", "otherAddress", "personalNotes", "profession",
        "spouseName", "surname", "title", "yomiCompanyName", "yomiGivenName", "yomiSurname")
    [AppDomain]::CurrentDomain.SetData("GALSyncFakeGraph", $graph)
    Reset-FakeGraph
    return $graph
}

function Reset-FakeGraph {
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    $graph.Calls = New-Object System.Collections.Generic.List[string]
    $graph.Requests = New-Object System.Collections.Generic.List[object]
    $graph.UserQueries = New-Object System.Collections.Generic.List[object]
    $graph.Users = New-Object System.Collections.Generic.List[object]
    $graph.OrgContacts = New-Object System.Collections.Generic.List[object]
    $graph.Faults = New-Object System.Collections.Generic.List[object]
    $graph.Groups = @{}
    $graph.Mailboxes = @{}
    $graph.Tokens = @{}
    $graph.RevokedTokens = @()
    $graph.Unlicensed = @()
    $graph.AccessDenied = @()
    $graph.PageSize = 0
    $graph.BatchCalls = 0
    $graph.TokenRequests = 0
    $graph.TokenLifetime = 3600
    $graph.LoginError = $null
    $graph.LastLogin = $null
    $graph.LastToken = $null
    $graph.TokenClaims = @{ tid = "tenant-id"; appid = "app-id"; roles = @("User.Read.All", "GroupMember.Read.All", "Contacts.ReadWrite", "OrgContact.Read.All") }
}

function Remove-FakeGraph {
    [AppDomain]::CurrentDomain.SetData("GALSyncFakeGraph", $null)
    Get-Module GAL-Sync | Remove-Module -Force
}

function Connect-FakeGraph {
    $credential = New-Object System.Management.Automation.PSCredential ("app-id", (ConvertTo-SecureString "secret" -AsPlainText -Force))
    Connect-GALSync -TenantId "contoso.onmicrosoft.com" -Credential $credential | Out-Null
}

function Add-FakeUser {
    param (
        [parameter(Mandatory)][string]$Id,
        [parameter(Mandatory)][string]$Name,
        [string]$Mail = "$($Name.Split(" ")[0].ToLower())@contoso.com",
        [string]$Upn = $Mail,
        [string]$Mobile = "+31 6 $Id",
        [string[]]$Business = @(),
        [hashtable]$Properties = @{},
        [switch]$Disabled,
        [switch]$Guest
    )
    $given, $surname = $Name.Split(" ", 2)
    $user = [ordered]@{
        id                = $Id
        displayName       = $Name
        givenName         = $given
        surname           = $surname
        mail              = $Mail
        userPrincipalName = if ($Upn) { $Upn } else { "$Id@contoso.com" }
        mobilePhone       = $Mobile
        businessPhones    = $Business
        jobTitle          = $null
        department        = $null
        companyName       = $null
        officeLocation    = $null
        streetAddress     = $null
        city              = $null
        state             = $null
        postalCode        = $null
        country           = $null
        accountEnabled    = -not $Disabled
        userType          = if ($Guest) { "Guest" } else { "Member" }
        showInAddressList = $null
    }
    foreach ($key in $Properties.Keys) { $user[$key] = $Properties[$key] }
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    $graph.Users.Add($user)
    return $user
}

function Add-FakeOrgContact {
    param ([parameter(Mandatory)][string]$Id, [parameter(Mandatory)][string]$Name, [string]$Mail, [hashtable[]]$Phones = @(), [hashtable[]]$Addresses = @())
    $given, $surname = $Name.Split(" ", 2)
    $contact = [ordered]@{ id = $Id; displayName = $Name; givenName = $given; surname = $surname; mail = $Mail; jobTitle = $null; department = $null; companyName = $null; phones = $Phones; addresses = $Addresses }
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    $graph.OrgContacts.Add($contact)
    return $contact
}

function Add-FakeGroup {
    param ([parameter(Mandatory)][string]$Id, [parameter(Mandatory)][string]$Name, [string[]]$Members = @())
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    $graph.Groups[$Id] = @{ DisplayName = $Name; Members = $Members }
}

function Add-FakeFolder {
    param (
        [parameter(Mandatory)][string]$Mailbox,
        [parameter(Mandatory)][string]$Name,
        [string]$Id = "AAMk/f+$([guid]::NewGuid())=",
        [switch]$Managed,
        [hashtable[]]$Contacts = @()
    )
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    if (-not $graph.Mailboxes.ContainsKey($Mailbox)) { $graph.Mailboxes[$Mailbox] = [ordered]@{} }
    $folder = [ordered]@{
        id             = $Id
        displayName    = $Name
        parentFolderId = "contacts"
        properties     = @(if ($Managed) { @{ id = $FolderMarker; value = "true" } })
        contacts       = [ordered]@{}
    }
    foreach ($contact in $Contacts) { $folder.contacts[$contact.id] = $contact }
    $graph.Mailboxes[$Mailbox][$Id] = $folder
    return $folder
}

function New-FakeContact {
    param ([parameter(Mandatory)][string]$Id, [string]$SourceId, [parameter(Mandatory)][System.Collections.IDictionary]$From, [hashtable]$Override = @{})
    $contact = [ordered]@{
        id              = $Id
        properties      = @(if ($SourceId) { @{ id = $SourceTag; value = $SourceId } })
        displayName     = $From.displayName
        givenName       = $From.givenName
        surname         = $From.surname
        jobTitle        = $From.jobTitle
        department      = $From.department
        companyName     = $From.companyName
        officeLocation  = $From.officeLocation
        mobilePhone     = $From.mobilePhone
        businessPhones  = @($From.businessPhones)
        businessAddress = @{ street = $From.streetAddress; city = $From.city; state = $From.state; postalCode = $From.postalCode; countryOrRegion = $From.country }
        emailAddresses  = @(if ($From.mail) { @{ name = $From.displayName; address = $From.mail } })
    }
    foreach ($key in $Override.Keys) { $contact[$key] = $Override[$key] }
    return $contact
}

function Get-FakeFolder {
    param ([parameter(Mandatory)][string]$Mailbox, [string]$Name = "GAL")
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    Write-Output -NoEnumerate @($graph.Mailboxes[$Mailbox].Values | Where-Object { $_.displayName -eq $Name })
}

function Test-FakeManaged ($Folder) {
    return [bool]($Folder.properties | Where-Object { $_.id -eq $FolderMarker -and $_.value -eq "true" })
}

function Get-FakeSourceId ($Contact) {
    return ($Contact.properties | Where-Object { $_.id -eq $SourceTag }).value
}

function Get-FakeContact {
    param ([parameter(Mandatory)][string]$Mailbox, [string]$Name = "GAL", [string]$SourceId)
    $contacts = @((Get-FakeFolder -Mailbox $Mailbox -Name $Name | Select-Object -First 1).contacts.Values)
    if ($SourceId) {
        return $contacts | Where-Object { (Get-FakeSourceId $_) -eq $SourceId }
    }
    return $contacts
}

function Add-FakeFault {
    param ([parameter(Mandatory)][string]$Match, [int]$Status = 429, [string]$Code = "TooManyRequests", [int]$Times = 1, [int]$RetryAfter)
    $graph = [AppDomain]::CurrentDomain.GetData("GALSyncFakeGraph")
    $graph.Faults.Add(@{ Match = $Match; Status = $Status; Code = $Code; Remaining = $Times; RetryAfter = $RetryAfter })
}
