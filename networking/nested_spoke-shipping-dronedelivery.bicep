@description('Creates a virtual network peering from the hub network to the cluster network')
param clusterVNetResourceId string

@description('The name of the hub network')
param hubNetworkName string


@description('The name of the cluster network')
param clusterVNetName string

resource hubNetworkNameToClusterVNet 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2019-11-01' = {
  name: '${hubNetworkName}/hub-to-${clusterVNetName}'
  properties: {
    remoteVirtualNetwork: {
      id: clusterVNetResourceId
    }
    allowForwardedTraffic: false
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    useRemoteGateways: false
  }
}
