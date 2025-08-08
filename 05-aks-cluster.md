# Deploy the AKS Cluster

Now that the [hub-spoke networks are provisioned](./04-networking.md), the next step in the [reference implementation](./) is deploying the AKS cluster and related Azure resources.

## Steps

1.  Create the AKS cluster and the Azure Container Registry resource groups.

    > :book: The app team working on behalf of business unit "shipping" is looking to create an AKS cluster for the app that they are creating (Application ID: Drone Delivery). They have worked with the organization's networking team, who have provisioned a spoke network in which to deploy the cluster and network-aware external resources (such as Application Gateway). They took that information and added it to their [`cluster-stamp.json`](./cluster-stamp.json) and [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) files.
    >
    > They create 3 dedicated resource groups to be the parent groups for the applications during its lifetime. These are mainly for building time and runtime. Additionally, the individual user identities for in-cluster apps are going to be created as part of this step.

    ```bash
    # [This takes less than two  minutes.]
    az deployment sub create --name workload-stamp-prereqs-${LOCATION} --location ${LOCATION} --template-file ./workload/workload-stamp-prereqs.bicep --parameters resourceGroupLocation=${LOCATION}

    az deployment sub create --name cluster-stamp-prereqs-${LOCATION} --location ${LOCATION} --template-file cluster-stamp-prereqs.bicep --parameters resourceGroupName=rg-shipping-dronedelivery-${LOCATION} resourceGroupLocation=${LOCATION}
    ```

1.  Get the AKS Fabrikam Drone Delivery 00's user identities

    > :book: the app team will need to assign roles to the user identities so these are granted appropriate access to specific Azure services.

    ```bash
    DELIVERY_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery-${LOCATION} -n uid-delivery --query principalId -o tsv) && \
    DRONESCHEDULER_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery-${LOCATION} -n uid-dronescheduler --query principalId -o tsv) && \
    WORKFLOW_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery-${LOCATION} -n uid-workflow --query principalId -o tsv) && \
    PACKAGE_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery-${LOCATION} -n uid-package --query principalId -o tsv) && \
    INGESTION_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery-${LOCATION} -n uid-ingestion --query principalId -o tsv)
    ```

1.  Wait for Microsoft Entra propagation of the AKS Fabrikam Drone Delivery 00's user identities.

    ```bash
    until az ad sp show --id ${DELIVERY_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for Microsoft Entra ID propagation" && sleep 5; done
    until az ad sp show --id ${DRONESCHEDULER_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for Microsoft Entra ID propagation" && sleep 5; done
    until az ad sp show --id ${WORKFLOW_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for Microsoft Entra ID propagation" && sleep 5; done
    until az ad sp show --id ${PACKAGE_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for Microsoft Entra ID propagation" && sleep 5; done
    until az ad sp show --id ${INGESTION_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for Microsoft Entra ID propagation" && sleep 5; done
    ```

1.  Get the AKS cluster spoke VNet resource ID.

    > :book: The app team will be deploying to a spoke VNet that the network team has already provisioned.

    ```bash
    TARGET_VNET_RESOURCE_ID=$(az deployment group show -g rg-enterprise-networking-spokes-${LOCATION} -n spoke-shipping-dronedelivery --query properties.outputs.clusterVnetResourceId.value -o tsv)
    ```

1.  Deploy the Azure Container Registry Bicep template.

    ```bash
    # [This takes about 10 minutes.]
    az deployment group create -f ./workload/workload-stamp.bicep -g rg-shipping-dronedelivery-${LOCATION} -p droneSchedulerPrincipalId=$DRONESCHEDULER_PRINCIPAL_ID -p workflowPrincipalId=$WORKFLOW_PRINCIPAL_ID -p deliveryPrincipalId=$DELIVERY_PRINCIPAL_ID  -p ingestionPrincipalId=$INGESTION_PRINCIPAL_ID -p packagePrincipalId=$PACKAGE_PRINCIPAL_ID
    ```

1.  Get the Azure Container Registry deployment output variables

    ```bash
    ACR_NAME=$(az deployment group show -g rg-shipping-dronedelivery-${LOCATION} -n workload-stamp --query properties.outputs.acrName.value -o tsv) && \
    ACR_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
    ```

1.  Import cluster management images to your container registry.

    > Public container registries are subject to faults such as outages (no SLA) or request throttling. Interruptions like these can be crippling for a system that needs to pull an image _right now_. To minimize the risks of using public registries, store all applicable container images in a registry that you control, such as the SLA-backed Azure Container Registry.

    ```bash
    # Import cluster management images hosted in public container registries
    az acr import --source ghcr.io/kubereboot/kured:1.15.0 -n $ACR_NAME
    ```

