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
param location string

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
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
          ]
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'AzureFirewallSubnet')
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
    ]
    applicationRuleCollections: []
  }
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
