@description('The name of the application gateway.')
param appGatewayName string

@allowed([
  'dev'
  'qa'
  'staging'
  'prod'
])
param environmentName string

@description('The name of the resource group that will contain the resources.')
param resourceGroupName string

@description('The location where the resources will be created.')
param resourceGroupLocation string = 'eastus'

resource appGatewayControllermanagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appGatewayName
  location: resourceGroupLocation
  tags: {
    displayName: 'app gateway controller managed identity'
    what: 'rbac'
    reason: 'aad-pod-identity'
    '${environmentName}': 'true'
  }
}

output appGatewayControllerIdName string = appGatewayName
output appGatewayControllerPrincipalResourceId string = '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${appGatewayName}'
