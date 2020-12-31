 # Deploy Workload (Fabrikam Drone Delivery Shipping app)

The cluster now has an [Azure Application Gateway Ingress Controller configured with a SSL certificate pre-installed integrated with Azure Key Vault](./08-secret-managment-and-ingress-controller.md). The last step in the process is to deploy the workload, which will demonstrate the system's functions and install the Fabrikam Drone Delivery app.

## Steps

> :book: The Fabrikam Drone Delivery app team is about to conclude this journey, but they need an app to test their new infrastructure. For this task they've picked out the formerly known [Microservices Reference Implementation](https://github.com/mspnp/microservices-reference-implementation). From now on, the Fabrikam Drone Delivery Shipping application is a sample application that consists of several microservices. Because it's a sample, the functionality is simulated, but the APIs and microservices interactions are intended to reflect real-world design patterns.
>
>  - Ingestion service. Receives client requests and buffers them.
>  - Workflow service. Dispatches client requests and manages the delivery workflow.
>  - Delivery service. Manages deliveries that are scheduled or in-transit.
>  - Package service. Manages packages.
>  - Drone service. Schedules drones and monitors drones in flight.
>
> The Fabrikam Drone Delivery app team is about to deploy all the microservices
> into the AKS cluster. They all are going to be deployed in the same way,
> it will require to build their Docker images, collect values like Azure service names or any
> other kind of information, and deploy the app using Helm.

![](./architecture.png)

1. Get the Azure Container Registry server name

   ```bash
   ACR_NAME=$(az deployment group show --resource-group rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.acrName.value -o tsv)
   ACR_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
   ```

1. Set the AKS cluster and Application Gateway subnet prefixes

   :book: The Fabrikan Drone Delivery application follow the zero trust principle when establishing network connections between containers. Initially any container is allowed to establish a connection against another one. The following information is required to create ALLOW Network Policies.

   ```bash
   CLUSTER_SUBNET_PREFIX="10.240.0.0/22"
   GATEWAY_SUBNET_PREFIX="10.240.4.16/28"
   ```

1. Get the Azure Application Insights settings

   ```bash
   export AI_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.appInsightsName.value -o tsv)
   export AI_IKEY=$(az resource show -g rg-shipping-dronedelivery -n $AI_NAME --resource-type "Microsoft.Insights/components" --query properties.InstrumentationKey -o tsv)
   ```

1. Enable the public access to your ACR temporary

   :bulb: The configured network access to the registry is limited to certain
   networks. In the following steps you are going to need access from your local
   machine to the ACR instace, so you can upload the Fabrikam Drone Delivery
   Docker images to it.

   ```bash
   az acr update --name $ACR_NAME --public-network-enabled true
   ```

