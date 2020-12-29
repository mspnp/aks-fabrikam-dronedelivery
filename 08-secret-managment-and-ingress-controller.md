# Configure AKS Ingress Controller with Azure Key Vault integration

Previously you have configured [workload prerequisites](./07-workload-prerequisites.md). These steps configure Traefik and AGIC, as the AKS ingress solutions used in this reference implementation, so that it can securely expose the web app to your Application Gateway.

## Steps

1. Get the AKS Ingress Controller Managed Identity details

   ```bash
   export TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.aksIngressControllerUserManageIdentityResourceId.value -o tsv)
   export TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.aksIngressControllerUserManageIdentityClientId.value -o tsv)
   ```

1. Ensure Flux has created the following namespace

   ```bash
   # press Ctrl-C once you receive a successful response
   kubectl get ns a0008 -w
   ```

1. Create Traefik's Azure Managed Identity binding

   > Create the Traefik Azure Identity and the Azure Identity Binding to let Azure Active Directory Pod Identity to get tokens on behalf of the Traefik's User Assigned Identity and later on assign them to the Traefik's pod.

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: "aadpodidentity.k8s.io/v1"
   kind: AzureIdentity
   metadata:
     name: aksic-to-keyvault-identity
     namespace: a0008
   spec:
     type: 0
     resourceID: $TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID
     clientID: $TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID
   ---
   apiVersion: "aadpodidentity.k8s.io/v1"
   kind: AzureIdentityBinding
   metadata:
     name: aksic-to-keyvault-identity-binding
     namespace: a0008
   spec:
     azureIdentity: aksic-to-keyvault-identity
     selector: traefik-ingress-controller
   EOF
   ```

1. Create the Traefik's Secret Provider Class resource

   > The Ingress Controller will be exposing the wildcard TLS certificate you created in a prior step. It uses the Azure Key Vault CSI Provider to mount the certificate which is managed and stored in Azure Key Vault. Once mounted, Traefik can use it.
   >
   > Create a `SecretProviderClass` resource with with your Azure Key Vault parameters for the [Azure Key Vault Provider for Secrets Store CSI driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure).

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
   kind: SecretProviderClass
   metadata:
     name: aks-internal-ingress-controller-tls-secret-csi-akv
     namespace: a0008
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

1. Import the Traefik container image to your container registry

   > Public container registries are subject to faults such as outages (no SLA) or request throttling. Interruptions like these can be crippling for an application that needs to pull an image _right now_. To minimize the risks of using public registries, store all applicable container images in a registry that you control, such as the SLA-backed Azure Container Registry.

   ```bash
   # Get your ACR cluster name
   export ACR_NAME=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.containerRegistryName.value -o tsv)

   # Import ingress controller image hosted in public container registries
   az acr import --source docker.io/library/traefik:2.2.1 -n $ACR_NAME
   ```

1. Install the Traefik Ingress Controller

   > Install the Traefik Ingress Controller; it will use the mounted TLS certificate provided by the CSI driver, which is the in-cluster secret management solution.

   > If you used your own fork of this GitHub repo, update the one `image:` value in [`traefik.yaml`](./workload/traefik.yaml) to reference your container registry instead of the default public container registry and change the URL below to point to yours as well.

   :warning: Deploying the traefik `traefik.yaml` file unmodified from this repo will be deploying your workload to take dependencies on a public container registry. This is generally okay for learning/testing, but not suitable for production. Before going to production, ensure _all_ image references are from _your_ container registry or another that you feel confident relying on.

   ```bash
   kubectl apply -f https://raw.githubusercontent.com/mspnp/aks-fabrikam-dronedelivery/main/workload/traefik.yaml
   ```

1. Wait for Traefik to be ready

   > During Traefik's pod creation process, AAD Pod Identity will need to retrieve token for Azure Key Vault. This process can take time to complete and it's possible for the pod volume mount to fail during this time but the volume mount will eventually succeed. For more information, please refer to the [Pod Identity documentation](https://github.com/Azure/secrets-store-csi-driver-provider-azure/blob/master/docs/pod-identity-mode.md).

   ```bash
   kubectl wait --namespace a0008 --for=condition=ready pod --selector=app.kubernetes.io/name=traefik-ingress-ilb --timeout=90s
   ```

1. Obtain all the identity info to install Azure App Gateway Ingress Controller

   > :book: the app team wants to use Azure AD Pod Identity to authenticate its
   > ingress controller pod so they will need to obtain indentity information such us the
   > user managed identity resource id and client id for the ingress controller created as part of the cluster pre requisites.
   > This way when installing Azure Application Gateway Ingress Controller they can provide such information to create the Kubernetes Azure Identity objects.

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

   > :book: The Fabrikam Drone Delivery app's team has made the decision of having a
   > separated ingress controller, since the team wants to simplify the
   > ingestion of traffic into the AKS cluster, keep it safe, improve the performance, and save resources.
   > The selected solution in this case was the Azure App Gateway
   > Ingress Controller. This eliminates the necessity of an extra load
   > balancer since pods will establish direct connections against their Azure App Gateway service
   > reducing the number of hops which results in better performance.
   > The traffic is now being handle exclusively by Azure
   > Application Gateway that has built-in capabilities for auto-scaling, and the Fabrikam Drone Delivery workload pods without
   > the necessity of scaling out any other component in the middle as it will
   > be the case compared against any other popular ingress controller solutions that ends up
   > consuming resources from the AKS cluster. Additionally, Azure App Gateway has
   > End-to-end TLS integrated with a web aplication firewall in front.

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
     --version 1.2.1
   ```

1. Wait for AGIC to be ready

   ```bash
   kubectl wait --namespace kube-system --for=condition=ready pod --selector=release=ingress-azure-dev --timeout=90s
   ```

### Next step

:arrow_forward: [Deploy the Workload](./09-workload.md)
