using 'main.bicep'

// Copy this file, fill in your values and deploy with:
//   az deployment group create --resource-group <rg> --template-file deploy/main.bicep --parameters deploy/main.bicepparam

param automationAccountName = 'aa-galsync'
param contactFolderName = 'Global Address List'

param targetMode = 'Group'
param targetGroup = 'SG-GALSync-Users'

param scheduleFrequency = 'Day'
param scheduleTimeZone = 'Europe/Amsterdam'

// To sync another tenant, sign in with an app registration instead of the managed identity:
// param signInMethod = 'Connection'
// param tenantId = 'fabrikam.onmicrosoft.com'
// param clientId = '00001111-aaaa-2222-bbbb-3333cccc4444'
// param clientSecret = readEnvironmentVariable('GALSYNC_CLIENT_SECRET')
// param certificateName = 'GAL-Sync'   // instead of clientSecret, upload the .pfx under Certificates first

// Start with a dry run, check the job output, then set this to false and redeploy.
param reportOnly = true