1. Deploy the Delivery service app

   Build the Delivery service

   ```bash
   docker build --pull --compress -t $ACR_SERVER/delivery:0.1.0 ./src/shipping/delivery/.
   ```

   Push the image to ACR

   ```bash
   az acr login --name $ACR_NAME
   docker push $ACR_SERVER/delivery:0.1.0
   ```

   Extract Azure resource details for the delivery app

   ```bash
   DELIVERY_ID_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.deliveryIdName.value -o tsv)
   DELIVERY_KEYVAULT_URI=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.deliveryKeyVaultUri.value -o tsv)
   DELIVERY_COSMOSDB_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.deliveryCosmosDbName.value -o tsv)
   DELIVERY_DATABASE_NAME="${DELIVERY_COSMOSDB_NAME}-db"
   DELIVERY_COLLECTION_NAME="${DELIVERY_COSMOSDB_NAME}-col"
   DELIVERY_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.deliveryPrincipalResourceId.value -o tsv)
   DELIVERY_PRINCIPAL_CLIENT_ID=$(az identity show -g rg-shipping-dronedelivery -n $DELIVERY_ID_NAME --query clientId -o tsv)
   ```

   Deploy the Delivery service

   ```bash
   helm package ./charts/delivery/ -u
   helm install delivery-v0.1.0-dev delivery-v0.1.0.tgz \
        --set image.tag=0.1.0 \
        --set image.repository=delivery \
        --set dockerregistry=$ACR_SERVER \
        --set ingress.hosts[0].name=dronedelivery.fabrikam.com \
        --set ingress.hosts[0].serviceName=delivery \
        --set networkPolicy.egress.external.enabled=true \
        --set networkPolicy.egress.external.clusterSubnetPrefix=$CLUSTER_SUBNET_PREFIX \
        --set networkPolicy.ingress.externalSubnet.enabled=true \
        --set networkPolicy.ingress.externalSubnet.subnetPrefix=$GATEWAY_SUBNET_PREFIX \
        --set identity.clientid=$DELIVERY_PRINCIPAL_CLIENT_ID \
        --set identity.resourceid=$DELIVERY_PRINCIPAL_RESOURCE_ID \
        --set cosmosdb.id=$DELIVERY_DATABASE_NAME \
        --set cosmosdb.collectionid=$DELIVERY_COLLECTION_NAME \
        --set keyvault.uri=$DELIVERY_KEYVAULT_URI \
        --set reason="Initial deployment" \
        --set envs.dev=true \
        --namespace backend-dev
   ```

   Verify the pod is created

   ```bash
   kubectl wait --namespace backend-dev --for=condition=ready pod --selector=app.kubernetes.io/name=delivery-v0.1.0-dev --timeout=90s
   ```
1. Deploy the Ingestion service app

   Build the Ingestion service

   ```bash
   docker build --pull --compress -t $ACR_SERVER/ingestion:0.1.0 ./src/shipping/ingestion/.
   ```

   Push the image to ACR

   ```bash
   az acr login --name $ACR_NAME
   docker push $ACR_SERVER/ingestion:0.1.0
   ```

   Extract Azure resource details for the ingestion app

   ```bash
   export INGESTION_QUEUE_NAMESPACE=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.ingestionQueueNamespace.value -o tsv)
   export INGESTION_QUEUE_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.ingestionQueueName.value -o tsv)
   export INGESTION_ACCESS_KEY_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.ingestionServiceAccessKeyName.value -o tsv)
   export INGESTION_ACCESS_KEY_VALUE=$(az servicebus namespace authorization-rule keys list --resource-group rg-shipping-dronedelivery --namespace-name $INGESTION_QUEUE_NAMESPACE --name $INGESTION_ACCESS_KEY_NAME --query primaryKey -o tsv)
   ```

   Deploy the Ingestion service

   ```bash
   helm package ./charts/ingestion/ -u
   helm install ingestion-v0.1.0-dev ingestion-v0.1.0.tgz \
        --set image.tag=0.1.0 \
        --set image.repository=ingestion \
        --set dockerregistry=$ACR_SERVER \
        --set ingress.hosts[0].name=dronedelivery.fabrikam.com \
        --set ingress.hosts[0].serviceName=ingestion \
        --set networkPolicy.egress.external.enabled=true \
        --set networkPolicy.egress.external.clusterSubnetPrefix=$CLUSTER_SUBNET_PREFIX \
        --set networkPolicy.ingress.externalSubnet.enabled=true \
        --set networkPolicy.ingress.externalSubnet.subnetPrefix=$GATEWAY_SUBNET_PREFIX \
        --set secrets.appinsights.ikey=${AI_IKEY} \
        --set secrets.queue.keyname=IngestionServiceAccessKey \
        --set secrets.queue.keyvalue=${INGESTION_ACCESS_KEY_VALUE} \
        --set secrets.queue.name=${INGESTION_QUEUE_NAME} \
        --set secrets.queue.namespace=${INGESTION_QUEUE_NAMESPACE} \
        --set reason="Initial deployment" \
        --set envs.dev=true \
        --namespace backend-dev
   ```

   Verify the pod is created

   ```bash
   kubectl wait --namespace backend-dev --for=condition=ready pod --selector=app.kubernetes.io/name=ingestion-v0.1.0-dev --timeout=90s
   ```

