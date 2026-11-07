extension microsoftGraphV1

metadata description = 'Grants Microsoft Graph application permissions (app roles) to a managed identity.'

@description('Object ID of the managed identity service principal.')
param principalId string

@description('Microsoft Graph application permissions to grant, for example User.Read.All.')
param appRoles string[]

// Microsoft Graph's well-known application ID.
resource microsoftGraph 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

resource assignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [
  for role in appRoles: {
    principalId: principalId
    resourceId: microsoftGraph.id
    appRoleId: filter(microsoftGraph.appRoles, appRole => appRole.value == role)[0].id
  }
]
