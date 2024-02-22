@description('The regional network spoke VNet Resource ID that the cluster will be joined to')
param targetVnetResourceId string

@description('Group that has admin access to this cluster')
param k8sRbacEntraAdminGroupObjectID string

@description('This is tennant where the ServerAppId, ServerAppSecret, ClientAppId all reside')
param k8sRbacEntraProfileTenantId string

@description('The certificate data for app gateway TLS termination. It is base64')
param appGatewayListenerCertificate string

@description('The base 64 encoded AKS Ingress Controller public certificate (as .crt or .cer) to be stored in Azure Key Vault as secret and referenced by Azure Application Gateway as a trusted root certificate.')
param aksIngressControllerCertificate string

@description('IP ranges authorized to contact the Kubernetes API server. Passing an empty array will result in no IP restrictions. If any are provided, remember to also provide the public IP of the egress Azure Firewall otherwise your nodes will not be able to talk to the API server (e.g. Flux).')
param clusterAuthorizedIPRanges array = []

@description('AKS Service, Node Pool, and supporting services (KeyVault, App Gateway, etc) region.  The network team maintains this approved regional list which is a subset of zones with Availability Zone support.')
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
param location string = 'westus3'

param kubernetesVersion string = '1.28'

@description('the resource group name of the Azure Container Registry')
param acrResourceGroupName string

@description('the name of the delivery managed identity')
param deliveryIdName string

@description('the name of the drone scheduler managed identity')
param droneSchedulerIdName string

@description('the name of the workflow managed identity')
param workflowIdName string

@description('the name of the ingress controller managed identity')
param ingressControllerIdName string

@description('the name of the Azure Container Registry')
param acrName string

@description('Your cluster will be bootstrapped from this git repo.')
@minLength(9)
param gitOpsBootstrappingRepoHttpsUrl string = 'https://github.com/mspnp/aks-fabrikam-dronedelivery.git'

@description('You cluster will be bootstrapped from this branch in the identified git repo.')
@minLength(1)
param gitOpsBootstrappingRepoBranch string = 'main'

@allowed([
  'dev'
])
param environmentName string = 'dev'

var monitoringMetricsPublisherRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var managedIdentityOperatorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830')
var readerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var contributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, resourceGroup().id)
var clusterName = 'aks-${subRgUniqueString}'
var nodeResourceGroupName = 'MC_${resourceGroup().name}_${clusterName}_${location}'
var logAnalyticsWorkspaceName = 'la-${clusterName}'
var containerInsightsSolutionName = 'ContainerInsights(${logAnalyticsWorkspaceName})'
var vNetResourceGroup = split(targetVnetResourceId, '/')[4]
var vnetNodePoolSubnetResourceId = '${targetVnetResourceId}/subnets/snet-clusternodes'
var agwName = 'apw-${clusterName}'
var keyVaultName = 'kv-${clusterName}'
var nestedACRDeploymentName = 'azuredeploy-acr-${acrResourceGroupName}${environmentName}'
var environmentSettings = {
  dev: {
    acrName: acrName
  }
}

module nestedACRDeployment './nested_nestedACRDeployment.bicep' = {
  name: nestedACRDeploymentName
  scope: resourceGroup(acrResourceGroupName)
  params: {
    clusterIdentityObjectId: cluster.properties.identityProfile.kubeletidentity.objectId
    vNetResourceGroup: vNetResourceGroup
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
    acrName: acrName
    vnetNodePoolSubnetResourceId: vnetNodePoolSubnetResourceId
    location: location
  }
}

resource appwToKeyVaultmanagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'appw-to-keyvault'
  location: location
}

resource aksToKeyVaultManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'aksic-to-keyvault'
  location: location
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    accessPolicies: [
      {
        tenantId: appwToKeyVaultmanagedIdentity.properties.tenantId
        objectId: appwToKeyVaultmanagedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
          ]
          certificates: [
            'get'
          ]
        }
      }
      {
        tenantId: aksToKeyVaultManagedIdentity.properties.tenantId
        objectId: aksToKeyVaultManagedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
          ]
          certificates: [
            'get'
          ]
        }
      }
    ]
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
}

