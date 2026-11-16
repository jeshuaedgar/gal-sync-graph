metadata description = 'GAL-Sync on Azure Automation: PowerShell 7.6 runtime environment, managed identity, runbook and schedule.'

@description('Name of the Automation account.')
param automationAccountName string

@description('Location of the Automation account.')
param location string = resourceGroup().location

@description('GAL-Sync release to deploy, for example 1.0.0 or 1.0.0-beta1. Used to build the default module and runbook URLs.')
param releaseVersion string = '1.0.0-beta1'

@description('Where the module is downloaded from. Ignored when modulePackageUri is set.')
@allowed([
  'GitHub'
  'PSGallery'
])
param moduleSource string = 'GitHub'

@description('Optional URL of your own module package: a zip with a GAL-Sync folder inside, or a .nupkg. Overrides moduleSource.')
param modulePackageUri string = ''

@description('URL of the runbook script. Defaults to the GitHub release asset.')
param runbookUri string = 'https://github.com/JeshuaEdgar/gal-sync-graph/releases/download/v${releaseVersion}/GAL-Sync-Runbook.ps1'

@description('Name of the contact folder created in each mailbox.')
param contactFolderName string = 'Global Address List'

@description('How the runbook signs in to Microsoft Graph. ManagedIdentity only works for the tenant of the Automation account. Connection uses an app registration, for example for another tenant, stored in a GALSync connection asset.')
@allowed([
  'ManagedIdentity'
  'Connection'
])
param signInMethod string = 'ManagedIdentity'

@description('Connection: tenant ID or contoso.onmicrosoft.com of the tenant to sync.')
param tenantId string = ''

@description('Connection: application (client) ID of the app registration.')
param clientId string = ''

@description('Connection: client secret of the app registration. Leave empty when you use a certificate.')
@secure()
param clientSecret string = ''

@description('Connection: name of a certificate asset (.pfx with private key) in the Automation account. Upload it under Certificates, it is used instead of the client secret.')
param certificateName string = ''

@description('Which mailboxes receive the contacts.')
@allowed([
  'AllUsers'
  'Group'
  'Mailbox'
])
param targetMode string = 'Group'

@description('Group (display name or object ID) whose members receive the contacts. Used when targetMode is Group.')
param targetGroup string = ''

@description('Comma-separated mailboxes that receive the contacts. Used when targetMode is Mailbox.')
param targetMailboxes string = ''

@description('Optional group (display name or object ID): only its members are synced as contacts.')
param sourceGroup string = ''

@description('Optional comma-separated object IDs, UPNs or email addresses to leave out of the contacts.')
param excludeUsers string = ''

param includeUsersWithoutPhone bool = false
param includeUsersWithoutEmail bool = false
param includeDisabledUsers bool = false
param includeGuests bool = false

@description('Optional OData filter for the users that become contacts, for example "companyName eq \'Contoso\'".')
param userFilter string = ''

@description('Leave out users that Microsoft Graph reports as hidden from the address list. Best effort: this value can be out of sync with Exchange Online.')
param excludeHiddenFromAddressList bool = false

@description('Also sync organisational (mail) contacts. Grants OrgContact.Read.All when grantGraphPermissions is true.')
param includeOrgContacts bool = false

@description('When a user has no mobile number, show their business number as the contact\'s mobile number.')
param businessPhoneAsMobile bool = false

@description('Mailboxes synced at the same time.')
@minValue(1)
@maxValue(16)
param throttleLimit int = 4

@description('Report planned changes without writing to mailboxes.')
param reportOnly bool = false

@description('Log verbose records of the runbook: a table of the results and details per mailbox. Can also be switched under Logging and tracing of the runbook.')
param verboseLogging bool = false

@description('Grant the Microsoft Graph permissions to the managed identity in this deployment. Needs Privileged Role Administrator (or Global Administrator). Only used with ManagedIdentity.')
param grantGraphPermissions bool = true

@description('Grant Contacts.ReadWrite in Entra, which covers every mailbox. Turn off to scope mailbox access with Exchange RBAC for Applications instead. Only used when grantGraphPermissions is true.')
param grantContactsAccess bool = true

@description('How often the sync runs.')
@allowed([
  'Hour'
  'Day'
])
param scheduleFrequency string = 'Day'

@minValue(1)
param scheduleInterval int = 1

@description('First run (ISO 8601, at least 5 minutes in the future). Defaults to one hour after deployment.')
param scheduleStartTime string = dateTimeAdd(utcNow(), 'PT1H')

@description('Time zone of the schedule, for example Europe/Amsterdam.')
param scheduleTimeZone string = 'UTC'

param tags object = {}

var runtimeEnvironmentName = 'GALSync-PowerShell-7-6'
var runbookName = 'GAL-Sync'
var configurationVariableName = 'GALSyncConfig'

var moduleUri = !empty(modulePackageUri)
  ? modulePackageUri
  : moduleSource == 'PSGallery'
      ? 'https://www.powershellgallery.com/api/v2/package/GAL-Sync/${releaseVersion}'
      : 'https://github.com/JeshuaEdgar/gal-sync-graph/releases/download/v${releaseVersion}/GAL-Sync.zip'

