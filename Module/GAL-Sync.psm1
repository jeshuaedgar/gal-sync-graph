#load variables for module
$script:galSyncData = $null

$propertySet = "{929243f2-3b50-4543-a72f-be8081616276}"
$script:sourceIdProperty = "String $propertySet Name GALSyncSourceId"
$script:folderMarker = @{
    id    = "String $propertySet Name GALSyncFolder"
    value = "true"
}

$script:contactFields = [ordered]@{
    displayName     = "Text"
    givenName       = "Text"
    surname         = "Text"
    jobTitle        = "Text"
    department      = "Text"
    companyName     = "Text"
    officeLocation  = "Text"
    mobilePhone     = "Text"
    businessPhones  = "List"
    businessAddress = "Address"
    emailAddresses  = "Email"
}

#load functions
foreach ($scope in "Private", "Public") {
    Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath $scope) -Recurse -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
        if ($scope -eq "Public") {
            Export-ModuleMember -Function ($_.BaseName -Split "_")[1]
        }
    }
}
