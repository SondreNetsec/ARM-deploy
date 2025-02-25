@description('Name of the Log Analytics Workspace to create or use')
param workspaceName string

@description('Location in which to deploy resources')
param location string = resourceGroup().location

var _solutionId = 'azuresentinel.azure-sentinel-solution-office365'
var _solutionVersion = '3.0.5'
var _solutionSufix = '${_solutionId}-Solution-${_solutionId}-${_solutionVersion}'

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

resource Sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
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
    Sentinel
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
dependsOn: [Sentinel]
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



// 4. (Optional) If you want a specific solution for "UEBA" (some is auto-included in Sentinel):
//    Many UEBA capabilities are automatically part of Sentinel once enabled.
//    Full advanced UEBA might require manual UI steps or additional licensing.
//
//    You might see references to "Microsoft.SecurityInsights/solutions" or "Microsoft.OperationsManagement/solutions",
//    but typically that's the same "Sentinel" solution. 
//    We'll skip a separate resource for UEBA here as it's usually encompassed in Sentinel's core.
