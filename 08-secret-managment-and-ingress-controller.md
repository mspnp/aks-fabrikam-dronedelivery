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

1. Obtain the identity info needed for installing the Azure App Gateway Ingress Controller.

   > :book: The app team wants to use Azure AD Pod Identity to assign an identity to its ingress controller pod. They will need to obtain identity information such as the user-managed identity resource id and client id for the ingress controller created as part of the cluster prerequisites. When installing the Azure Application Gateway ingress controller, they can provide such information to create the Kubernetes Azure Identity objects.

   ```bash
   INGRESS_CONTROLLER_PRINCIPAL_RESOURCE_ID=$(az deployment group show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.appGatewayControllerPrincipalResourceId.value -o tsv)
   INGRESS_CONTROLLER_PRINCIPAL_CLIENT_ID=$(az identity show --ids $INGRESS_CONTROLLER_PRINCIPAL_RESOURCE_ID --query clientId -o tsv)
   ```
1. Get the Name of Application Gateway

   > :book: The app team needs to connect the in-cluster Application gateway ingress controller with the Azure Application Gateway instance, which requires the Azure Application Gateway name.

   ```bash
   APPGW_NAME=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.agwName.value -o tsv)
   ```

1. Install the Azure App Gateway Ingress Controller.

   > :book: The Fabrikam Drone Delivery app's team has decided to use an externalized ingress controller. This configuration allows the team to simplify traffic ingestion, keep it safe, improve performance, and better utilize cluster resources. The selected solution is to use an Azure App Gateway Ingress Controller. This solution eliminates the necessity of an extra load balancer.  Pods establish direct connections with the Azure App Gateway service, reducing the number of network hops,  resulting in better performance. The traffic is now handled exclusively by Azure Application Gateway, which has native capabilities for auto-scaling workload pods without the necessity of scaling out any other component, as is the case with an in-cluster ingress controller. Additionally, Azure Application Gateway has end-to-end TLS integrated with a web application firewall in front.

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

1. Wait for Application Gateway Ingress Controller to be ready.

   ```bash
   kubectl wait --namespace kube-system --for=condition=ready pod --selector=release=ingress-azure-dev --timeout=90s
   ```

   > :warning: Once deployed, the Azure Application Gateway Ingress Controller manages the Azure Application Gateway instance. Application Gateway Ingress Controller updates the Azure Application Gateway it is linked to by writing rules based on your cluster configuration. The ARM template used to deploy the cluster is designed to be executed as many times as needed. If the ARM template is redeployed, all the AGIC-written rules are removed. In this scenario, please consider that it requires a manual intervention to reconcile the rules in your Azure Application Gateway by causing downtimes. Additionally, it is impossible to share an Azure Application Gateway between multiple clusters or different Azure services with the default configuration provided in this reference implementation; otherwise, it might end up with race conditions or unexpected behaviors. For more information, please take a look at [Agic reconcile](https://azure.github.io/application-gateway-kubernetes-ingress/features/agic-reconcile/) and [Multi-cluster / Shared App Gateway](https://github.com/Azure/application-gateway-kubernetes-ingress/blob/master/docs/setup/install-existing.md#multi-cluster--shared-app-gateway).

### Next step

:arrow_forward: [Deploy the Workload](./09-workload.md)
