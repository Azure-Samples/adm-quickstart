# Project Name

This quick start deploys a simple hello-world webapp to two regions in a staged manner using Azure Deployment Manager (ADM).

# Getting Started
## Prerequisites

An understanding of Deployment Manager: https://docs.microsoft.com/en-us/azure/azure-resource-manager/deployment-manager-overview

Az powershell module should be installed on the machine:
Installation instructions: https://docs.microsoft.com/en-us/powershell/azure/overview

Az.ManagedServiceIdentity module should be installed. Run the 'New-AzUserAssignedIdentity' cmdlet in a powershell window and if you get an error signature like "The term 'New-AzUserAssignedIdentity' is not recognized as the name of a cmdlet", run the following command in a powershell window opened in Administrator mode.

```
Install-Module -Name Az.ManagedServiceIdentity
```

## Details

App directory: 
Contains the code and scripts that make up the WebApp. This code is taken from the Azure NodeJS based WebApp sample: https://github.com/Azure-Samples/nodejs-docs-hello-world/

Deploy directory:
The artifacts and scripts that are used to deploy the app using ADM. 
This also includes the templates/parameters files required to create the ADM resources that deploy the WebApp.

ArtifactRoot:
Contains the ARM Template and Parameters files for the WebApp deployment. These are given to ADM and used by ADM to orchestrate your WebApp deployment.
The WebApp code in App directory is packaged into a zip as required for deployment and is stored in the bin directory.

DeploymentManagerSetup.ps1 script creates all the ADM resources, sets up a storage account, uploads the WebApp artifacts (from where this sample is run) to the storage account, creates a User Assigned Identity, creates a role assignment in your subscription for this Identity and proceeds to create a rollout.

## Run

1. Launch PowerShell
2. Clone the repo: git clone https://github.com/Azure-Samples/adm-quickstart
3. cd adm-quickstart\Deploy
4. Connect to Azure. Enter your Azure login credentials in the logon prompt.

```
Connect-AzAccount
```

5. Launch the setup script by running the following command. You need to provide a subscription Id, resource group name (the script creates this resource group for you) and location for the resource groups. Make sure to give a subscription Id that is in the account you logged in with.

```
.\DeploymentManagerSetup.ps1 -subscriptionId "<subscriptionId>" -resourceGroupName "<resourceGroupName>" -location "<location>"
```

Once you launch the script, you should be able to navigate to the given subscription and resource group in the Azure portal [portal.azure.com] and view the resources getting created. Make sure you select 'Show Hidden Types' option in the resource group view to see the ADM resources.

The WebApps are created in two different target resource groups named <resourceGroupName>ServiceWUSrg and <resourceGroupName>ServiceEUSrg. You can view the WebApp and dependent resources getting deployed to these resource groups once the script runs and as the rollout progresses. The rollout has a Wait Step after deploying to one region to demonstrate how you can introduce steps into your rollout to customize your deployment experience.

Once the script runs successfully it will print the command to track the rollout progress.
Run this command every 2-3 minutes to view the current status of the rollout and the resources that are being created. The rollout will reach a terminal state of 'Succeeded' when all the resources are deployed and all rollout steps are completed. 

## Clean up
There are 2 resource groups created in addition to the one provided as input to the script and you can clean up all the resources created in your subscription by deleting these 3 resource groups. 
Search in the portal for the resource groups using <resourceGroupName> and delete them.
Alternately, you can run the following commands from PowerShell to delete these resource groups.

Deleting the resource groups will delete all the underlying resources created as part of this quick start.

```
 Remove-AzResourceGroup -Name <resourceGroupName>
 Remove-AzResourceGroup -Name <resourceGroupName>ServiceWUSrg 
 Remove-AzResourceGroup -Name <resourceGroupName>ServiceEUSrg
```


# Resources

- ADM Overview: https://docs.microsoft.com/en-us/azure/azure-resource-manager/deployment-manager-overview
- Health Check integrated rollout with ADM: https://docs.microsoft.com/en-us/azure/azure-resource-manager/deployment-manager-health-check
- ADM tutorial: https://docs.microsoft.com/en-us/azure/azure-resource-manager/deployment-manager-tutorial
- ADM Health Check tutorial: https://docs.microsoft.com/en-us/azure/azure-resource-manager/deployment-manager-tutorial-health-check
