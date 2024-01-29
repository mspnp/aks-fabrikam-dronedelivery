@description('Subnet resource Ids for all AKS clusters nodepools in all attached spokes to allow necessary outbound traffic through the firewall')
param nodepoolSubnetResourceIds array

@description('The hub\'s regional affinity. All resources tied to this hub will also be homed in this region.  The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
  'westus3'
])
param location string = 'eastus2'

@description('A /24 to contain the firewall, management, and gateway subnet')
@minLength(10)
@maxLength(18)
param hubVnetAddressSpace string = '10.200.0.0/24'

@description('A /26 under the VNet Address Space for Azure Firewall')
@minLength(10)
@maxLength(18)
param azureFirewallSubnetAddressSpace string = '10.200.0.0/26'

@description('A /27 under the VNet Address Space for our On-Prem Gateway')
@minLength(10)
@maxLength(18)
param azureGatewaySubnetAddressSpace string = '10.200.0.64/27'

@description('A /27 under the VNet Address Space for Azure Bastion')
@minLength(10)
@maxLength(18)
param azureBastionSubnetAddressSpace string = '10.200.0.96/27'

@description('the location that will be used from the Azure Firewall rules to regionally allow establishing connections against Azure specific services.')
@allowed([
  'CentralUS'
  'WestUS'
  'EastUS2'
  'WestUS2'
  'FranceCentral'
  'NorthEurope'
  'UKSouth'
  'WestEurope'
  'JapanEast'
  'SoutheastAsia'
  'WestUS3'
])
param serviceTagsLocation string = 'EastUS2'

@description('the Fabrikam Shipping Drone Delivery 00\'s Azure Container Registries server names for dev-qa-staging and production.')
param acrServers array = [
  '*.azurecr.io'
]

@description('the Azure Redis Caches names for the Fabrikam Shipping Drone Delivery 00\'s delivery app in dev-qa-staging and production. It will be used to create an Azure Firewall FQDN Application Rule.')
param deliveryRedisHostNames array = [
  '*.redis.cache.windows.net'
]

var aksIpGroupName = 'ipg-${location}-AksNodepools'
var defaultFwPipName = 'pip-fw-${location}-default'
var hubFwName = 'fw-${location}-hub'
var hubVNetName = 'vnet-${location}-hub'
var hubLaName = 'la-networking-hub-${location}-${uniqueString(hubVnet.id)}'

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: hubVNetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: azureFirewallSubnetAddressSpace
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: azureGatewaySubnetAddressSpace
          serviceEndpoints: []
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: azureBastionSubnetAddressSpace
          serviceEndpoints: []
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

