@description('Name of the Log Analytics Workspace to create or use')
param workspaceName string

@description('Location in which to deploy resources')
param location string = resourceGroup().location

// 1. Create Log Analytics workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    sku: {
      name: 'PerGB2018'
    }
  }
}

// 2. Enable Microsoft Sentinel on the workspace
//    This resource effectively installs the "Azure Sentinel" solution.
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${logAnalytics.name})'
  location: location
  properties: {
    workspaceResourceId: logAnalytics.id
  }
  plan: {
    name: 'SecurityInsights(${logAnalytics.name})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
}

// 3. Optional: Enable the Office 365 connector
//    Note: The "name" for data connectors is up to you, but must be unique in the workspace.
//    The "kind" is "Office365". The tenantId is the subscription tenant.
resource office365Connector 'Microsoft.SecurityInsights/dataConnectors@2025-01-01-preview' = {
  name: 'Office365'
  location: location
  properties: {
    kind: 'Office365'
    tenantId: subscription().tenantId
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
  }
}

// 4. (Optional) If you want a specific solution for "UEBA" (some is auto-included in Sentinel):
//    Many UEBA capabilities are automatically part of Sentinel once enabled.
//    Full advanced UEBA might require manual UI steps or additional licensing.
//
//    You might see references to "Microsoft.SecurityInsights/solutions" or "Microsoft.OperationsManagement/solutions",
//    but typically that's the same "Sentinel" solution. 
//    We'll skip a separate resource for UEBA here as it's usually encompassed in Sentinel's core.
