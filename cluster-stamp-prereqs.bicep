targetScope = 'subscription'

@allowed([
  'dev'
  'qa'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('The name of the resource group that will contain the resources.')
param resourceGroupName string

@description('The location where the resources will be created.')
param resourceGroupLocation string = 'eastus'

var nestedIdDeploymentName = '${deployment().name}-identities'
var environmentSettings = {
  dev: {
    appGatewayControllerIdName: 'dev-ag'
  }
  qa: {
    appGatewayControllerIdName: 'qa-ag'
  }
  staging: {
    appGatewayControllerIdName: 'staging-ag'
  }
  prod: {
    appGatewayControllerIdName: 'prod-ag'
  }
}

module nestedIdDeployment './nested_cluster-stamp-prereqs.bicep' = {
  name: nestedIdDeploymentName
  scope: resourceGroup(resourceGroupName)
  params: {
    appGatewayName: environmentSettings[environmentName].appGatewayControllerIdName
    environmentName: environmentName
    location: resourceGroupLocation
    resourceGroupName: resourceGroupName
  }
  dependsOn: []
}
