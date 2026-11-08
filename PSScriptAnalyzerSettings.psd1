@{
    Severity     = @("Error", "Warning")
    # ShouldProcess lives on the public commands that change mailboxes
    ExcludeRules = @("PSUseShouldProcessForStateChangingFunctions")
}