resource keyVaultMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: keyVault
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
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

resource nodepoolToAkvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'nodepool-to-akv'
  location: location
  properties: {
    subnet: {
      id: vnetNodePoolSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'nodepoolsubnet-to-akv'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource nodepoolToAkvPrivateEndpointDNSGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: nodepoolToAkvPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-akv-net'
        properties: {
          privateDnsZoneId: resourceId(vNetResourceGroup, 'Microsoft.Network/privateDnsZones', 'privatelink.vaultcore.azure.net')
        }
      }
    ]
  }
}

resource keyVaultNameSslcert 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'sslcert'
  properties: {
    value: appGatewayListenerCertificate
  }
}

resource keyVaultAppgwBackendpoolFabrikamComTls 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'appgw-backendpool-fabrikam-com-tls'
  properties: {
    value: aksIngressControllerCertificate
  }
}

resource agw 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: agwName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appwToKeyVaultmanagedIdentity.id}': {}
    }
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  tags: {}
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    sslPolicy: {
      policyType: 'Custom'
      cipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
      minProtocolVersion: 'TLSv1_2'
    }
    trustedRootCertificates: [
      {
        name: 'root-cert-wildcard-aks-ingress-fabrikam'
        properties: {
          keyVaultSecretId: '${keyVault.properties.vaultUri}secrets/appgw-backendpool-fabrikam-com-tls'
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'apw-ip-configuration'
        properties: {
          subnet: {
            id: '${targetVnetResourceId}/subnets/snet-applicationgateways'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'apw-frontend-ip-configuration'
        properties: {
          publicIPAddress: {
            id: resourceId(subscription().subscriptionId, vNetResourceGroup, 'Microsoft.Network/publicIpAddresses', 'pip-ShippingDroneDelivery-00')
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'apw-frontend-ports'
        properties: {
          port: 443
        }
      }
    ]
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.0'
    }
    enableHttp2: false
    sslCertificates: [
      {
        name: 'appgw-ssl-certificate'
        properties: {
          keyVaultSecretId: '${keyVault.properties.vaultUri}secrets/sslcert'
        }
      }
    ]
    probes: []
    backendAddressPools: [
      {
        name: 'aks-ingress.fabrikam.com'
        properties: {
          backendAddresses: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'aks-ingress-fabrikam-backendpool-httpsettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'listener-https'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', agwName, 'apw-frontend-ip-configuration')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', agwName, 'apw-frontend-ports')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', agwName, 'appgw-ssl-certificate')
          }
          hostName: 'dronedelivery.fabrikam.com'
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'apw-routing-rules'
        properties: {
          ruleType: 'Basic'
          priority: 1
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'listener-https')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'aks-ingress.fabrikam.com')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'aks-ingress-fabrikam-backendpool-httpsettings')
          }
        }
      }
    ]
  }
}

resource agwMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: agw
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
    ]
  }
}

module EnsureClusterSpHasRbacToVNet './nested_EnsureClusterSpHasRbacToVNet.bicep' = {
  name: 'EnsureClusterSpHasRbacToVNet'
  scope: resourceGroup(vNetResourceGroup)
  params: {
    clusterIdentityObjectId: cluster.properties.identityProfile.kubeletidentity.objectId
    targetVnetResourceId: targetVnetResourceId
    ingressControllerPrincipalId: cluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
  }
}

