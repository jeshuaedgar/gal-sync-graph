function ConvertTo-RedactedText {
    param (
        [AllowNull()][AllowEmptyString()][string]$Text
    )
    if (-not $Text) {
        return $Text
    }
    # best effort: tokens, secrets, email addresses (also URL-encoded in request paths), GUIDs and mailbox item IDs
    $rules = [ordered]@{
        "eyJ[\w-]+\.[\w-]+\.[\w-]*"                                                        = "<token>"
        "(?i)bearer\s+[\w.~+/=-]+"                                                         = "Bearer <token>"
        "(?i)(client_secret|client_assertion|secret|password|pwd)(\s*[=:]\s*)[^\s&;,""']+" = '$1$2<redacted>'
        "[\w.+'#-]+(?:@|%40)[\w-]+(?:\.[\w-]+)+"                                           = "<email>"
        "(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b"                              = "<guid>"
        "AA[\w+/=%-]{30,}"                                                                 = "<id>"
    }
    foreach ($pattern in $rules.Keys) {
        $Text = $Text -replace $pattern, $rules[$pattern]
    }
    return $Text
}
