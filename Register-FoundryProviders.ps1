#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Registers the Azure resource providers that Microsoft Foundry needs in a subscription.
.DESCRIPTION
    Registers the resource providers that the Microsoft Foundry resource, model deployments,
    Foundry Agent Service (agent building), and the playgrounds depend on. Use -IncludeOptional
    to also register the providers that optional Foundry features use, such as Grounding with
    Bing Search, partner models from Azure Marketplace, Browser Automation, tracing, hosted
    agents, publishing to Teams, and private networking.

    Bicep and ARM deployments only register the providers declared in the template
    (Microsoft.CognitiveServices for this repo), so the other providers must be registered
    separately, once per subscription.

    The script is safe to run more than once and on subscriptions that already contain Foundry
    resources: providers that are already registered are skipped, registration is additive, and
    existing resources aren't changed. It waits for every registration to complete and exits
    with code 1 if any provider isn't registered.
.PARAMETER SubscriptionId
    ID or name of the subscription to prepare. Defaults to the current Azure CLI subscription.
.PARAMETER IncludeOptional
    Also register the providers used by optional Foundry features.
.PARAMETER TimeoutMinutes
    Maximum number of minutes to wait for the registrations to complete. Defaults to 15.
.EXAMPLE
    ./Register-FoundryProviders.ps1
.EXAMPLE
    ./Register-FoundryProviders.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -IncludeOptional
.EXAMPLE
    ./Register-FoundryProviders.ps1 -IncludeOptional -WhatIf
.NOTES
    Requires the Azure CLI and the Contributor or Owner role on the subscription, which include
    the */register/action permission. Run it on a new subscription before deploy.ps1.
.LINK
    https://learn.microsoft.com/azure/foundry/agents/how-to/use-your-own-resources#prerequisites
.LINK
    https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeOptional,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 15
)

$ErrorActionPreference = 'Stop'

# Azure CLI exit codes are checked explicitly, so a failed registration doesn't stop the others.
$PSNativeCommandUseErrorActionPreference = $false

#region Configuration

# Needed by the Foundry resource, model deployments, Foundry Agent Service, and the playgrounds.
$RequiredProviders = @(
    'Microsoft.CognitiveServices'       # Foundry resource, projects, model deployments, agents
    'Microsoft.MachineLearningServices' # Foundry Agent Service prerequisite
    'Microsoft.App'                     # Foundry Agent Service runtime
    'Microsoft.ContainerService'        # Foundry Agent Service runtime
    'Microsoft.KeyVault'                # Connection secrets
    'Microsoft.Storage'                 # Files, datasets, and evaluation data
    'Microsoft.Search'                  # Azure AI Search tool and knowledge retrieval
)

# Needed only by specific Foundry features.
$OptionalProviders = @(
    'Microsoft.Bing'                    # Grounding with Bing Search tools
    'Microsoft.SaaS'                    # Partner and community models from Azure Marketplace
    'Microsoft.LoadTestService'         # Browser Automation tool (Playwright workspace)
    'Microsoft.Insights'                # Tracing, monitoring, and evaluations (Application Insights)
    'Microsoft.OperationalInsights'     # Log Analytics workspace behind Application Insights
    'Microsoft.ContainerRegistry'       # Hosted agents (container images)
    'Microsoft.BotService'              # Publishing agents to Teams and Microsoft 365 Copilot
    'Microsoft.Network'                 # Private networking (VNet injection, private endpoints)
    'Microsoft.DocumentDB'              # Standard agent setup with your own Cosmos DB
    'Microsoft.Web'                     # Azure Functions tool and Functions-hosted MCP servers
)

#endregion Configuration

#region Functions

