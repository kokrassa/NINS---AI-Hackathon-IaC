using 'foundryInstances.bicep'

// Number of resource groups (and matching AI Foundry resources) to deploy.
param instanceCount = 3

// Region for every resource group and AI Foundry resource.
param location = 'swedencentral'

// Naming prefixes. An index suffix is appended per instance.
param resourceGroupNamePrefix = 'rg-aifoundry-konkra'
param foundryNamePrefix = 'aifoundry-konkra'

param tags = {
  environment: 'dev'
  workload: 'ai-foundry'
}

param sku = 'S0'
param publicNetworkAccess = 'Enabled'

// Model deployment settings (applied to every AI Foundry instance).
param deployModel = true
param modelName = 'gpt-5-mini'
param modelVersion = '2025-08-07'
param modelCapacityType = 'GlobalStandard'
param modelCapacity = 50
param modelFormat = 'OpenAI'
