param clusterIdentityObjectId string

var virtualMachineContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')

resource clusterIdentityRoleAssigmentVirtualMachineContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id)
  properties: {
    roleDefinitionId: virtualMachineContributorRole
    principalId: clusterIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}