module EnsureClusterUserAssignedHasRbacToManageVMSS './nested_EnsureClusterUserAssignedHasRbacToManageVMSS.bicep' = {
  name: 'EnsureClusterUserAssignedHasRbacToManageVMSS'
  scope: resourceGroup(nodeResourceGroupName)
  params: {
    clusterIdentityObjectId: cluster.properties.identityProfile.kubeletidentity.objectId
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource logAnalyticsWorkspaceAllPrometheus 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'AllPrometheus'
  properties: {
    eTag: '*'
    category: 'Prometheus'
    displayName: 'All collected Prometheus information'
    query: 'InsightsMetrics | where Namespace == "prometheus"'
    version: 1
  }
}

resource logAnalyticsWorkspaceNameForbiddenReponsesOnIngress 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'ForbiddenReponsesOnIngress'
  properties: {
    eTag: '*'
    category: 'Prometheus'
    displayName: 'Increase number of forbidden response on the Ingress Controller'
    query: 'let value = toscalar(InsightsMetrics | where Namespace == "prometheus" and Name == "traefik_entrypoint_requests_total" | where parse_json(Tags).code == 403 | summarize Value = avg(Val) by bin(TimeGenerated, 5m) | summarize min = min(Value)); InsightsMetrics | where Namespace == "prometheus" and Name == "traefik_entrypoint_requests_total" | where parse_json(Tags).code == 403 | summarize AggregatedValue = avg(Val)-value by bin(TimeGenerated, 5m) | order by TimeGenerated | render barchart'
    version: 1
  }
}

resource logAnalyticsWorkspaceNameNodeRebootRequested 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'NodeRebootRequested'
  properties: {
    eTag: '*'
    category: 'Prometheus'
    displayName: 'Nodes reboot required by kured'
    query: 'InsightsMetrics | where Namespace == "prometheus" and Name == "kured_reboot_required" | where Val > 0'
    version: 1
  }
}

resource PodFailedScheduledQuery 'Microsoft.insights/scheduledQueryRules@2018-04-16' = {
  name: 'PodFailedScheduledQuery'
  location: location
  properties: {
    description: 'Alert on pod Failed phase.'
    enabled: 'true'
    source: {
      query: '//https://learn.microsoft.com/azure/azure-monitor/insights/container-insights-alerts \r\n let endDateTime = now(); let startDateTime = ago(1h); let trendBinSize = 1m; let clusterName = "${clusterName}"; KubePodInventory | where TimeGenerated < endDateTime | where TimeGenerated >= startDateTime | where ClusterName == clusterName | distinct ClusterName, TimeGenerated | summarize ClusterSnapshotCount = count() by bin(TimeGenerated, trendBinSize), ClusterName | join hint.strategy=broadcast ( KubePodInventory | where TimeGenerated < endDateTime | where TimeGenerated >= startDateTime | distinct ClusterName, Computer, PodUid, TimeGenerated, PodStatus | summarize TotalCount = count(), PendingCount = sumif(1, PodStatus =~ "Pending"), RunningCount = sumif(1, PodStatus =~ "Running"), SucceededCount = sumif(1, PodStatus =~ "Succeeded"), FailedCount = sumif(1, PodStatus =~ "Failed") by ClusterName, bin(TimeGenerated, trendBinSize) ) on ClusterName, TimeGenerated | extend UnknownCount = TotalCount - PendingCount - RunningCount - SucceededCount - FailedCount | project TimeGenerated, TotalCount = todouble(TotalCount) / ClusterSnapshotCount, PendingCount = todouble(PendingCount) / ClusterSnapshotCount, RunningCount = todouble(RunningCount) / ClusterSnapshotCount, SucceededCount = todouble(SucceededCount) / ClusterSnapshotCount, FailedCount = todouble(FailedCount) / ClusterSnapshotCount, UnknownCount = todouble(UnknownCount) / ClusterSnapshotCount| summarize AggregatedValue = avg(FailedCount) by bin(TimeGenerated, trendBinSize)'
      dataSourceId: logAnalyticsWorkspace.id
      queryType: 'ResultCount'
    }
    schedule: {
      frequencyInMinutes: 5
      timeWindowInMinutes: 10
    }
    action: {
      'odata.type': 'Microsoft.WindowsAzure.Management.Monitoring.Alerts.Models.Microsoft.AppInsights.Nexus.DataContracts.Resources.ScheduledQueryRules.AlertingAction'
      severity: '3'
      trigger: {
        thresholdOperator: 'GreaterThan'
        threshold: 3
        metricTrigger: {
          thresholdOperator: 'GreaterThan'
          threshold: 2
          metricTriggerType: 'Consecutive'
        }
      }
    }
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource AllAzureAdvisorAlert 'Microsoft.insights/activityLogAlerts@2017-04-01' = {
  name: 'AllAzureAdvisorAlert'
  location: 'Global'
  properties: {
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Recommendation'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Advisor/recommendations/available/action'
        }
      ]
    }
    actions: {
      actionGroups: []
    }
    enabled: true
    description: 'All azure advisor alerts'
  }
}

resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: containerInsightsSolutionName
  location: location
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: containerInsightsSolutionName
    product: 'OMSGallery/ContainerInsights'
    promotionCode: ''
    publisher: 'Microsoft'
  }
  dependsOn: []
}

resource cluster 'Microsoft.ContainerService/managedClusters@2023-07-02-preview' = {
  name: clusterName
  location: location
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: uniqueString(subscription().subscriptionId, resourceGroup().id, clusterName)
    agentPoolProfiles: [
      {
        name: 'npsystem'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 80
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        minCount: 3
        maxCount: 4
        vnetSubnetID: vnetNodePoolSubnetResourceId
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        scaleSetPriority: 'Regular'
        scaleSetEvictionPolicy: 'Delete'
        orchestratorVersion: kubernetesVersion
        enableNodePublicIP: false
        maxPods: 30
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
      {
        name: 'npuser01'
        count: 2
        vmSize: 'Standard_DS3_v2'
        osDiskSizeGB: 120
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        minCount: 2
        maxCount: 5
        vnetSubnetID: vnetNodePoolSubnetResourceId
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        mode: 'User'
        scaleSetPriority: 'Regular'
        scaleSetEvictionPolicy: 'Delete'
        orchestratorVersion: kubernetesVersion
        enableNodePublicIP: false
        maxPods: 30
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
    ]
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      httpApplicationRouting: {
        enabled: false
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.id
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'false'
        }
      }
      aciConnectorLinux: {
        enabled: false
      }
      azurepolicy: {
        enabled: true
        config: {
          version: 'v2'
        }
      }
      ingressApplicationGateway: {
        config: {
          applicationGatewayId: agw.id
        }
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    podIdentityProfile: {
      enabled: false
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    nodeResourceGroup: nodeResourceGroupName
    enableRBAC: true
    enablePodSecurityPolicy: false
    maxAgentPools: 2
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      outboundType: 'userDefinedRouting'
      loadBalancerSku: 'standard'
      loadBalancerProfile: null
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
      dockerBridgeCidr: '172.18.0.1/16'
    }
    aadProfile: {
      managed: true
      adminGroupObjectIDs: [
        k8sRbacEntraAdminGroupObjectID
      ]
      tenantID: k8sRbacEntraProfileTenantId
    }
    autoScalerProfile: {
      'scan-interval': '10s'
      'scale-down-delay-after-add': '10m'
      'scale-down-delay-after-delete': '20s'
      'scale-down-delay-after-failure': '3m'
      'scale-down-unneeded-time': '10m'
      'scale-down-unready-time': '20m'
      'scale-down-utilization-threshold': '0.5'
      'max-graceful-termination-sec': '600'
      'balance-similar-node-groups': 'false'
      expander: 'random'
      'skip-nodes-with-local-storage': 'true'
      'skip-nodes-with-system-pods': 'true'
      'max-empty-bulk-delete': '10'
      'max-total-unready-percentage': '45'
      'ok-total-unready-count': '3'
    }
    apiServerAccessProfile: {
      authorizedIPRanges: clusterAuthorizedIPRanges
      enablePrivateCluster: false
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource clusterMicrosoftInsightsDefault 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: cluster
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-audit-admin'
        enabled: true
      }
      {
        category: 'guard'
        enabled: true
      }
    ]
  }
}

