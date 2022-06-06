# Prep for Azure Active Directory Integration

In the prior step, you [generated the user-facing TLS certificate](./02-ca-certificates.md), now we'll prepare for leveraging Azure AD for Kubernetes role-based access control (RBAC). This step is the last of the cluster infrastructure prerequisites.

## Steps

> :book: The Fabrikam Drone Delivery Azure AD team requires all admin access to AKS clusters be security-group based. This configuration applies to the new AKS cluster that is being built for the Fabrikam Drone Delivery Shipping application under the shipping business unit. Kubernetes RBAC will be AAD-backed and access granted based on a user's identity or directory group membership.

1. Query for and save your Azure subscription tenant id of for the subscription where the AKS cluster will be deployed. This value is used throughout the reference implementation.

   ```bash
   export TENANT_ID=$(az account show --query tenantId --output tsv)
   ```

1. Log into the tenant associated with the Azure Active Directory instance that will be used to provide identity services to the AKS cluster.
   ```bash
   az login
   ```

2. Retrieve the tenant ID for this tenant. This value is used when deploying the AKS cluster.

   ```
   export K8S_RBAC_AAD_PROFILE_TENANTID=$(az account show --query tenantId --output tsv)
   ```

1. Create the first Azure AD group that will map the Kubernetes Cluster Role Admin. If you already have a security group appropriate for cluster admins, consider using that group and skipping this step. If using your own group, you will need to update group object names throughout the reference implementation.

   ```bash
   export K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_OBJECTID=$(az ad group create --display-name aad-to-dronedelivery-cluster-admin --mail-nickname aad-to-dronedelivery-cluster-admin --query id -o tsv)
   ```

1. Create a break-glass Cluster Admin user for the Fabrikam Drone Delivery AKS cluster.

   > :book: The organization knows the value of having a break-glass admin user for their critical infrastructure. The app team requests a cluster admin user, and the Azure AD Admin team proceeds with the creation of the user from Azure AD.

   ```bash
   export K8S_RBAC_AAD_PROFILE_TENANT_DOMAIN_NAME=$(az ad signed-in-user show --query 'userPrincipalName' -o tsv | cut -d '@' -f 2 | sed 's/\"//')
   export AKS_ADMIN_OBJECTID=$(az ad user create --display-name=dronedelivery-admin --user-principal-name dronedelivery-admin@${K8S_RBAC_AAD_PROFILE_TENANT_DOMAIN_NAME} --force-change-password-next-sign-in --password ChangeMeDroneDeliveryAdminChangeMe! --query id -o tsv)
   ```

1. Add the new admin user to the new security group to grant the Kubernetes Cluster Admin role.

   > :book: The recently created break-glass admin user is added to the Kubernetes Cluster Admin group from Azure AD. After this step, the Azure AD Admin team will have finished the app team's request, and the outcome are:
   >
   > * the new app team's user admin credentials
   > * and the Azure AD group object ID
   >

   ```bash
   az ad group member add --group aad-to-dronedelivery-cluster-admin --member-id $AKS_ADMIN_OBJECTID
   ```

   The value stored in the $AKS_ADMIN_OBJECTID is the id of the newly created user. This value is needed when creating the AKS cluster for establishing proper cluster RBAC role bindings.

1. Set up groups to map into other Kubernetes Roles. (Optional, fork required).

   > :book: The team knows there will be more than cluster admins that need group-managed access to the cluster.  Out of the box, Kubernetes has other roles like _admin_, _edit_, and _view_, which can also be mapped to Azure AD Groups.

   In the [`user-facing-cluster-role-aad-group.yaml` file](./cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml), you can replace the four `<replace-with-an-aad-group-object-id-for-this-cluster-role-binding>` placeholders with corresponding new or existing AD groups that map to their purpose for this cluster.

   :bulb: Alternatively, you can make these group associations to [Azure RBAC roles](https://docs.microsoft.com/azure/aks/manage-azure-rbac). At the time of this writing, this feature is still in _preview_ but will become the preferred way of mapping identities to Kubernetes RBAC roles.

### Next step

:arrow_forward: [Deploy the hub-spoke network topology](./04-networking.md)
