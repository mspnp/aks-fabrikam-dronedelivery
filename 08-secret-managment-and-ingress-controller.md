# Configure AKS Ingress Controller with Azure Key Vault integration

Previously you configured [workload prerequisites](./07-workload-prerequisites.md). This reference implementation uses Azure Application Gateway Ingress Controller (AGIC) as the AKS ingress solution. The following steps will guide you in configuring AGIC to securely expose the web app to your Application Gateway. AGIC is included as an AKS addon.

## Steps


1. Wait for Application Gateway Ingress Controller to be ready.

   ```bash
   kubectl wait --namespace kube-system --for=condition=ready pod --selector=app=ingress-appgw --timeout=90s
   ```

   > :warning: Once deployed, the Azure Application Gateway Ingress Controller manages the Azure Application Gateway instance. Application Gateway Ingress Controller updates the Azure Application Gateway it is linked to by writing rules based on your cluster configuration. The Bicep template used to deploy the cluster is designed to be executed as many times as needed. If the Bicep template is redeployed, all the AGIC-written rules are removed. In this scenario, please consider that it requires a manual intervention to reconcile the rules in your Azure Application Gateway by causing downtimes. Additionally, it is impossible to share an Azure Application Gateway between multiple clusters or different Azure services with the default configuration provided in this reference implementation; otherwise, it might end up with race conditions or unexpected behaviors. For more information, please take a look at [Agic reconcile](https://azure.github.io/application-gateway-kubernetes-ingress/features/agic-reconcile/) and [Multi-cluster / Shared App Gateway](https://github.com/Azure/application-gateway-kubernetes-ingress/blob/master/docs/setup/install-existing.md#multi-cluster--shared-app-gateway).

### Next step

:arrow_forward: [Deploy the Workload](./09-workload.md)
