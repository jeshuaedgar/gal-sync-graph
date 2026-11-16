function Compare-Contact {
    param (
        [parameter(Mandatory)][object]$Desired,
        [parameter(Mandatory)][object]$Current
    )
    function ConvertTo-Comparable ($Value, $Kind, $AddressFields) {
        switch ($Kind) {
            "Text" { return ([string]$Value).Trim() }
            "List" { return ($Value | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join "|" }
            "Address" { return ($AddressFields | ForEach-Object { ([string]$Value.$_).Trim() }) -join "|" }
            "Email" { return ($Value | ForEach-Object { ([string]$_.address).Trim().ToLower() } | Where-Object { $_ } | Sort-Object) -join "|" }
            default { throw "Unknown contact field kind $Kind" }
        }
    }
    $changes = foreach ($field in $script:contactFields.Keys) {
        $kind = $script:contactFields[$field]
        $addressFields = if ($kind -eq "Address") { $Desired.$field.Keys }
        if ((ConvertTo-Comparable $Desired.$field $kind $addressFields) -cne (ConvertTo-Comparable $Current.$field $kind $addressFields)) {
            $field
        }
    }
    return $changes
}
