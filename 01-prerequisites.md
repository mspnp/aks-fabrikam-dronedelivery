# Prerequisites

This document is the starting point for deploying the [reference implementation](./README.md). There is required access and tooling you need in order to complete the deployment. Follow the instructions below and on the subsequent pages so that you can get your environment ready to proceed with the AKS cluster creation.

## Steps

1. An Azure subscription. If you don't have an Azure subscription, you can create a [free account](https://azure.microsoft.com/free).

   > :warning: The user or service principal initiating the deployment process _must_ have the following minimal set of Azure Role-Based Access Control (RBAC) roles:
   >
   > * [Contributor role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor) is _required_ at the subscription level to have the ability to create resource groups and perform deployments.
   > * [User Access Administrator role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#user-access-administrator) is _required_ at the subscription level since you'll be granting least-privilege RBAC access to managed identities.
   >   * One such example is detailed in the [Container Insights documentation](https://learn.microsoft.com/azure/azure-monitor/insights/container-insights-troubleshoot#authorization-error-during-onboarding-or-update-operation).

1. A Microsoft Entra tenant to associate your Kubernetes RBAC configuration to.

   > :warning: The user or service principal initiating the deployment process _must_ have the following minimal set of Microsoft Entra permissions assigned:
   >
   > * Microsoft Entra [User Administrator](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#user-administrator-permissions) is _required_ to create a "break glass" AKS admin Microsoft Entra security group and user. Alternatively, you could get your Microsoft Entra admin to create this for you when instructed to do so.
   >   * If you are not part of the User Administrator group in the tenant associated to your Azure subscription, please consider [creating a new tenant](https://learn.microsoft.com/entra/fundamentals/create-new-tenant#create-a-new-tenant-for-your-organization) to use while evaluating this implementation.

1. Latest [Azure CLI installed](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest) (must be at least 2.56), or you can perform this from Azure Cloud Shell by clicking below.

   [![Launch Azure Cloud Shell](https://learn.microsoft.com/azure/includes/media/cloud-shell-try-it/launchcloudshell.png)](https://shell.azure.com)

1. Clone/download this repo locally, or even better, fork this repository.

   > :twisted_rightwards_arrows: If you have forked this reference implementation repos, you'll be able to customize some of the files and commands for a more personalized experience; also, ensure references to repos mentioned are updated to use your own (e.g., the following `GITHUB_REPO`).

   ```bash
   export GITHUB_REPO=https://github.com/mspnp/aks-fabrikam-dronedelivery.git
   git clone --recurse-submodules $GITHUB_REPO
   ```

   > :bulb: The steps shown here and elsewhere in the reference implementation use Bash shell commands. On Windows, you can use the [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/about#what-is-wsl-2) to run Bash. If you are planning to use VS Code, create a script file to store commands from this tutorial in it and run using VS Code's integrated Bash terminal then run `export MSYS_NO_PATHCONV=1` to avoid path mangling.

1. Ensure [OpenSSL is installed](https://github.com/openssl/openssl#download) in order to generate self-signed certs used in this implementation.
1. [JQ](https://stedolan.github.io/jq/download/)
1. [Helm 3](https://helm.sh)

   ```bash
   curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
   ```

### Next step

:arrow_forward: [Generate your client-facing TLS certificate](./02-ca-certificates.md)
