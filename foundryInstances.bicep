targetScope = 'subscription'

@description('Number of resource group / AI Foundry instances to deploy. Each instance is a resource group containing one AI Foundry resource.')
@minValue(1)
@maxValue(800)
param instanceCount int

@description('Azure region for all resource groups and AI Foundry resources.')
param location string

@description('Prefix used to name each resource group. A zero-padded index suffix is appended per instance (e.g. rg-aifoundry-001).')
param resourceGroupNamePrefix string

@description('Prefix used to name each AI Foundry resource. A zero-padded index and a uniqueness suffix are appended per instance to keep the name globally unique.')
param foundryNamePrefix string

@description('Tags applied to every resource group and AI Foundry resource.')
param tags object = {}

@description('SKU for each AI Foundry (CognitiveServices) resource.')
param sku string = 'S0'

@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

// Suffix that helps keep the globally unique CognitiveServices account name (and its subdomain) collision free.
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupNamePrefix)

// Resource group created per instance in the target subscription
resource resourceGroups 'Microsoft.Resources/resourceGroups@2025-04-01' = [
  for i in range(0, instanceCount): {
    name: '${resourceGroupNamePrefix}-${padLeft(string(i + 1), 3, '0')}'
    location: location
    tags: tags
  }
]

// AI Foundry resource deployed into each resource group via a module (nested deployment)
module aiFoundry 'aiFoundryAccount.module.bicep' = [
  for i in range(0, instanceCount): {
    name: 'aiFoundry-${padLeft(string(i + 1), 3, '0')}'
    scope: resourceGroups[i]
    params: {
      name: toLower('${foundryNamePrefix}${padLeft(string(i + 1), 3, '0')}${uniqueSuffix}')
      location: location
      tags: tags
      sku: sku
      publicNetworkAccess: publicNetworkAccess
    }
  }
]

output resourceGroupNames array = [for i in range(0, instanceCount): resourceGroups[i].name]
output foundryAccountIds array = [for i in range(0, instanceCount): aiFoundry[i].outputs.id]
output foundryEndpoints array = [for i in range(0, instanceCount): aiFoundry[i].outputs.endpoint]
