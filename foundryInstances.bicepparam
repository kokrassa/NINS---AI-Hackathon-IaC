using 'foundryInstances.bicep'

// Number of resource groups (and matching AI Foundry resources) to deploy.
param instanceCount = 3

// Region for every resource group and AI Foundry resource.
param location = 'swedencentral'

// Naming prefixes. An index suffix is appended per instance.
param resourceGroupNamePrefix = 'rg-aifoundry'
param foundryNamePrefix = 'aifoundry'

param tags = {
  environment: 'dev'
  workload: 'ai-foundry'
}

param sku = 'S0'
param publicNetworkAccess = 'Enabled'
