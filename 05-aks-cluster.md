# Deploy the AKS Cluster

Now that the [hub-spoke networks are provisioned](./04-networking.md), the next step in the [AKS secure Baseline reference implementation](./) is deploying the AKS cluster and related Azure resources.

## Steps

1. Create the AKS cluster resource group.

   > :book: The app team working on behalf of business unit "shipping" is looking to create an AKS cluster for the app that they are creating (Application ID: Drone Delivery). They have worked with the organization's networking team, who have provisioned a spoke network in which to deploy the cluster and network-aware external resources (such as Application Gateway). They took that information and added it to their [`cluster-stamp.json`](./cluster-stamp.json) and [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) files.
   >
   > They create 3 dedicated resource groups to be the parent groups for the applications during its lifetime. These are mainly for building time and runtime. Additionally, the individual user identities for in-cluster apps are going to be created as part of this step.

   ```bash
   # [This takes less than two  minute.]
   az deployment sub create --name cluster-stamp-prereqs --location eastus2 --template-file cluster-stamp-prereqs.json --parameters resourceGroupName=rg-shipping-dronedelivery resourceGroupLocation=eastus2
   ```

1. Get the AKS Fabrikam Drone Delivery 00's Azure Container Registry resource group name.

   > :book: The app team will need an isolated resource group for the Azure  Container Registry that contains all their business application Docker images.

   ```bash
   ACR_RESOURCE_GROUP=$(az deployment sub show -n cluster-stamp-prereqs --query properties.outputs.acrResourceGroupName.value -o tsv)
   ```

1. Get the AKS Fabrikam Drone Delivery 00's user identities

   > :book: the app team will need to assign roles to the user identities so these are granted appropriate access to specific Azure services.

   ```bash
   DELIVERY_ID_NAME=$(az deployment group show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.deliveryIdName.value -o tsv) && \
   DELIVERY_ID_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery -n $DELIVERY_ID_NAME --query principalId -o tsv) && \
   DRONESCHEDULER_ID_NAME=$(az deployment group show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.droneSchedulerIdName.value -o tsv) && \
   DRONESCHEDULER_ID_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery -n $DRONESCHEDULER_ID_NAME --query principalId -o tsv) && \
   WORKFLOW_ID_NAME=$(az deployment group show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.workflowIdName.value -o tsv) && \
   WORKFLOW_ID_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery -n $WORKFLOW_ID_NAME --query principalId -o tsv) && \
   INGRESS_CONTROLLER_ID_NAME=$(az deployment group show -g rg-shipping-dronedelivery -n cluster-stamp-prereqs-identities --query properties.outputs.appGatewayControllerIdName.value -o tsv) && \
   INGRESS_CONTROLLER_ID_PRINCIPAL_ID=$(az identity show -g rg-shipping-dronedelivery -n $INGRESS_CONTROLLER_ID_NAME --query principalId -o tsv)
   ```

1. Wait for Azure AD propagation of the AKS Fabrikam Drone Delivery 00's user identities.

   ```bash
   until az ad sp show --id ${DELIVERY_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
   until az ad sp show --id ${DRONESCHEDULER_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
   until az ad sp show --id ${WORKFLOW_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
   until az ad sp show --id ${INGRESS_CONTROLLER_ID_PRINCIPAL_ID} &> /dev/null ; do echo "Waiting for AAD propagation" && sleep 5; done
   ```

1. Get the AKS cluster spoke VNet resource ID.

   > :book: The app team will be deploying to a spoke VNet that the network team has already provisioned.

   ```bash
   TARGET_VNET_RESOURCE_ID=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-shipping-dronedelivery --query properties.outputs.clusterVnetResourceId.value -o tsv)
   ```