resource defaultFwPip 'Microsoft.Network/publicIpAddresses@2023-04-01' = {
  name: defaultFwPipName
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

resource aksIpGroup 'Microsoft.Network/ipGroups@2023-04-01' = {
  location: location
  name: aksIpGroupName
  properties: {
    ipAddresses: [for item in nodepoolSubnetResourceIds: reference(item, '2019-11-01').addressPrefix]
  }
}

resource hubFw 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: hubFwName
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    ipConfigurations: [
      {
        name: defaultFwPipName
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVNetName, 'AzureFirewallSubnet')
          }
          publicIPAddress: {
            id: defaultFwPip.id
          }
        }
      }
    ]
    natRuleCollections: []
    networkRuleCollections: [
      {
        name: 'org-wide-allowed'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 100
          rules: [
            {
              name: 'dns'
              sourceAddresses: [
                '*'
              ]
              protocols: [
                'UDP'
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '53'
              ]
            }
            {
              name: 'ntp'
              description: 'Network Time Protocol (NTP) time synchronization'
              sourceAddresses: [
                '*'
              ]
              protocols: [
                'UDP'
              ]
              destinationPorts: [
                '123'
              ]
              destinationAddresses: [
                '*'
              ]
            }
          ]
        }
      }
      {
        name: 'AKS-Global-Requirements'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 200
          rules: [
            {
              name: 'tunnel-front-pod-tcp'
              description: 'Tunnel front pod to communicate with the tunnel end on the API server.  Technically only needed to our API servers.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                'TCP'
              ]
              destinationPorts: [
                '22'
                '9000'
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
            }
            {
              name: 'tunnel-front-pod-udp'
              description: 'Tunnel front pod to communicate with the tunnel end on the API server.  Technically only needed to our API servers.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                'UDP'
              ]
              destinationPorts: [
                '1194'
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
            }
            {
              name: 'managed-k8s-api-tcp-443'
              description: 'in-cluster apps could contact the Kubernetes Api Server using its endpoing IP address without providing the SNI extension, something which is not allowed by Azure Firewall. This rule takes care of it by allowing to establish connections against well-known Azure Public Ip addresses over the port 443. For instance this will be the case of Microsoft Entra Pod identity if it does not reside within the kube-system namespace or Azure Application Gateway Ingress Controller'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '443'
              ]
            }
          ]
        }
      }
      {
        name: 'AKS-Fabrikam-Shipping-DroneDelivery-00'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 300
          rules: [
            {
              name: 'servicebus'
              description: 'Azure Service Bus access for ingestion and workflow apps'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'ServiceBus.${serviceTagsLocation}'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '5671'
              ]
            }
            {
              name: 'azure-cosmosdb'
              description: 'Azure Cosmos Db access for delivery and drone scheduler apps'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'AzureCosmosDB.${serviceTagsLocation}'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '443'
              ]
            }
            {
              name: 'azure-mongodb'
              description: 'Azure Mongo Db access for package app'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'AzureCosmosDB.${serviceTagsLocation}'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '10255'
              ]
            }
            {
              name: 'azure-keyvault'
              description: 'Azure Key Vault access for delivery, workflow and dronescheduler apps'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'AzureKeyVault.${serviceTagsLocation}'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '443'
              ]
            }
            {
              name: 'azure-monitor'
              protocols: [
                'TCP'
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              destinationAddresses: [
                'AzureMonitor'
              ]
              destinationIpGroups: []
              destinationFqdns: []
              destinationPorts: [
                '443'
              ]
            }
          ]
        }
      }
    ]
    applicationRuleCollections: [
      {
        name: 'AKS-Global-Requirements'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 200
          rules: [
            {
              name: 'nodes-to-api-server'
              description: 'This address is required for Node <-> API server communication.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                '*.hcp.eastus2.azmk8s.io'
                '*.tun.eastus2.azmk8s.io'
              ]
            }
            {
              name: 'microsoft-container-registry'
              description: 'All URLs related to MCR needed by AKS'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                '*.cdn.mscr.io'
                'mcr.microsoft.com'
                '*.data.mcr.microsoft.com'
              ]
            }
            {
              name: 'management-plane'
              description: 'This address is required for Kubernetes GET/PUT operations.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'management.azure.com'
              ]
            }
            {
              name: 'aad-auth'
              description: 'This address is required for Microsoft Entra authentication.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'login.microsoftonline.com'
              ]
            }
            {
              name: 'apt-get'
              description: 'This address is the Microsoft packages repository used for cached apt-get operations. Example packages include Moby, PowerShell, and Azure CLI.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'packages.microsoft.com'
              ]
            }
            {
              name: 'cluster-binaries'
              description: 'This address is for the repository required to install required binaries like kubenet and Azure CNI.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'acs-mirror.azureedge.net'
              ]
            }
            {
              name: 'ubuntu-security-patches'
              description: 'This address lets the Linux cluster nodes download the required security patches and updates per https://docs.microsoft.com/azure/aks/limit-egress-traffic#optional-recommended-fqdn--application-rules-for-aks-clusters.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Http'
                  port: 80
                }
              ]
              targetFqdns: [
                'security.ubuntu.com'
                'azure.archive.ubuntu.com'
                'changelogs.ubuntu.com'
              ]
            }
            {
              name: 'azure-monitor'
              description: 'All required for Azure Monitor for containers per https://docs.microsoft.com/azure/aks/limit-egress-traffic#azure-monitor-for-containers'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'dc.services.visualstudio.com'
                '*.ods.opinsights.azure.com'
                '*.oms.opinsights.azure.com'
                '*.microsoftonline.com'
                '*.monitoring.azure.com'
              ]
            }
            {
              name: 'azure-policy'
              description: 'All required for Azure Policy per https://docs.microsoft.com/azure/aks/limit-egress-traffic#azure-policy'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'gov-prod-policy-data.trafficmanager.net'
                'raw.githubusercontent.com'
                'dc.services.visualstudio.com'
                'data.policy.core.windows.net'
                'store.policy.core.windows.net'
              ]
            }
          ]
        }
      }
      {
        name: 'Flux-Requirements'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 300
          rules: [
            {
              name: 'flux-to-github'
              description: 'This address is required for Flux <-> Github repository with the desired cluster baseline configuration.'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'github.com'
                'api.github.com'
              ]
            }
            {
              name: 'accompanying-container-registries'
              description: 'helm, agic, aad pod idenity, and others'
              sourceIpGroups: [
                aksIpGroup.id
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                '${location}.dp.kubernetesconfiguration.azure.com'
                'mcr.microsoft.com'
                'raw.githubusercontent.com'
                split(environment().resourceManager, '/')[2] // Prevent the linter from getting upset at management.azure.com - https://github.com/Azure/bicep/issues/3080
                split(environment().authentication.loginEndpoint, '/')[2] // Prevent the linter from getting upset at login.microsoftonline.com
                '*.blob.${environment().suffixes.storage}' // required for the extension installer to download the helm chart install flux. This storage account is not predictable, but does look like eusreplstore196 for example.
                'azurearcfork8s.azurecr.io' // required for a few of the images installed by the extension.
                '*.docker.io' // Only required if you use the default bootstrapping manifests included in this repo.
                '*.docker.com' // Only required if you use the default bootstrapping manifests included in this repo.
                'ghcr.io' // Only required if you use the default bootstrapping manifests included in this repo. Kured is sourced from here by default.
                'pkg-containers.githubusercontent.com' // Only required if you use the default bootstrapping manifests included in this repo. Kured is sourced from here by default.
              ]
            }
          ]
        }
      }
      {
        name: 'AKS-Fabrikam-Shipping-DroneDelivery-00'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 400
          rules: [
            {
              name: 'accompanying-container-registries'
              description: 'helm, agic, aad pod idenity, and others'
              protocols: [
                {
                  protocolType: 'https'
                  port: 443
                }
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              targetFqdns: [
                'gcr.io'
                'storage.googleapis.com'
                'aksrepos.azurecr.io'
                '*.docker.io'
                '*.docker.com'
              ]
            }
            {
              name: 'fabrikam-shipping-dronedelivery-00-container-registries'
              description: 'images for delivery, package, workflow, ingestion and drone scheduler apps'
              protocols: [
                {
                  protocolType: 'https'
                  port: 443
                }
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              targetFqdns: acrServers
            }
            {
              name: 'azure-cache-redis'
              description: 'Azure Redis Cache for delivery app'
              protocols: [
                {
                  protocolType: 'https'
                  port: 6380
                }
              ]
              sourceIpGroups: [
                aksIpGroup.id
              ]
              targetFqdns: deliveryRedisHostNames
            }
          ]
        }
      }
    ]
  }
  dependsOn: [

    hubVnet

  ]
}

resource hubLa 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: hubLaName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource hubFwMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: hubFw
  name: 'default'
  properties: {
    workspaceId: hubLa.id
    logs: [
      {
        category: 'AzureFirewallApplicationRule'
        enabled: true
      }
      {
        category: 'AzureFirewallNetworkRule'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource hubVnetMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: hubVnet
  properties: {
    workspaceId: hubLa.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output hubVnetId string = hubVnet.id