1. Deploy the Workflow service app

   Build the Workflow service

   ```bash
   docker build --pull --compress -t $ACR_SERVER/workflow:0.1.0 ./src/shipping/workflow/.
   ```

   Push the image to ACR

   ```bash
   az acr login --name $ACR_NAME
   docker push $ACR_SERVER/workflow:0.1.0
   ```

   Extract Azure resource details for the workflow app

   ```bash
   export WORKFLOW_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.workflowPrincipalResourceId.value -o tsv) && \
   export WORKFLOW_PRINCIPAL_CLIENT_ID=$(az identity show -g rg-shipping-dronedelivery -n $WORKFLOW_ID_NAME --query clientId -o tsv)
   export WORKFLOW_KEYVAULT_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.workflowKeyVaultName.value -o tsv)
   ```

   Create the Workflows's Secret Provider Class resource

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
   kind: SecretProviderClass
   metadata:
     name: workflow-secrets-csi-akv
     namespace: backend-dev
   spec:
     provider: azure
     parameters:
       usePodIdentity: "true"
       keyvaultName: "${WORKFLOW_KEYVAULT_NAME}"
       objects:  |
         array:
           - |
             objectName: QueueName
             objectAlias: QueueName
             objectType: secret
           - |
             objectName: QueueEndpoint
             objectAlias: QueueEndpoint
             objectType: secret
           - |
             objectName: QueueAccessPolicyName
             objectAlias: QueueAccessPolicyName
             objectType: secret
           - |
             objectName: QueueAccessPolicyKey
             objectAlias: QueueAccessPolicyKey
             objectType: secret
           - |
             objectName: ApplicationInsights-InstrumentationKey
             objectAlias: ApplicationInsights-InstrumentationKey
             objectType: secret
       tenantId: "${TENANT_ID}"
   EOF
   ```

   Deploy the Workflow service

   ```bash
   helm package ./charts/workflow/ -u && \
   helm install workflow-v0.1.0-dev workflow-v0.1.0.tgz \
        --set image.tag=0.1.0 \
        --set image.repository=workflow \
        --set dockerregistry=$ACR_SERVER \
        --set identity.clientid=$WORKFLOW_PRINCIPAL_CLIENT_ID \
        --set identity.resourceid=$WORKFLOW_PRINCIPAL_RESOURCE_ID \
        --set networkPolicy.egress.external.enabled=true \
        --set networkPolicy.egress.external.clusterSubnetPrefix=$CLUSTER_SUBNET_PREFIX \
        --set keyvault.name=$WORKFLOW_KEYVAULT_NAME \
        --set keyvault.resourcegroup=rg-shipping-dronedelivery \
        --set keyvault.subscriptionid=$SUBSCRIPTION_ID \
        --set keyvault.tenantid=$TENANT_ID \
        --set reason="Initial deployment" \
        --set envs.dev=true \
        --namespace backend-dev
   ```

   Verify the pod is created

   ```bash
   kubectl wait --namespace backend-dev --for=condition=ready pod --selector=app.kubernetes.io/name=workflow-v0.1.0-dev --timeout=90s
   ```

1. Deploy the DroneScheduler service app

   Build the DroneScheduler service

   ```bash
   docker build -f ./src/shipping/dronescheduler/Dockerfile --pull --compress -t $ACR_SERVER/dronescheduler:0.1.0 ./src/shipping/.
   ```

   Push the image to ACR

   ```bash
   az acr login --name $ACR_NAME
   docker push $ACR_SERVER/dronescheduler:0.1.0
   ```

   Extract Azure resource details for the dronescheduler app

   ```bash
   export DRONESCHEDULER_KEYVAULT_URI=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
   export DRONESCHEDULER_COSMOSDB_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.droneSchedulerCosmosDbName.value -o tsv)
   export DRONESCHEDULER_DATABASE_NAME="invoicing"
   export DRONESCHEDULER_COLLECTION_NAME="utilization"
   export DRONESCHEDULER_PRINCIPAL_RESOURCE_ID=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.droneSchedulerPrincipalResourceId.value -o tsv) && \
   export DRONESCHEDULER_PRINCIPAL_CLIENT_ID=$(az identity show -g rg-shipping-dronedelivery -n $DRONESCHEDULER_ID_NAME --query clientId -o tsv)
   export DRONESCHEDULER_KEYVAULT_URI=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.droneSchedulerKeyVaultUri.value -o tsv)
   ```

   Deploy the DroneScheduler service

   ```bash
   helm package ./charts/dronescheduler/ -u && \
   helm install dronescheduler-v0.1.0-dev dronescheduler-v0.1.0.tgz \
        --set image.tag=0.1.0 \
        --set image.repository=dronescheduler \
        --set dockerregistry=$ACR_SERVER \
        --set identity.clientid=$DRONESCHEDULER_PRINCIPAL_CLIENT_ID \
        --set identity.resourceid=$DRONESCHEDULER_PRINCIPAL_RESOURCE_ID \
        --set networkPolicy.egress.external.enabled=true \
        --set networkPolicy.egress.external.clusterSubnetPrefix=$CLUSTER_SUBNET_PREFIX \
        --set keyvault.uri=$DRONESCHEDULER_KEYVAULT_URI \
        --set cosmosdb.id=$DRONESCHEDULER_DATABASE_NAME \
        --set cosmosdb.collectionid=$DRONESCHEDULER_COLLECTION_NAME \
        --set reason="Initial deployment" \
        --set envs.dev=true \
        --namespace backend-dev
   ```

   Verify the pod is created

   ```bash
   kubectl wait --namespace backend-dev --for=condition=ready pod --selector=app.kubernetes.io/name=dronescheduler-v0.1.0-dev --timeout=90s
   ```

1. Deploy the Package service app

   Build the Package service

   ```bash
   docker build --pull --compress -t $ACR_SERVER/package:0.1.0 ./src/shipping/package/.
   ```

   Push the image to ACR

   ```bash
   az acr login --name $ACR_NAME
   docker push $ACR_SERVER/package:0.1.0
   ```

   Extract Azure resource details for the package app

   ```bash
   export PACKAGE_DATABASE_NAME=$(az group deployment show -g rg-shipping-dronedelivery -n cluster-stamp --query properties.outputs.packageMongoDbName.value -o tsv)
   export PACKAGE_CONNECTION=$(az cosmosdb list-connection-strings --name $PACKAGE_DATABASE_NAME --resource-group rg-shipping-dronedelivery --query "connectionStrings[0].connectionString" -o tsv | sed 's/==/%3D%3D/g') && \
   export PACKAGE_COLLECTION_NAME=packages
   export PACKAGE_INGRESS_TLS_SECRET_NAME=package-ingress-tls
   ```

   Deploy the Package service

   ```bash
   helm package ./charts/package/ -u && \
   helm install package-v0.1.0-dev package-v0.1.0.tgz \
        --set image.tag=0.1.0 \
        --set image.repository=package \
        --set networkPolicy.egress.external.enabled=true \
        --set networkPolicy.egress.external.clusterSubnetPrefix=$CLUSTER_SUBNET_PREFIX \
        --set secrets.appinsights.ikey=$AI_IKEY \
        --set secrets.mongo.pwd=$PACKAGE_CONNECTION \
        --set cosmosDb.collectionName=$PACKAGE_COLLECTION_NAME \
        --set dockerregistry=$ACR_SERVER \
        --set reason="Initial deployment" \
        --set envs.dev=true \
        --namespace backend-dev
   ```

   Verify the pod is created

   ```bash
   kubectl wait --namespace backend-dev --for=condition=ready pod --selector=app.kubernetes.io/name=package-v0.1.0-dev --timeout=90s
   ```

1. Disable the public access to your ACR temporary

   ```bash
   az acr update --name $ACR_NAME --public-network-enabled false
   ```

### Next step

:arrow_forward: [End-to-End Validation](./10-validation.md)
