@description('The hub networking which it is going to be peering')
param hubVnetResourceId string

@description('The spokes\'s regional affinity. All resources tied to this spoke will also be homed in this region.  The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
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

var orgAppId = 'ShippingDroneDelivery'
var clusterVNetName = 'vnet-hub-spoke-${orgAppId}-00'
var routeTableName = 'route-${clusterVNetName}-clusternodes-to-hub'
var hubRgName = split(hubVnetResourceId, '/')[4]
var hubNetworkName = split(hubVnetResourceId, '/')[8]
var acrPrivateDnsZonesName = 'privatelink.azurecr.io'
var akvPrivateDnsZonesName = 'privatelink.vaultcore.azure.net'
var clusterSubnetPrefix = '10.240.0.0/22'
var gatewaySubnetPrefix = '10.240.4.16/28'

resource routeTable 'Microsoft.Network/routeTables@2023-04-01' = {
  location: location
  name: routeTableName
  properties: {
    routes: [
      {
        name: 'r-nexthop-to-fw'
        properties: {
          nextHopType: 'VirtualAppliance'
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: reference(resourceId(hubRgName, 'Microsoft.Network/azureFirewalls', 'fw-${location}-hub'), '2023-04-01', 'Full').properties.ipConfigurations[0].properties.privateIpAddress
        }
      }
    ]
  }
}

resource clusterVNet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: clusterVNetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.240.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-clusternodes'
        properties: {
          addressPrefix: clusterSubnetPrefix
          serviceEndpoints: []
          routeTable: {
            id: routeTable.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-clusteringressservices'
        properties: {
          addressPrefix: '10.240.4.0/28'
        }
      }
      {
        name: 'snet-applicationgateways'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

resource clusterVNetNameSpokeToHubNetwork 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: clusterVNet
  name: 'spoke-to-${hubNetworkName}'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetResourceId
    }
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource clusterVNetMicrosoftInsightsToHub 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: clusterVNet
  name: 'toHub'
  properties: {
    workspaceId: resourceId(hubRgName, 'Microsoft.OperationalInsights/workspaces', 'la-networking-hub-${reference(hubVnetResourceId, '2023-04-01', 'Full').location}-${uniqueString(hubVnetResourceId)}')
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

module CreateHubToSpokePeer './nested_spoke-shipping-dronedelivery.bicep' = {
  name: 'CreateHubToSpokePeer'
  scope: resourceGroup(hubRgName)
  params: {
    clusterVNetResourceId: clusterVNet.id
    hubNetworkName: hubNetworkName
    clusterVNetName: clusterVNetName
  }
}

resource acrPrivateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: acrPrivateDnsZonesName
  location: 'global'
  properties: {}
}

resource akvPrivateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: akvPrivateDnsZonesName
  location: 'global'
  properties: {}
}

resource acrPrivateDnsZonesName_Microsoft_Network_virtualNetworks_clusterVNet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZones
  name: uniqueString(clusterVNet.id)
  location: 'global'
  properties: {
    virtualNetwork: {
      id: clusterVNet.id
    }
    registrationEnabled: false
  }
}

resource akvPrivateDnsZonesName_Microsoft_Network_virtualNetworks_clusterVNet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: akvPrivateDnsZones
  name: uniqueString(clusterVNet.id)
  location: 'global'
  properties: {
    virtualNetwork: {
      id: clusterVNet.id
    }
    registrationEnabled: false
  }
}

resource pipOrgAppId00 'Microsoft.Network/publicIpAddresses@2023-04-01' = {
  name: 'pip-${orgAppId}-00'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

output clusterVnetResourceId string = clusterVNet.id
output nodepoolSubnetResourceIds array = [
  resourceId('Microsoft.Network/virtualNetworks/subnets', clusterVNetName, 'snet-clusternodes')
]
output appGwPublicIpAddress string = pipOrgAppId00.properties.ipAddress
output clusterSubnetPrefix string = clusterSubnetPrefix
output gatewaySubnetPrefix string = gatewaySubnetPrefix
