param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'
param sku string = 'S0'

param deployModel bool = false
param modelName string?
param modelVersion string?
@allowed([
  'Standard'
  'GlobalStandard'
  'ProvisionedManaged'
  'DataZoneStandard'
])
param modelCapacityType string = 'Standard'
param modelCapacity int?
param modelFormat string = 'OpenAI'

// AI Foundry Resource (CognitiveServices account with kind AIServices)
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: publicNetworkAccess
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
  }
  sku: {
    name: sku
  }
}

// AI Foundry Project
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  name: '${name}-project'
  parent: account
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Deploy model (for OpenAI)
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployModel) {
  name: modelName ?? ''
  parent: account
  sku: {
    name: modelCapacityType
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName ?? ''
      version: modelVersion
    }
  }
}

output endpoint string = account.properties.endpoint
output openAIEndpoint string = 'https://${name}.openai.azure.com/'
output id string = account.id
output name string = account.name
