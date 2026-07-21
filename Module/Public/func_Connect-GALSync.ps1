function Connect-GALSync {
    param (
        [CmdletBinding()]
        [System.IO.FileInfo]$CredentialFile,
        [pscredential]$Credential,
        [parameter(Mandatory)][string]$Tenant
    )
    # Create a function to decrypt either file or PSCredential object
    function Decrypt-AppSecret {
        param (
            [pscredential]$Credential
        )
        # Decrypt ApplicationSecret for getting a token
        try {
            $encrypted_data = ConvertFrom-SecureString $credential.Password
            $password_securestring = ConvertTo-SecureString $encrypted_data
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password_securestring))
        }
        catch {
            throw $_.Exception.Message
        }
    }
    # Check the parameters
    if ((-not $CredentialFile) -and (-not $Credential)) {
        throw "Please provide credential in the forms of a credential file or PSCredential object"
    }

    # Throw error if file is not present
    elseif (($CredentialFile) -and (-not (Test-Path $CredentialFile))) {
        throw "Credential file does not exist! Please check if it is present or the path is filled in correctly..."
    }

    elseif ($CredentialFile) {
        $credentialObject = Import-Clixml -Path $CredentialFile
        $clientSecret = Decrypt-AppSecret $credentialObject
    }

    elseif ($Credential) {
        $credentialObject = $Credential
        $clientSecret = Decrypt-AppSecret $Credential
    }

    $necesaryAppRoles = @("Group.Read.All", "Contacts.ReadWrite", "User.Read.All", "OrgContact.Read.All")
    function Check-Permissions {
        [CmdletBinding()]
        param (
            $AppScopes
        )
        $comparisson = Compare-Object $necesaryAppRoles $AppScopes
        if (-not ($comparisson | Where-Object { $_.SideIndicator -eq "<=" })) {
            Write-VerboseEvent "Permissions are OK!"
        }
        else {
            throw "Missing the $(($comparisson | Where-Object {$_.SideIndicator -eq "<="}).InputObject -join ", ") role(s), please update your application and rerun the script"
        }
    }

    if ($UseGraphSDK) {
        Connect-MgGraph -TenantId $Tenant -ClientSecretCredential $credentialObject
        $ctx = Get-MgContext
        Check-Permissions -AppScopes $ctx.Scopes
        return $true
    }

    try {
        # Make body
        $applicationId = $credentialObject.UserName
        $requestbody = @{
            client_id     = $applicationId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $clientSecret
            grant_type    = "client_credentials"
        }
        # Get token
        $tokenRequest = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Tenant)/oauth2/v2.0/token" -Method POST -Body $requestbody -ContentType "application/x-www-form-urlencoded"
        
        # Check permissions
        $tokenPayload = $tokenRequest.access_token.Split(".")[1].Replace('-', '+').Replace('_', '/')
        while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
        $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
        $applicationRoles = [System.Text.Encoding]::ASCII.GetString($tokenByteArray) | ConvertFrom-Json | Select-Object -ExpandProperty roles

        Check-Permissions -AppScopes $applicationRoles
        
        # Set token
        $script:galSyncData.Tenant = $Tenant
        $script:galSyncData.GraphAuthHeader = @{
            Authorization  = "Bearer $($tokenRequest.access_token)"
            "Content-Type" = "application/json"
        }
        $script:galSyncData.TokenExpiration = (Get-Date).AddSeconds($tokenRequest.expires_in)
        return $true
    }
    catch {
        throw (Format-ErrorCode $_).ErrorMessage
    }
}