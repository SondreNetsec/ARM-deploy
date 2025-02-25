@description('The base URI where artifacts required by this template are located.')
param _artifactsLocation string = 'https://raw.githubusercontent.com/SondreNetsec/ARM-deploy/main/Create-NewSolutionAndRulesFromList.ps1'

@description('The sasToken required to access _artifactsLocation.')
@secure()
param _artifactsLocationSasToken string = ''

@description('Name of the Log Analytics Workspace to create or use')
param workspaceName string

@description('Location in which to deploy resources')
param location string = resourceGroup().location

@description('Which solutions to deploy automatically')
param contentSolutions string[] = [
  'Microsoft Entra ID'
  'Microsoft 365'
]

var _solutionId = 'azuresentinel.azure-sentinel-solution-office365'
var _solutionVersion = '3.0.5'
var _solutionSufix = '${_solutionId}-Solution-${_solutionId}-${_solutionVersion}'
var roleDefinitionId = 'ab8e14d6-4a74-4a29-9ba8-549422addade'
var subscriptionId = subscription().id

// 1. Create Log Analytics workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: 90
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Create Microsoft Sentinel on the Log Analytics Workspace
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspaceName})'
  location: location
  properties: {
    workspaceResourceId: logAnalytics.id
  }
  plan: {
    name: 'SecurityInsights(${workspaceName})'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
    publisher: 'Microsoft'
  }
}

resource SentinelOnboard 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  name: 'default'
  scope: logAnalytics
}

// Enable the Entity Behavior directory service
resource EntityAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'EntityAnalytics'
  kind: 'EntityAnalytics'
  scope: logAnalytics
  properties: {
    entityProviders: ['AzureActiveDirectory']
  }
  dependsOn: [
    SentinelOnboard
  ]
}

// Enable the additional UEBA data sources
resource uebaAnalytics 'Microsoft.SecurityInsights/settings@2023-02-01-preview' = {
  name: 'Ueba'
  kind: 'Ueba'
  scope: logAnalytics
  properties: {
    dataSources: ['AuditLogs', 'AzureActivity', 'SigninLogs', 'SecurityEvent']
  }
  dependsOn: [
    EntityAnalytics
  ]
}

resource ContentHub_Office365 'Microsoft.SecurityInsights/contentPackages@2023-04-01-preview' = {
  name: 'Microsoft 365'
  scope: logAnalytics
  properties: {
    contentId: _solutionId
    contentProductId: '${take(_solutionId,50)}-sl-${uniqueString(_solutionSufix)}'
    contentKind: 'Solution'
    displayName: 'Microsoft 365 (formerly, Office 365)'
    version: _solutionVersion
    contentSchemaVersion: '2.0.0'
  }
dependsOn: [
  SentinelOnboard
]
}


// 3. Optional: Enable the Office 365 connector
//    Note: The "name" for data connectors is up to you, but must be unique in the workspace.
//    The "kind" is "Office365". The tenantId is the subscription tenant.
 resource office365Connector 'Microsoft.SecurityInsights/dataConnectors@2023-02-01-preview' = {
  name: 'Office365Config'
  scope: logAnalytics
  location: location
  dependsOn: [ContentHub_Office365]
  kind: 'Office365'
  properties: {   
   
    dataTypes: {
      exchange: {
        state: 'Enabled'
      }
      sharePoint: {
        state: 'Enabled'
      }
      teams: {
        state: 'Enabled'
      }
    }
  tenantId: subscription().tenantId
  }
} 

//Create the user identity to interact with Azure
@description('The user identity for the deployment script.')
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'script-identity'
  location: location
}

//Pausing for 5 minutes to allow the new user identity to propagate
resource pauseScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'pauseScript'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '12.2.0'
    scriptContent: 'Start-Sleep -Seconds 300'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    scriptIdentity
  ]
}

//Assign the Sentinel Contributor rights on the Resource Group to the User Identity that was just created
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().name, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: scriptIdentity.properties.principalId
  }
  dependsOn: [
    pauseScript
  ]
}

//  Call the external PowerShell script to deploy the solutions and rules
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploySolutionsScript'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '12.2.0'
    arguments: '-ResourceGroup ${resourceGroup().name} -Workspace ${workspaceName} -Region ${resourceGroup().location} -Solutions ${contentSolutions} -SubscriptionId ${subscriptionId} -TenantId ${subscription().tenantId} -Identity ${scriptIdentity.properties.clientId} '
    primaryScriptUri: '${_artifactsLocation}${_artifactsLocationSasToken}'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
  dependsOn: [
    roleAssignment
  ]
}