function Get-ProviderRegistrationState {
    <#
    .SYNOPSIS
        Gets the registration state of every resource provider in the subscription.
    .PARAMETER SubscriptionArgs
        Optional --subscription arguments for the Azure CLI.
    .OUTPUTS
        [hashtable] Registration state keyed by provider namespace (case-insensitive).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionArgs = @()
    )

    $lines = az provider list @SubscriptionArgs --query '[].[namespace,registrationState]' --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Couldn't list the resource providers of the subscription."
    }

    $states = @{}
    foreach ($line in $lines) {
        $parts = $line -split "`t"
        if ($parts.Count -ge 2) {
            $states[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $states
}

function Wait-ProviderRegistration {
    <#
    .SYNOPSIS
        Waits until the given resource providers are registered or the timeout expires.
    .PARAMETER Namespace
        Namespaces of the resource providers to wait for.
    .PARAMETER TimeoutMinutes
        Maximum number of minutes to wait.
    .PARAMETER SubscriptionArgs
        Optional --subscription arguments for the Azure CLI.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Namespace,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMinutes,

        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionArgs = @()
    )

    $pending = [System.Collections.Generic.List[string]]::new($Namespace)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $states = Get-ProviderRegistrationState -SubscriptionArgs $SubscriptionArgs
        foreach ($name in $pending.ToArray()) {
            if ($states[$name] -eq 'Registered') {
                Write-Host "  [done]  $name" -ForegroundColor Green
                [void]$pending.Remove($name)
            }
        }
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
            throw "Azure CLI ('az') was not found on PATH. Install it from https://learn.microsoft.com/cli/azure/install-azure-cli"
        }

        $SubscriptionArgs = @()
        if ($SubscriptionId) {
            $SubscriptionArgs = @('--subscription', $SubscriptionId)
        }

        $SubscriptionJson = az account show @SubscriptionArgs --query '{name:name,id:id}' --output json --only-show-errors
        if ($LASTEXITCODE -ne 0 -or -not $SubscriptionJson) {
            throw "Couldn't access the subscription. Run 'az login' first and check the subscription ID."
        }
        $Subscription = ($SubscriptionJson -join "`n") | ConvertFrom-Json

        $Providers = $RequiredProviders
        if ($IncludeOptional) {
            $Providers = $RequiredProviders + $OptionalProviders
        }

        Write-Host "Checking $($Providers.Count) resource providers in subscription '$($Subscription.name)' ($($Subscription.id))..." -ForegroundColor Cyan

        $States = Get-ProviderRegistrationState -SubscriptionArgs $SubscriptionArgs
        $Pending = [System.Collections.Generic.List[string]]::new()

        foreach ($provider in $Providers) {
            $state = $States[$provider]
            if ($state -eq 'Registered') {
                Write-Host "  [skip]  $provider is already registered" -ForegroundColor DarkGray
            }
            elseif ($state -eq 'Registering') {
                Write-Host "  [wait]  $provider is already registering" -ForegroundColor Yellow
                $Pending.Add($provider)
            }
            elseif ($PSCmdlet.ShouldProcess($provider, 'Register resource provider')) {
                az provider register --namespace $provider @SubscriptionArgs --output none --only-show-errors
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [start] $provider registration requested" -ForegroundColor Cyan
                    $Pending.Add($provider)
                }
                else {
                    Write-Host "  [fail]  $provider registration failed" -ForegroundColor Red
                }
            }
        }

        if ($WhatIfPreference) {
            Write-Host 'WhatIf: no resource providers were registered.' -ForegroundColor Yellow
            exit 0
        }

        if ($Pending.Count -gt 0) {
            Write-Host "Waiting up to $TimeoutMinutes minutes for $($Pending.Count) registrations to complete..." -ForegroundColor Cyan
            Wait-ProviderRegistration -Namespace $Pending -TimeoutMinutes $TimeoutMinutes -SubscriptionArgs $SubscriptionArgs
        }

        $States = Get-ProviderRegistrationState -SubscriptionArgs $SubscriptionArgs
        $Providers |
            ForEach-Object { [pscustomobject]@{ Provider = $_; State = $States[$_] } } |
            Format-Table -AutoSize |
            Out-Host

        $NotRegistered = @($Providers | Where-Object { $States[$_] -ne 'Registered' })
        if ($NotRegistered.Count -gt 0) {
            throw "These resource providers aren't registered yet: $($NotRegistered -join ', '). Re-run the script to retry."
        }

        Write-Host "All $($Providers.Count) resource providers are registered." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Register-FoundryProviders failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
