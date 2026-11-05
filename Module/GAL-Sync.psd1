@{
    RootModule           = "GAL-Sync.psm1"
    ModuleVersion        = "1.0.0"
    CompatiblePSEditions = @("Core")
    GUID                 = "6142701a-c0ea-4577-bfa6-9b6a3858d355"
    Author               = "Jeshua Edgar"
    CompanyName          = "Jeshua Edgar"
    Copyright            = "(c) Jeshua Edgar. All rights reserved."
    Description          = "Sync the Global Address List to a contact folder in every mailbox with Microsoft Graph."
    PowerShellVersion    = "7.6"

    FunctionsToExport    = @(
        "Connect-GALSync"
        "Disconnect-GALSync"
        "Get-GALContactFolder"
        "Get-GALDirectoryUser"
        "Get-GALFolderContact"
        "Get-GALGroupMember"
        "Invoke-GALSync"
        "Remove-GALContactFolder"
        "Sync-GALMailbox"
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @("Microsoft365", "Graph", "GAL", "Contacts", "Exchange", "AzureAutomation")
            LicenseUri   = "https://github.com/JeshuaEdgar/gal-sync-graph/blob/main/LICENSE"
            ProjectUri   = "https://github.com/JeshuaEdgar/gal-sync-graph"
            ReleaseNotes = "https://github.com/JeshuaEdgar/gal-sync-graph/blob/main/CHANGELOG.md"
        }
    }
}