var connectionName = 'GAL-Sync'

var signInConfiguration = signInMethod == 'Connection' ? { AutomationConnection: connectionName } : {}

var configuration = union(
  signInConfiguration,
  targetMode == 'AllUsers' ? { AllUsers: true } : targetMode == 'Group' ? { TargetGroup: targetGroup } : { TargetMailbox: targetMailboxes },
  empty(sourceGroup) ? {} : { SourceGroup: sourceGroup },
  empty(excludeUsers) ? {} : { ExcludeUser: excludeUsers },
  empty(userFilter) ? {} : { UserFilter: userFilter },
  {
    ContactFolderName: contactFolderName
    IncludeUsersWithoutPhone: includeUsersWithoutPhone
    IncludeUsersWithoutEmail: includeUsersWithoutEmail
    IncludeDisabledUsers: includeDisabledUsers
    IncludeGuests: includeGuests
    ExcludeHiddenFromAddressList: excludeHiddenFromAddressList
    IncludeOrgContacts: includeOrgContacts
    BusinessPhoneAsMobile: businessPhoneAsMobile
    ThrottleLimit: throttleLimit
    WhatIf: reportOnly
  }
)

// Automation variable values are JSON. A string variable is a quoted JSON string, so the
// configuration JSON is wrapped in an array, serialised, and the brackets are stripped.
var configurationArray = string([string(configuration)])
var configurationVariableValue = substring(configurationArray, 1, max(length(configurationArray) - 2, 0))

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    disableLocalAuth: true
  }
}

resource runtimeEnvironment 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: runtimeEnvironmentName
  location: location
  tags: tags
  properties: {
    description: 'PowerShell 7.6 (LTS) for GAL-Sync. No Az modules are needed.'
    runtime: {
      language: 'PowerShell'
      version: '7.6'
    }
  }
}

resource modulePackage 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnvironment
  name: 'GAL-Sync'
  properties: {
    contentLink: {
      uri: moduleUri
    }
  }
}

resource configurationVariable 'Microsoft.Automation/automationAccounts/variables@2024-10-23' = {
  parent: automationAccount
  name: configurationVariableName
  properties: {
    description: 'GAL-Sync settings (JSON). Edit here or redeploy the template.'
    isEncrypted: false
    value: configurationVariableValue
  }
}

resource connectionType 'Microsoft.Automation/automationAccounts/connectionTypes@2024-10-23' = if (signInMethod == 'Connection') {
  parent: automationAccount
  name: 'GALSync'
  properties: {
    isGlobal: false
    fieldDefinitions: {
      TenantId: {
        isEncrypted: false
        isOptional: false
        type: 'System.String'
      }
      ClientId: {
        isEncrypted: false
        isOptional: false
        type: 'System.String'
      }
      ClientSecret: {
        isEncrypted: true
        isOptional: true
        type: 'System.String'
      }
      CertificateName: {
        isEncrypted: false
        isOptional: true
        type: 'System.String'
      }
    }
  }
}

resource connection 'Microsoft.Automation/automationAccounts/connections@2024-10-23' = if (signInMethod == 'Connection') {
  parent: automationAccount
  name: connectionName
  properties: {
    description: 'App registration GAL-Sync signs in with. Fill in ClientSecret or CertificateName.'
    connectionType: {
      name: connectionType.name
    }
    fieldDefinitionValues: {
      TenantId: tenantId
      ClientId: clientId
      ClientSecret: clientSecret
      CertificateName: certificateName
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: runbookName
  location: location
  tags: tags
  properties: {
    description: 'Syncs the Global Address List into a contact folder in each target mailbox.'
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
    logProgress: false
    logVerbose: verboseLogging
    publishContentLink: {
      uri: runbookUri
    }
  }
  dependsOn: [
    modulePackage
  ]
}

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  parent: automationAccount
  name: 'GAL-Sync'
  properties: {
    frequency: scheduleFrequency
    interval: scheduleInterval
    startTime: scheduleStartTime
    timeZone: scheduleTimeZone
  }
}

resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2024-10-23' = {
  parent: automationAccount
  name: guid(automationAccount.id, runbookName, schedule.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: schedule.name
    }
    parameters: {
      ConfigurationVariable: configurationVariableName
    }
  }
}

module graphPermissions 'modules/graph-app-roles.bicep' = if (grantGraphPermissions && signInMethod == 'ManagedIdentity') {
  name: 'galsync-graph-permissions'
  params: {
    principalId: automationAccount.identity.principalId
    appRoles: concat(
      ['User.Read.All'],
      grantContactsAccess ? ['Contacts.ReadWrite'] : [],
      targetMode == 'Group' || !empty(sourceGroup) ? ['GroupMember.Read.All'] : [],
      includeOrgContacts ? ['OrgContact.Read.All'] : []
    )
  }
}

@description('Object ID of the managed identity.')
output managedIdentityPrincipalId string = automationAccount.identity.principalId

output automationAccountName string = automationAccount.name
output runbookName string = runbook.name
