<#
.SYNOPSIS
Sets up all the required resources for an ADM rollout and launches the rollout.
#>

param 
(
    [string] $subscriptionId,
    [string] $resourceGroupName,
    [string] $location
)

$global:createRolloutTemplate = ".\CreateRollout.json"
$global:createRolloutTemplateParameters = ".\CreateRollout.Parameters.json"
$global:createTopologyTemplate = ".\CreateTopology.json"
$global:createTopologyTemplateParameters = ".\CreateTopology.Parameters.json"

$global:parametersEUSPath = "ArtifactRoot\Parameters\WebApp.Parameters_EUS.json" 
$global:parametersWUSPath = "ArtifactRoot\Parameters\WebApp.Parameters_WUS.json"
$global:templatePath = "ArtifactRoot\Templates\WebApp.Template.json" 
$global:appPackageRelativePath = "ArtifactRoot\bin\WebApp.zip"
$global:westUSLocation = "West US"
$global:eastUSLocation = "East US"

$global:escapePattern = '[^a-z0-9 ]'

<#
.SYNOPSIS
Sets up all the required artifacts and DeploymentManager resources and launches a rollout.
#>
function Setup-EndToEnd
{
    param
	(
        $subscriptionId,
        $resourceGroupName,
        $location,
        $targetResourceGroupNameWUS,
        $targetResourceGroupNameEUS
    )

    $randomNum = Get-Random -Maximum 300
    $storageAccountName = $resourceGroupName.Substring(0, [System.Math]::Min(18, $resourceGroupName.Length)).ToLower() + $randomNum + "stg"
    $storageAccountName = $storageAccountName -replace $global:escapePattern

    # Create resource group
    New-AzResourceGroup -Name $resourceGroupName -Location $location -Force | Out-Null

    # Create target resource groups
    New-AzResourceGroup -Name $targetResourceGroupNameWUS -Location $global:westUSLocation -Force | Out-Null
    New-AzResourceGroup -Name $targetResourceGroupNameEUS -Location $global:eastUSLocation -Force | Out-Null

	# Create artifact source
    $sasKeyForContainer = Setup-ArtifactSource $resourceGroupName $storageAccountName $artifactSourceName $location 

    Setup-Topology $resourceGroupName $location $sasKeyForContainer $subscriptionId

    Setup-Rollout $resourceGroupName $location
}

<#
.SYNOPSIS
Creates the topology and other resources.
#>
function Setup-Topology
{
    param
    (
        $resourceGroupName,
        $location,
        $sasKeyForContainer,
        $subscriptionId
    )

    $deploymentName = "CreateTopology"

    Replace-TopologyPlaceHolders $resourceGroupName $location $sasKeyForContainer $subscriptionId

    Write-Host "`nCreating ArtifactSource, ServiceTopology and other ADM resources."
    New-AzResourceGroupDeployment `
        -Name $deploymentName `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $global:createTopologyTemplate `
        -TemplateParameterFile $global:createTopologyTemplateParameters | Out-Null
    Write-Host "`nCreated ArtifactSource, ServiceTopology and other ADM resources."
}

<#
.SYNOPSIS
Creates a rollout.
#>
function Setup-Rollout
{
    param
    (
        $resourceGroupName,
        $location
    )

    $rolloutName = $resourceGroupName + "Rollout"

    # Create and set permissions for managed identity to deploy to the subscription
    Set-ManagedIdentity $subscriptionId $resourceGroupName $location

    Replace-RolloutPlaceholders $resourceGroupName $location

    Write-Host "`nCreating rollout."
    New-AzResourceGroupDeployment `
        -Name $rolloutName `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $global:createRolloutTemplate `
        -TemplateParameterFile $global:createRolloutTemplateParameters | Out-Null

    Write-Host "`nCreated rollout $rolloutName in resource group $resourceGroupName"

    $rollout = Get-AzDeploymentManagerRollout -ResourceGroupName $resourceGroupName -Name $rolloutName -Verbose

    $rollout
    
    Write-Host "`nThe rollout first deploys the app to the West US region, waits for 5 minutes as part of the Wait step and then deploys to the East US region."
    Write-Host "`nUse the cmdlet 'Get-AzDeploymentManagerRollout -ResourceGroupName $resourceGroupName -Name $rolloutName -Verbose' to track rollout progress."
}

<#
.SYNOPSIS
Sets up an artifact source.
#>
function Setup-ArtifactSource
{
    param
    (
        $resourceGroupName,
        $storageAccountName,
        $artifactSourceName,
        $location
    )

    # Artifacts setup information
    $artifactRoot = "ArtifactRoot"
    $containerName = "artifacts"

    $sasKeyForContainer = ""
    Get-SasForContainer $resourceGroupName  $storageAccountName $containerName $artifactRoot $location ([ref]$sasKeyForContainer) | Out-Null

    return $sasKeyForContainer
}

