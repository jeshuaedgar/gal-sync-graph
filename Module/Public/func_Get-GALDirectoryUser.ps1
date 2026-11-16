function Get-GALDirectoryUser {
    [CmdletBinding()]
    param (
        [string]$SourceGroup,
        [string[]]$ExcludeUser,
        [string]$UserFilter,
        [switch]$ExcludeHiddenFromAddressList,
        [switch]$IncludeOrgContacts,
        [switch]$BusinessPhoneAsMobile,
        [switch]$IncludeUsersWithoutPhone,
        [switch]$IncludeUsersWithoutEmail,
        [switch]$IncludeDisabledUsers,
        [switch]$IncludeGuests
    )
    $userEndpoint = "/users?`$select=id,displayName,givenName,surname,jobTitle,department,companyName,officeLocation,mail,userPrincipalName,businessPhones,mobilePhone,streetAddress,city,state,postalCode,country,accountEnabled,userType&`$top=999"
    $userHeaders = @{}
    if ($ExcludeHiddenFromAddressList) {
        # the docs advise against showInAddressList because it can be out of sync with Exchange, so only ask for it when requested
        $userEndpoint = $userEndpoint.Replace(",userType&", ",userType,showInAddressList&")
        Write-VerboseEvent "Using showInAddressList to hide users, this property can be out of sync with Exchange"
    }
    if ($UserFilter) {
        $userEndpoint += "&`$count=true&`$filter=$([System.Uri]::EscapeDataString($UserFilter))"
        $userHeaders.ConsistencyLevel = "eventual"
    }

    Write-VerboseEvent "Getting directory users"
    $entries = @(
        New-GraphRequest -Endpoint $userEndpoint -Headers $userHeaders -All | Where-Object {
            ($IncludeDisabledUsers -or $_.accountEnabled) -and
            ($IncludeGuests -or $_.userType -ne "Guest") -and
            -not ($ExcludeHiddenFromAddressList -and $_.showInAddressList -eq $false)
        } | ForEach-Object {
            [ordered]@{
                id                = $_.id
                userPrincipalName = $_.userPrincipalName
                mail              = $_.mail
                displayName       = $_.displayName
                givenName         = $_.givenName
                surname           = $_.surname
                jobTitle          = $_.jobTitle
                department        = $_.department
                companyName       = $_.companyName
                officeLocation    = $_.officeLocation
                mobilePhone       = $_.mobilePhone
                businessPhones    = @($_.businessPhones | Where-Object { $_ })
                businessAddress   = [ordered]@{
                    street          = $_.streetAddress
                    city            = $_.city
                    state           = $_.state
                    postalCode      = $_.postalCode
                    countryOrRegion = $_.country
                }
            }
        }

        if ($IncludeOrgContacts) {
            Write-VerboseEvent "Getting mail contacts"
            New-GraphRequest -Endpoint "/contacts?`$select=id,displayName,givenName,surname,jobTitle,department,companyName,mail,phones,addresses&`$top=999" -All | ForEach-Object {
                $phones = $_.phones
                $address = @($_.addresses)[0]
                [ordered]@{
                    id                = $_.id
                    userPrincipalName = $null
                    mail              = $_.mail
                    displayName       = $_.displayName
                    givenName         = $_.givenName
                    surname           = $_.surname
                    jobTitle          = $_.jobTitle
                    department        = $_.department
                    companyName       = $_.companyName
                    officeLocation    = $address.officeLocation
                    mobilePhone       = ($phones | Where-Object { $_.type -eq "mobile" -and $_.number } | Select-Object -First 1).number
                    businessPhones    = @($phones | Where-Object { $_.type -eq "business" -and $_.number } | ForEach-Object { $_.number })
                    businessAddress   = [ordered]@{
                        street          = $address.street
                        city            = $address.city
                        state           = $address.state
                        postalCode      = $address.postalCode
                        countryOrRegion = $address.countryOrRegion
                    }
                }
            }
        }
    )

    $groupMembers = @{}
    if ($SourceGroup) {
        $groupId = Get-GroupId -Group $SourceGroup
        # a plain request reads the directory directly, advanced queries ($count, $select) use an eventually consistent index
        New-GraphRequest -Endpoint "/groups/$($groupId)/transitiveMembers" -All | ForEach-Object {
            $groupMembers[$_.id] = $true
        }
    }

    $directoryUsers = foreach ($entry in $entries) {
        if (-not $IncludeUsersWithoutEmail -and -not $entry.mail) { continue }
        if (-not $IncludeUsersWithoutPhone -and -not $entry.mobilePhone -and -not $entry.businessPhones) { continue }
        if (Test-ExcludedUser -User $entry -ExcludeUser $ExcludeUser) { continue }
        if ($SourceGroup -and -not $groupMembers.ContainsKey($entry.id)) { continue }

        if (-not $entry.displayName) {
            $entry.displayName = $entry.mail
        }
        if ($BusinessPhoneAsMobile -and -not $entry.mobilePhone -and $entry.businessPhones) {
            $entry.mobilePhone = $entry.businessPhones[0]
            $entry.businessPhones = @($entry.businessPhones | Select-Object -Skip 1)
        }
        $entry.emailAddresses = @(
            if ($entry.mail) {
                [ordered]@{
                    name    = $entry.displayName
                    address = $entry.mail
                }
            }
        )
        [pscustomobject]$entry
    }
    Write-VerboseEvent "$(@($directoryUsers).Count) of $($entries.Count) directory entries will be synced"
    return $directoryUsers
}