resource NodeCPUUtilizationHighForClusterNameCI1 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Node CPU utilization high for ${clusterName} CI-1'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'cpuUsagePercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node CPU utilization across the cluster.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource NodeWorkingSetMemoryUtilizationHighForClusterNameCI2 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Node working set memory utilization high for ${clusterName} CI-2'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'memoryWorkingSetPercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node working set memory utilization across the cluster.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource JobsCompletedMoreThan6HoursAgoForClusterNameCI11 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Jobs completed more than 6 hours ago for ${clusterName} CI-11'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'completedJobsCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors completed jobs (more than 6 hours ago).'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT1M'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource ContainerCPUsageHighForClusterNameCI9 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Container CPU usage high for ${clusterName} CI-9'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'cpuExceededPercentage'
          metricNamespace: 'Insights.Container/containers'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors container CPU utilization.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource ContainerWorkingSetMemoryUsageHighForClusterNameCI10 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Container working set memory usage high for ${clusterName} CI-10'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'memoryWorkingSetExceededPercentage'
          metricNamespace: 'Insights.Container/containers'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors container working set memory utilization.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource PodsInFailedStateForClusterNameCI4 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Pods in failed state for ${clusterName} CI-4'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'phase'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
          metricName: 'podCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Pod status monitoring.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource DiskUsageHighForClusterNameCI5 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Disk usage high for ${clusterName} CI-5'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'host'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'device'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'DiskUsedPercentage'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors disk usage for all nodes and storage devices.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource NodesInNotReadyStatusForClusterNameCI3 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Nodes in not ready status for ${clusterName} CI-3'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'status'
              operator: 'Include'
              values: [
                'NotReady'
              ]
            }
          ]
          metricName: 'nodesCount'
          metricNamespace: 'Insights.Container/nodes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'Node status monitoring.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource ContainersGettingOOMKilledForClusterNameCI6 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Containers getting OOM killed for ${clusterName} CI-6'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'oomKilledContainerCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors number of containers killed due to out of memory (OOM) error.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT1M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource PersistentVolumeUsageHighForClusterNameCI18 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Persistent volume usage high for ${clusterName} CI-18'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'podName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetesNamespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'pvUsageExceededPercentage'
          metricNamespace: 'Insights.Container/persistentvolumes'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors persistent volume utilization.'
    enabled: false
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource PodsNotInReadyStateForClusterNameCI8 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Pods not in ready state for ${clusterName} CI-8'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'PodReadyPercentage'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'LessThan'
          threshold: 80
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors for excessive pods not in the ready state.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'microsoft.containerservice/managedclusters'
    windowSize: 'PT5M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource RestartingContainerCountForClusterNameCI7 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  location: 'global'
  name: 'Restarting container count for ${clusterName} CI-7'
  properties: {
    actions: []
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'kubernetes namespace'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'controllerName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          metricName: 'restartingContainerCount'
          metricNamespace: 'Insights.Container/pods'
          name: 'Metric1'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          skipMetricValidation: true
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    description: 'This alert monitors number of containers restarting across the cluster.'
    enabled: true
    evaluationFrequency: 'PT1M'
    scopes: [
      cluster.id
    ]
    severity: 3
    targetResourceType: 'Microsoft.ContainerService/managedClusters'
    windowSize: 'PT1M'
  }
  dependsOn: [
    containerInsightsSolution
  ]
}

resource clusterMicrosoftAuthorizationKubeletMonitoringMetricsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cluster
  name: guid(resourceGroup().id, clusterName, 'kubelet', monitoringMetricsPublisherRole)
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [

    containerInsightsSolution
  ]
}

