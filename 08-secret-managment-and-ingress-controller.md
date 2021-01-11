# Configure AKS Ingress Controller with Azure Key Vault integration

Previously you have configured [workload prerequisites](./07-workload-prerequisites.md). These steps configure Azure Application Gateway Ingress Controller (AGIC), as the AKS ingress solution used by this reference implementation, so that it can securely expose the web app to your Application Gateway.

## Steps

1. Create the Ingress Controller's Secret Provider Class resource

   > The Ingress Controller will be exposing the wildcard TLS certificate you created in a prior step. It uses the Azure Key Vault CSI Provider to mount the certificate which is managed and stored in Azure Key Vault. Once mounted, Traefik can use it.
   >
   > Create a `SecretProviderClass` resource with with your Azure Key Vault parameters for the [Azure Key Vault Provider for Secrets Store CSI driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure).

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
   kind: SecretProviderClass
   metadata:
     name: aks-internal-ingress-controller-tls-secret-csi-akv
     namespace: backend-dev
   spec:
     provider: azure
     parameters:
       usePodIdentity: "true"
       keyvaultName: "${KEYVAULT_NAME}"
       objects:  |
         array:
           - |
             objectName: aks-internal-ingress-controller-tls
             objectAlias: tls.crt
             objectType: cert
           - |
             objectName: aks-internal-ingress-controller-tls
             objectAlias: tls.key
             objectType: secret
       tenantId: "${TENANT_ID}"
   EOF
   ```

1. Obtain all the identity info to install Azure App Gateway Ingress Controller

   > :book: the app team wants to use Azure AD Pod Identity to assign an identity to its ingress controller pod, so they will need to obtain indentity information such us the user managed identity resource id and client id for the ingress controller created as part of the cluster pre requisites. This way when installing Azure Application Gateway Ingress Controller they can provide such information to create the Kubernetes Azure Identity objects.

   ```bash
   INGRESS_CONTROLLER_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.appGatewayControllerPrincipalResourceId.value -o tsv)
   INGRESS_CONTROLLER_PRINCIPAL_CLIENT_ID=$(az identity show --ids $INGRESS_CONTROLLER_PRINCIPAL_RESOURCE_ID --query clientId -o tsv)
   ```
1. Get the Name of Application Gateway

   > :book: The app team needs to wire up the in-cluster AGIC with Application Gateway and that requires the Azure Application Gateway name.

   ```bash
   APPGW_NAME=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.agwName.value -o tsv)
   ```

1. Install the Azure App Gateway Ingress Controller

   > :book: The Fabrikam Drone Delivery app's team has made the decision of having an externalized ingress controller, since the team wants to simplify the ingestion of traffic into the AKS cluster, keep it safe, improve the performance, and save resources. The selected solution in this case was the Azure App Gateway Ingress Controller. This eliminates the necessity of an extra load balancer since pods will establish direct connections against their Azure App Gateway service reducing the number of hops which results in better performance. The traffic is now being handle exclusively by Azure Application Gateway that has built-in capabilities for auto-scaling, and the Fabrikam Drone Delivery workload pods without the necessity of scaling out any other component in the middle as it will be the case compared against any other in-cluster ingress controller solutions that ends up consuming added resources from the AKS cluster. Additionally, Azure Application Gateway has end-to-end TLS integrated with a web aplication firewall in front.

   ```bash
   helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
   helm repo update

   helm install ingress-azure-dev application-gateway-kubernetes-ingress/ingress-azure \
     --namespace kube-system \
     --set appgw.name=$APPGW_NAME \
     --set appgw.resourceGroup=rg-shipping-dronedelivery \
     --set appgw.subscriptionId=$(az account show --query id --output tsv) \
     --set appgw.shared=false \
     --set kubernetes.watchNamespace=backend-dev \
     --set armAuth.type=aadPodIdentity \
     --set armAuth.identityResourceID=$INGRESS_CONTROLLER_PRINCIPAL_RESOURCE_ID \
     --set armAuth.identityClientID=$INGRESS_CONTROLLER_PRINCIPAL_CLIENT_ID \
     --set rbac.enabled=true \
     --set verbosityLevel=3 \
     --set aksClusterConfiguration.apiServerAddress=$(az aks show -n $AKS_CLUSTER_NAME -g rg-shipping-dronedelivery --query fqdn -o tsv) \
     --set appgw.usePrivateIP=false \
     --version 1.3.0
   ```

1. Wait for AGIC to be ready

   ```bash
   kubectl wait --namespace kube-system --for=condition=ready pod --selector=release=ingress-azure-dev --timeout=90s
   ```

   > :warning: Once you deploy the Azure Application Gateway Ingress Controller it turns your Azure Application Gateway instance into a managed service and by default the ingress controller will assume full ownership. In other words, AGIC is going to attempt to alter the Azure Application Gateway it is linked to by writing rules based on your cluster configuration. The ARM template for the cluster stamp in this project has been designed to be executed as many times as needed. Therefore if the ARM template is redeployed all the AGIC-written rules will be removed removed. In this scenario, please take into account that it requires a manual intervention to reconcile the rules in your Azure Application Gateway by causing downtimes. Additionally, it is not possible to share an Azure Application Gateway between multiple clusters or different Azure services with the default configuration provided in this reference implementation, otherwise it might end up with race conditions or unexpected behaviors. For more information, please take a look at [Agic reconcile](https://azure.github.io/application-gateway-kubernetes-ingress/features/agic-reconcile/) and [Multi-cluster / Shared App Gateway](https://github.com/Azure/application-gateway-kubernetes-ingress/blob/master/docs/setup/install-existing.md#multi-cluster--shared-app-gateway).
### Next step

:arrow_forward: [Deploy the Workload](./09-workload.md)