1. Deploy the cluster ARM template.
  :exclamation: By default, this deployment will allow unrestricted access to your cluster's API Server. You can limit access to the API Server to a set of well-known IP addresses such as your hub firewall IP, bastion subnet, and build agents. You can do this by providing these IP addresses to the `clusterAuthorizedIPRanges` parameter of the cluster-stamp ARM template.

    **Option 1 - Deploy from the command line**

   ```bash
   # [This takes about 15 minutes.]
   az deployment group create --resource-group rg-shipping-dronedelivery --template-file cluster-stamp.json --parameters targetVnetResourceId=$TARGET_VNET_RESOURCE_ID k8sRbacAadProfileAdminGroupObjectID=$K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_OBJECTID k8sRbacAadProfileTenantId=$K8S_RBAC_AAD_PROFILE_TENANTID appGatewayListenerCertificate=$APP_GATEWAY_LISTENER_CERTIFICATE aksIngressControllerCertificate=$AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64 deliveryIdName=$DELIVERY_ID_NAME deliveryPrincipalId=$DELIVERY_ID_PRINCIPAL_ID droneSchedulerIdName=$DRONESCHEDULER_ID_NAME droneSchedulerPrincipalId=$DRONESCHEDULER_ID_PRINCIPAL_ID workflowIdName=$WORKFLOW_ID_NAME workflowPrincipalId=$WORKFLOW_ID_PRINCIPAL_ID ingressControllerIdName=$INGRESS_CONTROLLER_ID_NAME ingressControllerPrincipalId=$INGRESS_CONTROLLER_ID_PRINCIPAL_ID acrResourceGroupName=$ACR_RESOURCE_GROUP
   ```

   > Alternatively, you could have updated the [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) file and deployed as above, using `--parameters "@azuredeploy.parameters.prod.json"` instead of the individual key-value pairs.

    **Option 2 - Automated deploy using GitHub Actions (fork is required)**

    1. Create the Azure Credentials for the GitHub CD workflow.

       ```bash
       # Create an Azure Service Principal
       az ad sp create-for-rbac --name "github-workflow-aks-cluster" --sdk-auth --skip-assignment > sp.json
       export APP_ID=$(grep -oP '(?<="clientId": ").*?[^\\](?=",)' sp.json)

       # Wait for propagation
       until az ad sp show --id ${APP_ID} &> /dev/null ; do echo "Waiting for Azure AD propagation" && sleep 5; done

       # Assign built-in Contributor RBAC role for creating resource groups and performing deployments at the subscription level
       az role assignment create --assignee $APP_ID --role 'Contributor'

       # Assign built-in User Access Administrator RBAC role since granting RBAC access to other resources during the cluster creation will be required at subscription level (e.g. AKS-managed Internal Load Balancer, ACR, Managed Identities, etc.)
       az role assignment create --assignee $APP_ID --role 'User Access Administrator'
       ```

    1. Create `AZURE_CREDENTIALS` secret in your GitHub repository. For more information, see [Creating encrypted secrets for a repository](https://docs.github.com/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository).

       > :bulb: Use the content from the `sp.json` file.

       ```bash
       cat sp.json
       ```

    1. Create `APP_GATEWAY_LISTENER_CERTIFICATE_BASE64` secret in your GitHub repository. For more information, see [Creating encrypted secrets for a repository](https://docs.github.com/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository).

       > :bulb:
       >
       >  * Use the env var value of `APP_GATEWAY_LISTENER_CERTIFICATE`
       >  * Ideally fetching this secret from a platform-managed secret store such as [Azure KeyVault](https://github.com/marketplace/actions/azure-key-vault-get-secrets)

       ```bash
       echo $APP_GATEWAY_LISTENER_CERTIFICATE
       ```

    1. Create `AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64` secret in your GitHub repository. For more information, see [Creating encrypted secrets for a repository](https://docs.github.com/actions/configuring-and-managing-workflows/creating-and-storing-encrypted-secrets#creating-encrypted-secrets-for-a-repository).

       > :bulb:
       >
       >  * Use the env var value of `AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64`
       >  * Ideally fetching this secret from a platform-managed secret store such as [Azure Key Vault](https://github.com/marketplace/actions/azure-key-vault-get-secrets)

       ```bash
       echo $AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64
       ```

    1. Copy the GitHub workflow file into the expected directory and update the placeholders in it.

       ```bash
       mkdir -p .github/workflows
       cat github-workflow/aks-deploy.yaml | \
           sed "s#<resource-group-location>#eastus2#g" | \
           sed "s#<resource-group-name>#rg-shipping-dronedelivery#g" | \
           sed "s#<geo-redundancy-location>#centralus#g" | \
           sed "s#<cluster-spoke-vnet-resource-id>#$TARGET_VNET_RESOURCE_ID#g" | \
           sed "s#<tenant-id-with-user-admin-permissions>#$K8S_RBAC_AAD_PROFILE_TENANTID#g" | \
           sed "s#<azure-ad-aks-admin-group-object-id>#$K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_OBJECTID#g" | \
           sed "s#<delivery-id-name>#$DELIVERY_ID_NAME#g" | \
           sed "s#<delivery-principal-id>#$DELIVERY_ID_PRINCIPAL_ID#g" | \
           sed "s#<dronescheduler-id-name>#$DRONESCHEDULER_ID_NAME#g" | \
           sed "s#<dronescheduler-principal-id>#$DRONESCHEDULER_ID_PRINCIPAL_ID#g" | \
           sed "s#<workflow-id-name>#$WORKFLOW_ID_NAME#g" | \
           sed "s#<workflow-principal-id>#$WORKFLOW_ID_PRINCIPAL_ID#g" | \
           sed "s#<ingress-controller-id-name>#$INGRESS_CONTROLLER_ID_NAME#g" | \
           sed "s#<ingress-controller-principalid>#$INGRESS_CONTROLLER_ID_PRINCIPAL_ID #g" | \
           sed "s#<acr-resource-group-name>#$ACR_RESOURCE_GROUP#g" | \
           sed "s#<acr-resource-group-location>#eastus2#g" \
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

       > :book: The DevOps team configured the GitHub Workflow to preview the changes that will happen when a PR is opened. This preview allows them to evaluate any changes before they get deployed. After the PR reviewers see how resources will change if the AKS cluster ARM template gets deployed, it is possible to merge or discard the pull request. If the decision is made to merge, a push event s created that will start the deployment process that consists of:
       >
       > * AKS cluster creation
       > * Flux deployment

    1. Once the GitHub Workflow validation has finished successfully, please proceed by merging this PR into `main`.

       > :book: The DevOps team monitors this Workflow execution instance. In this instance, it will impact a critical piece of infrastructure as well as the management. This flow works for both new or existing AKS clusters.

    1. :fast_forward: The cluster is placed under GitOps managed as part of these GitHub Workflow steps. Therefore, you should proceed straight to [Workflow Prerequisites](./07-workload-prerequisites.md).

## Container registry note

:warning: To assist in deploying this cluster and workload experimentation, Azure Policy is configured to allow your cluster to pull images from _public container registries_ such as Docker Hub and Quay. For a production system, update the Azure Policy named `pa-allowed-registries-images` in your `cluster-stamp.json` file to only list container registries that you are willing to take a dependency on and to what namespaces those policies should apply. This configuration protects the cluster from unapproved registry use. This configuration helps prevent issues while trying to pull images from a registry that does not provide SLA guarantees for your deployment.

This deployment creates an SLA-backed Azure Container Registry for your cluster's needs. Your organization may have a central container registry for you to use, or your registry may be deployed with your application's infrastructure (as demonstrated in this implementation). **Only use container registries that satisfy the availability needs of your application.**

### Next step

:arrow_forward: [Place the cluster under GitOps management](./06-gitops.md)