resource clusterMicrosoftAuthorizationOmsagentMonitoringMetricsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cluster
  name: guid(resourceGroup().id, clusterName, 'omsagent', monitoringMetricsPublisherRole)
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRole
    principalId: cluster.properties.addonProfiles.omsagent.identity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource aksToKeyvaultMicrosoftAuthorizationManagedIdentityOperatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aksToKeyVaultManagedIdentity
  name: guid(concat(resourceGroup().id), managedIdentityOperatorRole)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource appwToKeyvaultMicrosoftAuthorizationManagedIdentityOperatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appwToKeyVaultmanagedIdentity
  name: guid('${resourceGroup().id}appw-to-keyvault', managedIdentityOperatorRole)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultMicrosoftAuthorizationReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid('aksic-to-keyvault${resourceGroup().id}', readerRole)
  properties: {
    roleDefinitionId: readerRole
    principalId: aksToKeyVaultManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource _42b8ef37_b724_4e24_bbc8_7a7708edfe00PolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('42b8ef37-b724-4e24-bbc8-7a7708edfe00', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policySetDefinitions/42b8ef37-b724-4e24-bbc8-7a7708edfe00', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policySetDefinitions/42b8ef37-b724-4e24-bbc8-7a7708edfe00'
    parameters: {
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'audit'
      }
    }
  }
}

resource _1a5b4dca_0b6f_4cf5_907c_56316bc1bf3dPolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('1a5b4dca-0b6f-4cf5-907c-56316bc1bf3d', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policyDefinitions/1a5b4dca-0b6f-4cf5-907c-56316bc1bf3d', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/1a5b4dca-0b6f-4cf5-907c-56316bc1bf3d'
    parameters: {
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'deny'
      }
    }
  }
}

resource _3fc4dc25_5baf_40d8_9b05_7fe74c1bc64ePolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('3fc4dc25-5baf-40d8-9b05-7fe74c1bc64e', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policyDefinitions/3fc4dc25-5baf-40d8-9b05-7fe74c1bc64e', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/3fc4dc25-5baf-40d8-9b05-7fe74c1bc64e'
    parameters: {
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'deny'
      }
    }
  }
}

resource df49d893_a74c_421d_bc95_c663042e5b80PolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('df49d893-a74c-421d-bc95-c663042e5b80', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policyDefinitions/df49d893-a74c-421d-bc95-c663042e5b80', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/df49d893-a74c-421d-bc95-c663042e5b80'
    parameters: {
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'audit'
      }
    }
  }
}

resource e345eecc_fa47_480f_9e88_67dcc122b164PolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('e345eecc-fa47-480f-9e88-67dcc122b164', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policyDefinitions/e345eecc-fa47-480f-9e88-67dcc122b164', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/e345eecc-fa47-480f-9e88-67dcc122b164'
    parameters: {
      cpuLimit: {
        value: '1000m'
      }
      memoryLimit: {
        value: '1024Mi'
      }
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'deny'
      }
    }
  }
}

resource febd0533_8e55_448f_b837_bd0e06f16469PolicyAssigment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('febd0533-8e55-448f-b837-bd0e06f16469', resourceGroup().name, clusterName)
  properties: {
    displayName: '[${clusterName}] ${reference('/providers/Microsoft.Authorization/policyDefinitions/febd0533-8e55-448f-b837-bd0e06f16469', '2020-09-01').displayName}'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/febd0533-8e55-448f-b837-bd0e06f16469'
    parameters: {
      allowedContainerImagesRegex: {
        value: '${environmentSettings[environmentName].acrName}.azurecr.io/.+$|mcr.microsoft.com/.+$|registry.hub.docker.com/library/.+$'
      }
      excludedNamespaces: {
        value: [
          'kube-system'
          'gatekeeper-system'
          'azure-arc'
          'cluster-baseline-settings'
          'flux-system'
        ]
      }
      effect: {
        value: 'deny'
      }
    }
  }
}

resource deliveryId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: deliveryIdName
}

resource deliveryIdentityOperatorRoleAssigment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: deliveryId
  name: guid('${deliveryIdName}${environmentName}', resourceGroup().id)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource workflowId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: workflowIdName
}

