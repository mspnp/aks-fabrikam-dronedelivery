@description('Aks Cluster identity.')
param clusterIdentityObjectId string

@description('The name of the resource group that contains the virtual network for acr.')
param vNetResourceGroup string

@description('The resource id of the Log Analytics Workspace.')
param logAnalyticsWorkspaceId string

@description('The name of the Azure Container Registry (ACR) name.')
param acrName string

@description('The resource id of the subnet that the node pool will be deployed to.')
param vnetNodePoolSubnetResourceId string

@description('AKS Service, Node Pool, and supporting services (KeyVault, App Gateway, etc) region.  The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
param location string = resourceGroup().location

var acrPullRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource acrMicrosoftAuthorizationAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(concat(resourceGroup().id), '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRole
    principalId: clusterIdentityObjectId
    principalType: 'ServicePrincipal'
  }
  dependsOn: []
}

resource nodepoolToAcrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-04-01' = {
  name: 'nodepool-to-acr'
  location: location
  properties: {
    subnet: {
      id: vnetNodePoolSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'nodepoolsubnet-to-registry'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
  dependsOn: []
}

resource nodepoolToAcrDefaultDNSGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-04-01' = {
  parent: nodepoolToAcrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: resourceId(vNetResourceGroup, 'Microsoft.Network/privateDnsZones', 'privatelink.azurecr.io')
        }
      }
    ]
  }
}

resource acrMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: acr
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        timeGrain: 'PT1M'
        category: 'AllMetrics'
        enabled: true
      }
    ]
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
      }
    ]
  }
}
