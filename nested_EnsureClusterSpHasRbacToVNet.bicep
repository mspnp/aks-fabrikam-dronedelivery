@description('Aks Cluster identity.')
param clusterIdentityObjectId string

@description('The regional network spoke VNet Resource ID that the cluster will be joined to')
param targetVnetResourceId string

@description('the principal id for the ingress controller managed identity')
param ingressControllerPrincipalId string

var networkContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
var  vNetName = split(targetVnetResourceId, '/')[8]

resource targetVnetResource 'Microsoft.Network/virtualNetworks@2023-04-01' existing = {
  name: vNetName
}

resource aksClusterTotargetVnetResourceIdMicrosoftAuthorizationNetworkContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '4d97b98b-1d4f-4787-a291-c67834d212e7', '-aks-system-assigned-managed-identity-ilb')
  scope: targetVnetResource
  properties: {
    roleDefinitionId: networkContributorRole
    principalId: clusterIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

resource ShippingDroneDeliveryPublicIP 'Microsoft.Network/publicIpAddresses@2023-04-01' existing = {
  name: 'pip-ShippingDroneDelivery-00'
}

resource aksClusterToPipShippingDroneDeliveryMicrosoftAuthorizationNetworkContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '4d97b98b-1d4f-4787-a291-c67834d212e7', '-agic-system-assigned-managed-identity-appw-public-ip')
  scope:ShippingDroneDeliveryPublicIP
  properties: {
    roleDefinitionId: networkContributorRole
    principalId: ingressControllerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource aksClusterAgicTotargetVnetResourceIdMicrosoftAuthorizationNetworkContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '4d97b98b-1d4f-4787-a291-c67834d212e7', '-agic-system-assigned-managed-identity-appw-network')
  scope:targetVnetResource
  properties: {
    roleDefinitionId: networkContributorRole
    principalId: ingressControllerPrincipalId
    principalType: 'ServicePrincipal'
  }
}