<#
.SYNOPSIS
Creates a storage account, sets up an Azure Container to be used as ADM artifact source and gets a SAS URI for the container.
#>
function Get-SasForContainer
{
    param
    (
        $resourceGroupName,
        $storageName,
        $storageContainerName,
        $artifactRoot,
        $location,
        [ref] $sasKeyForContainer
    )

    Write-Host "`nCreating storage account $storageName in resource group $resourceGroupName to upload the artifacts."
    New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageName -Location $location -SkuName "Standard_GRS"

    # Get storage account context
    $storageAccountContext = New-AzStorageContext `
        -StorageAccountName $storageName `
        -StorageAccountKey (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageName).Value[0]

    Setup-StorageContainer $resourceGroupName $storageName $containerName $artifactRoot $storageAccountContext

    # Get SAS token for container
    $sasKeyForContainer.Value = New-AzStorageContainerSASToken `
        -Name $storageContainerName `
        -Permission "rl" `
        -StartTime ([System.DateTime]::Now).AddHours(-20) `
        -ExpiryTime ([System.DateTime]::Now).AddHours(48) `
        -Context $storageAccountContext -FullUri
}

<#
.SYNOPSIS
Creates an Azure blob container and uploads the artifacts that are used to deploy the WebApp.
#>
function Setup-StorageContainer
{
    param
    (
        $resourceGroupName,
        $storageName,
        $storageContainerName,
        $artifactRoot,
        $storageAccountContext
    )

    $webAppResourcePrefix = $resourceGroupName + "WebApp"
    $webAppResourcePrefix = $webAppResourcePrefix -replace $global:escapePattern
    $webAppReplacementSymbol = "__WEBAPP_PREFIX__"

    Replace-String $webAppReplacementSymbol $webAppResourcePrefix $global:parametersEUSPath
    Replace-String $webAppReplacementSymbol $webAppResourcePrefix $global:parametersWUSPath

    $container = New-AzStorageContainer -Name $storageContainerName -Context $storageAccountContext

    Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccountContext -File $global:parametersWUSPath -Blob $global:parametersWUSPath -Force
    Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccountContext -File $global:parametersEUSPath -Blob $global:parametersEUSPath -Force
    Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccountContext -File $global:templatePath -Blob $global:templatePath -Force
    Set-AzStorageBlobContent -Container $storageContainerName -Context $storageAccountContext -File $global:appPackageRelativePath -Blob $global:appPackageRelativePath -Force

    Write-Host "`nUploaded artifacts to the storage account into container $storageContainerName."
}

<#
.SYNOPSIS
Replaces the placeholders in the ARM parameters file with the inputs to the script and created dependent resource information. 
This parameters file is used to create the ADM ServiceTopology and dependent resources.
#>
function Replace-TopologyPlaceHolders
{
    param
    (
        $namePrefix,
        $location,
        $artifactSourceSASLocation,
        $subscriptionId
    )

    Replace-String "__RESOURCE_GROUP_NAME__" $namePrefix $global:createTopologyTemplateParameters
    Replace-String "__LOCATION__" $location $global:createTopologyTemplateParameters
    Replace-String "__ARTIFACT_SOURCE_SAS_URI__" $artifactSourceSASLocation $global:createTopologyTemplateParameters
    Replace-String "__TARGET_SUBSCRIPTION_ID__" $subscriptionId $global:createTopologyTemplateParameters
}

<#
.SYNOPSIS
Replaces the placeholders in the ARM parameters file with the inputs to the script and created dependent resource information. 
This parameters file is used to create the ADM Rollout.
#>
function Replace-RolloutPlaceholders
{
    param
    (
        $namePrefix,
        $location
    )

    Replace-String "__RESOURCE_GROUP_NAME__" $namePrefix $global:createRolloutTemplateParameters
    Replace-String "__LOCATION__" $location $global:createRolloutTemplateParameters
}

<#
.SYNOPSIS
Replaces a string in a file with the given replacement value. 
#>
function Replace-String
{
    param 
    (
        $replacementSymbol,
        $replacementValue,
        $file
    )

    $content = Get-Content($file)
    $content = $content.replace($replacementSymbol, $replacementValue)
    $content | out-file $file -encoding UTF8
}

<#
.SYNOPSIS
Creates a User Assigned Identity in the input subscription and creates a role assignment at the subscription
level for that Identity to have permissions to deploy resources to the subscription. 
ADM Rollout deploys the WebApp using this Identity.
#>
function Set-ManagedIdentity
{
    param
    (
        $subscriptionId,
        $resourceGroupName,
        $location
    )

    # Create identity for rollout
    $identityName = $resourceGroupName + "Identity"

    $ErrorActionPreference = "SilentlyContinue"
    $identity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name $identityName
    $Error.Clear()

    if ($identity -eq $null)
    {
        $identity = New-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name $identityName -Location $location

        Write-Host "`nCreated new user assigned identity $identityName in resource group $resourceGroupName for use in the rollout."

        # Allow time for MSI to take effect before role assignment
        Start-Sleep 120
    }

    $identityScope = "/subscriptions/" + $subscriptionId

    $roleAssignment = Get-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName "Contributor" -Scope $identityScope

    if ($roleAssignment -eq $null)
    {
        New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName "Contributor" -Scope $identityScope | Out-Null

        Write-Host "`nA new role assignment has been added as a Contributor with subscription scope to let the user assigned identity deploy resources into this subscription."

        Start-Sleep 30
    }
}

$targetResourceGroupNameWUS = $resourceGroupName + "ServiceWUSrg"
$targetResourceGroupNameEUS = $resourceGroupName + "ServiceEUSrg"

try {
    Write-Host "Operating on subscription $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId | Out-Null

    Setup-EndToEnd $subscriptionId $resourceGroupName $location $targetResourceGroupNameWUS $targetResourceGroupNameEUS
}
catch {
    $ex = $_.Exception
    $errorMessage = $_.Exception.Message

    Write-Host "Error encountered. Deleting created resources."
    Remove-AzResourceGroup -Name $resourceGroupName -Force | Out-Null
    Remove-AzResourceGroup -Name $targetResourceGroupNameWUS -Force | Out-Null
    Remove-AzResourceGroup -Name $targetResourceGroupNameEUS -Force | Out-Null
    Write-Host "Deleted created resources."

    Write-Error "Error: $errorMessage"

    throw $ex
}
