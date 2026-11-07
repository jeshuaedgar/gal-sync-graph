using 'main.bicep'

// Copy this file, fill in your values and deploy with:
//   az deployment group create --resource-group <rg> --template-file deploy/main.bicep --parameters deploy/main.bicepparam

param automationAccountName = 'aa-galsync'
param contactFolderName = 'Global Address List'

param targetMode = 'Group'
param targetGroup = 'SG-GALSync-Users'

param scheduleFrequency = 'Day'
param scheduleTimeZone = 'Europe/Amsterdam'

// Start with a dry run, check the job output, then set this to false and redeploy.
param reportOnly = true
