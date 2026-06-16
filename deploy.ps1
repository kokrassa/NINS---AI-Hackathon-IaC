<#
.SYNOPSIS
    Deploys the foundryInstances Bicep template at subscription scope.

.DESCRIPTION
    Wraps 'az deployment sub create' to deploy N resource groups, each containing
    one AI Foundry resource, using foundryInstances.bicep and its .bicepparam file.

.PARAMETER Location
    Azure region used to store the subscription deployment metadata. Defaults to swedencentral.

.PARAMETER TemplateFile
    Path to the Bicep template. Defaults to foundryInstances.bicep next to this script.

.PARAMETER ParametersFile
    Path to the .bicepparam file. Defaults to foundryInstances.bicepparam next to this script.

.PARAMETER SubscriptionId
    Optional subscription ID to target. If omitted, the current az CLI subscription is used.

.PARAMETER WhatIf
    Run a what-if preview instead of an actual deployment.

.EXAMPLE
    ./deploy.ps1

.EXAMPLE
    ./deploy.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -WhatIf
#>
[CmdletBinding()]
param(
    [string]$Location = 'swedencentral',

    [string]$TemplateFile = (Join-Path $PSScriptRoot 'foundryInstances.bicep'),

    [string]$ParametersFile = (Join-Path $PSScriptRoot 'foundryInstances.bicepparam'),

    [string]$SubscriptionId,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Ensure the Azure CLI is available.
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI ('az') was not found on PATH. Install it from https://learn.microsoft.com/cli/azure/install-azure-cli"
}

# Confirm an active az login session.
if (-not (az account show 2>$null)) {
    throw "No active Azure CLI session. Run 'az login' first."
}

if ($SubscriptionId) {
    Write-Host "Setting active subscription to $SubscriptionId" -ForegroundColor Cyan
    az account set --subscription $SubscriptionId
}

$deploymentName = "foundryInstances-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$azArgs = @(
    'deployment', 'sub', 'create'
    '--name', $deploymentName
    '--location', $Location
    '--template-file', $TemplateFile
    '--parameters', $ParametersFile
)

if ($WhatIf) {
    $azArgs += '--what-if'
}

Write-Host "Deploying '$deploymentName' to location '$Location'..." -ForegroundColor Cyan
az @azArgs

if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed with exit code $LASTEXITCODE."
}

Write-Host "Deployment '$deploymentName' completed successfully." -ForegroundColor Green