resource workflowIdentityOperatorRoleAssigment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: workflowId
  name: guid('${workflowIdName}${environmentName}', resourceGroup().id)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource droneSchedulerId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: droneSchedulerIdName
}

resource droneSchedulerIdentityOperatorRoleAssigment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${droneSchedulerIdName}${environmentName}')
  scope: droneSchedulerId
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource ingestionId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: ingressControllerIdName
}

resource ingestionIdentityOperatorRoleAssigment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ingestionId
  name: guid('${ingressControllerIdName}${environmentName}', resourceGroup().id)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource ingestionIdentityApwOperatorRoleAssigment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ingestionId
  name: guid('${ingressControllerIdName}Apw${environmentName}', resourceGroup().id)
  properties: {
    roleDefinitionId: managedIdentityOperatorRole
    principalId: cluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource agwMicrosoftAuthorizationContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: agw
  name: guid('${ingressControllerIdName}appgateway', resourceGroup().id, environmentName)
  properties: {
    roleDefinitionId: contributorRole
    principalId: cluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
  }
}

resource ingressControllerIdName_resourcegroup_environmentName_id 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${ingressControllerIdName}resourcegroup${environmentName}', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: readerRole
    principalId: cluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
  }
}


// Ensures that flux add-on (extension) is installed.
resource clusterFluxExtension 'Microsoft.KubernetesConfiguration/extensions@2021-09-01' = {
  scope: cluster
  name: 'flux'
  properties: {
    extensionType: 'microsoft.flux'
    autoUpgradeMinorVersion: true
    releaseTrain: 'Stable'
    scope: {
      cluster: {
        releaseNamespace: 'flux-system'
      }
    }
    configurationSettings: {
      'helm-controller.enabled': 'false'
      'source-controller.enabled': 'true'
      'kustomize-controller.enabled': 'true'
      'notification-controller.enabled': 'true'  // As of testing on 29-Dec, this is required to avoid an error.  Normally it's not a required controller. YMMV
      'image-automation-controller.enabled': 'false'
      'image-reflector-controller.enabled': 'false'
    }
    configurationProtectedSettings: {}
  }
  dependsOn: [
    nestedACRDeployment
  ]
}

// Bootstraps your cluster using content from your repo.
resource clusterfluxConfiguration 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-03-01' = {
  scope: cluster
  name: 'bootstrap'
  properties: {
    scope: 'cluster'
    namespace: 'flux-system'
    sourceKind: 'GitRepository'
    gitRepository: {
      url: gitOpsBootstrappingRepoHttpsUrl
      timeoutInSeconds: 180
      syncIntervalInSeconds: 300
      repositoryRef: {
        branch: gitOpsBootstrappingRepoBranch
        tag: null
        semver: null
        commit: null
      }
      sshKnownHosts: ''
      httpsUser: null
      httpsCACert: null
      localAuthRef: null
    }
    kustomizations: {
      unified: {
        path: './cluster-manifests'
        dependsOn: []
        timeoutInSeconds: 300
        syncIntervalInSeconds: 300
        retryIntervalInSeconds: 300
        prune: true
        force: false
      }
    }
  }
  dependsOn: [
    clusterFluxExtension
    nestedACRDeployment
  ]
}

output acrName string = environmentSettings[environmentName].acrName
output aksClusterName string = clusterName
output agwName string = agwName
output aksIngressControllerUserManageIdentityResourceId string = aksToKeyVaultManagedIdentity.id
output aksIngressControllerUserManageIdentityClientId string = aksToKeyVaultManagedIdentity.properties.clientId
output keyVaultName string = keyVaultName
output containerRegistryName string = environmentSettings[environmentName].acrName
output deliveryPrincipalResourceId string = '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${deliveryIdName}'
output workflowPrincipalResourceId string = '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${workflowIdName}'
output droneSchedulerPrincipalResourceId string = '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${droneSchedulerIdName}'