1.  Prepare for Flux extension

    > - update the `<replace-with-an-entra-group-object-id-for-this-cluster-role-binding>` placeholder in [`user-facing-cluster-role-entra-group.yaml`](./cluster-manifests/user-facing-cluster-role-entra-group.yaml) with the Object IDs for the Microsoft Entra group(s) you created for management purposes. If you don't, the manifest will still apply, but Microsoft Entra integration will not be mapped to your specific Microsoft Entra configuration.
    > - Update three `image` manifest references to your container registry instead of the default public container registry. See comment in each file for instructions.
    >   - update the one `image:` values in [`kured-1.15.0-dockerhub.yaml`](./cluster-baseline-settings/kured-1.15.0-dockerhub.yaml).

1.  Deploy the cluster Bicep template.
    :exclamation: By default, this deployment will allow unrestricted access to your cluster's API Server. You can limit access to the API Server to a set of well-known IP addresses such as your hub firewall IP, bastion subnet, and build agents. You can do this by providing these IP addresses to the `clusterAuthorizedIPRanges` parameter of the cluster-stamp Bicep template.

    **Option 1 - Deploy from the command line**

    ```bash
    # [This takes about 15 minutes.]
    az deployment group create --resource-group rg-shipping-dronedelivery-${LOCATION} --template-file cluster-stamp.bicep --parameters targetVnetResourceId=$TARGET_VNET_RESOURCE_ID k8sRbacEntraAdminGroupObjectID=$K8S_RBAC_ENTRA_ADMIN_GROUP_OBJECTID k8sRbacEntraProfileTenantId=$K8S_RBAC_ENTRA_TENANTID appGatewayListenerCertificate=$APP_GATEWAY_LISTENER_CERTIFICATE aksIngressControllerCertificate=$AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64 deliveryIdName=uid-delivery  droneSchedulerIdName=uid-dronescheduler workflowIdName=uid-workflow ingressControllerIdName=uid-ingestion acrResourceGroupName=rg-shipping-dronedelivery-${LOCATION}-acr acrName=$ACR_NAME
    ```

    > Alternatively, you could have updated the [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) file and deployed as above, using `--parameters "@azuredeploy.parameters.prod.json"` instead of the individual key-value pairs.

    **Option 2 - Automated deploy using GitHub Actions (fork is required)**  
    The GitHub Action integration is using [OpenID Connect (OIDC) with an Azure service principal using a Federated Identity Credential](/azure/developer/github/connect-from-azure)

    1. Create Microsoft Entra application and service principal and then assign a role on your subscription to your application so that your workflow has access to your subscription.

       ```bash
         GH_ACTION_FEDERATED_IDENTITY=$(az ad app create --display-name ghActionFederatedIdentity)
         GH_ACTION_FEDERATED_IDENTITY_APP_ID=$(echo $GH_ACTION_FEDERATED_IDENTITY | jq -r '.appId')
         GH_ACTION_FEDERATED_IDENTITY_OBJECT_ID=$(echo $GH_ACTION_FEDERATED_IDENTITY | jq -r '.id')
         GH_ACTION_FEDERATED_IDENTITY_SP=$(az ad sp create --id $GH_ACTION_FEDERATED_IDENTITY_APP_ID)
         GH_ACTION_FEDERATED_IDENTITY_SP_OBJECT_ID=$(echo $GH_ACTION_FEDERATED_IDENTITY_SP | jq -r '.id')
       ```

       Set environment information

       ```bash
         AZURE_SUBSCRIPTION_ID=$(az account show --query 'id' -o tsv)
         AZURE_SUBSCRIPTION_RESOURCE_ID=/subscriptions/$(az account show --query 'id' -o tsv)
         GITHUB_USER_NAME=<git repository owner>
       ```

       Create a new role assignment by subscription and object

       ```bash
         # Assign built-in Contributor RBAC role for creating resource groups and performing deployments at the subscription level
         az role assignment create --role contributor --subscription $AZURE_SUBSCRIPTION_ID --assignee-object-id  $GH_ACTION_FEDERATED_IDENTITY_SP_OBJECT_ID --assignee-principal-type ServicePrincipal --scope $AZURE_SUBSCRIPTION_RESOURCE_ID

         # Assign built-in User Access Administrator RBAC role since granting RBAC access to other resources during the cluster creation will be required at subscription level (e.g. AKS-managed Internal Load Balancer, ACR, Managed Identities, etc.)
         az role assignment create --role 'User Access Administrator' --subscription $AZURE_SUBSCRIPTION_ID --assignee-object-id $GH_ACTION_FEDERATED_IDENTITY_SP_OBJECT_ID --assignee-principal-type ServicePrincipal --scope $AZURE_SUBSCRIPTION_RESOURCE_ID
       ```

    1. Add federated credentials

       First, the ./github-workflow/credential.json file needs to be customized with the repository owner.

       ```bash
          sed -i "s/<repo_owner>/${GITHUB_USER_NAME}/g" ./github-workflow/credential.json
       ```

       Then, the federated credential need to be created.

       ```bash
         az ad app federated-credential create --id $GH_ACTION_FEDERATED_IDENTITY_OBJECT_ID --parameters ./github-workflow/credential.json
       ```

    1. Install [GitHub CLI](https://github.com/cli/cli/#installation)

    1. Create secrets for AZURE_CLIENT_ID, AZURE_TENANT_ID, and AZURE_SUBSCRIPTION_ID.  
       Use these values from your Microsoft Entra application for your GitHub secrets:

       ```bash
         gh secret set AZURE_CLIENT_ID -b"${GH_ACTION_FEDERATED_IDENTITY_APP_ID}" --repo ${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery
         gh secret set AZURE_TENANT_ID -b"${TENANT_ID}" --repo ${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery
         gh secret set AZURE_SUBSCRIPTION_ID -b"${AZURE_SUBSCRIPTION_ID}" --repo ${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery
       ```

    1. Create the secret `APP_GATEWAY_LISTENER_CERTIFICATE_BASE64` in your GitHub repository.

       ```bash
         gh secret set APP_GATEWAY_LISTENER_CERTIFICATE_BASE64 -b"${APP_GATEWAY_LISTENER_CERTIFICATE}" --repo ${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery
       ```

    1. Create `AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64` secret in your GitHub repository.

       ```bash
         gh secret set AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64 -b"${AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64}" --repo ${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery
       ```

    1. Copy the GitHub workflow file into the expected directory and update the placeholders in it.

       ```bash
       mkdir -p .github/workflows
       cat github-workflow/aks-deploy.yaml | \
         sed "s#<resource-group-name>#rg-shipping-dronedelivery-${LOCATION}#g" | \
         sed "s#<cluster-spoke-vnet-resource-id>#$TARGET_VNET_RESOURCE_ID#g" | \
         sed "s#<tenant-id-with-user-admin-permissions>#$K8S_RBAC_ENTRA_TENANTID#g" | \
         sed "s#<azure-ad-aks-admin-group-object-id>#$K8S_RBAC_ENTRA_ADMIN_GROUP_OBJECTID#g" | \
         sed "s#<delivery-id-name>#uid-delivery#g" | \
         sed "s#<dronescheduler-id-name>#uid-dronescheduler#g" | \
         sed "s#<workflow-id-name>#uid-workflow#g" | \
         sed "s#<ingress-controller-id-name>#uid-ingestion#g"  | \
         sed "s#<acr-resource-group-name>#$ACR_RESOURCE_GROUP#g"  | \
         sed "s#<acr-name>#$ACR_NAME#g"  | \
         sed "s#<gitops-bootstrapping-repo-https-url>#https://github.com/${GITHUB_USER_NAME}/aks-fabrikam-dronedelivery.git#g"  | \
         sed "s#<gitops-bootstrapping-repo-branch>#main#g" \
         > .github/workflows/aks-deploy.yaml
       ```

    1. Push the changes to your forked repo.

       > :book: The DevOps team wants to automate their infrastructure deployments. In this case, they decided to use GitHub Actions. They are going to create a workflow for every AKS cluster instance they need to deploy and manage.

       ```bash
       git add .github/workflows/aks-deploy.yaml && git commit -m "setup GitHub CD workflow"
       git push origin HEAD:kick-off-workflow
       ```

       > :bulb: You might want to convert this GitHub workflow into a template since your organization or team might need to handle multiple AKS clusters. For more information, see [Sharing Workflow Templates within your organization](https://docs.github.com/actions/configuring-and-managing-workflows/sharing-workflow-templates-within-your-organization).

    1. Navigate to your GitHub forked repository and open a PR against `main` using the recently pushed changes to the remote branch `kick-off-workflow`.

       > :book: The DevOps team configured the GitHub Workflow to preview the changes that will happen when a PR is opened. This preview allows them to evaluate any changes before they get deployed. After the PR reviewers see how resources will change if the AKS cluster Bicep template gets deployed, it is possible to merge or discard the pull request. If the decision is made to merge, a push event s created that will start the deployment process that consists of:
       >
       > - AKS cluster creation
       > - Flux deployment

    1. Once the GitHub Workflow validation has finished successfully, please proceed by merging this PR into `main`.

       > :book: The DevOps team monitors this Workflow execution instance. In this instance, it will impact a critical piece of infrastructure as well as the management. This flow works for both new or existing AKS clusters.

    1. :fast_forward: The cluster is placed under GitOps managed as part of these GitHub Workflow steps. Therefore, you should proceed straight to [Workflow Prerequisites](./07-workload-prerequisites.md).

## Container registry note

:warning: To assist in deploying this cluster and workload experimentation, Azure Policy is configured to allow your cluster to pull images from _public container registries_ such as Docker Hub and Quay. For a production system, update the Azure Policy named `pa-allowed-registries-images` in your `cluster-stamp.json` file to only list container registries that you are willing to take a dependency on and to what namespaces those policies should apply. This configuration protects the cluster from unapproved registry use. This configuration helps prevent issues while trying to pull images from a registry that does not provide SLA guarantees for your deployment.

This deployment creates an SLA-backed Azure Container Registry for your cluster's needs. Your organization may have a central container registry for you to use, or your registry may be deployed with your application's infrastructure (as demonstrated in this implementation). **Only use container registries that satisfy the availability needs of your application.**

### Next step

:arrow_forward: [Place the cluster under GitOps management](./06-gitops.md)
