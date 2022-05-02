[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $subscription,
    [Parameter(Mandatory = $false)]
    [string]
    $resourceGroupName,
    [Parameter(Mandatory = $false)]
    [string]
    $location = "westeurope",
    [Parameter(Mandatory = $false)]
    [string]
    $storageAccountName,
    [Parameter(Mandatory = $false)]
    [string]
    $containerRegistryName,
    [Parameter(Mandatory = $false)]
    [string]
    $aksName
)

#Prompt for login
az login -o none

if (!$subscription) {
    #List all available subscriptions
    $subscriptions = $(az account list --query "[].name" -o table) | Select-Object -Skip 2

    Write-Output "Multiple subscriptions were found."
    Write-Output "Please choose a subscription:"

    1..$subscriptions.Length | foreach-object { Write-Output "$($_): $($subscriptions[$_-1])" }

    [ValidateScript({ $_ -ge 1 -and $_ -le $subscriptions.Length })]
    [int]$number = Read-Host "Press the number to select a subscription"

    if ($?) {
        $subscription = $subscriptions[$number - 1]
        Write-Output "You chose: ${number}: $subscription"
    }
    else {
        Write-Output "Not a valid subscription"
        Exit 1
    }
}

#Set subscription
az account set --subscription "$subscription" -o none

#Set resource group name
if (!$resourceGroupName) {
    $resourceGroupName = Read-Host "Enter a Resource group name:"
}

#Set storage account name
if (!$storageAccountName) {
    $storageAccountName = Read-Host "Enter a storage account name:"
}

#Set container registry name
if (!$containerRegistryName) {
    $containerRegistryName = Read-Host "Enter a Container registry name:"
}

#Set container registry name
if (!$aksName) {
    $aksName = Read-Host "Enter a AKS name:"
}

#Create Resource group
Write-Output "Creating resource group: '$resourceGroupName' in '$location'"
az group create --name $resourceGroupName --location $location -o none

#Creating container registry
Write-Output "Creating container registry"
az acr create --resource-group $resourceGroupName --name $containerRegistryName --sku Basic --admin-enabled true -o none
az acr identity assign --identities [system] --name $containerRegistryName -o none

#Create storage account
Write-Output "Creating storage account: '$storageAccountName' in '$location'"
az storage account create `
    --resource-group $resourceGroupName `
    --name $storageAccountName `
    --location $location `
    --kind "StorageV2" `
    --sku "Standard_LRS" `
    --access-tier "hot" `
    --https-only "true" `
    -o none

#Create storage account queue
$queueName = "text-submitted"
Write-Output "Creating storage account queue: '$queueName' in '$storageAccountName'"
$storageAccountKey = $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query "[0].value") -replace '"', ''
$storageAccountConnectionString = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$storageAccountKey;EndpointSuffix=core.windows.net"

az storage queue create `
    --name $queueName `
    --account-key $storageAccountKey `
    --account-name $storageAccountName `
    --connection-string $storageAccountConnectionString `
    -o none

#Create AKS
Write-Output "Creating AKS with name: '$aksName' in '$location'"
az aks create `
    --resource-group $resourceGroupName `
    --name $aksName `
    --node-count 1 `
    --generate-ssh-keys `
    --network-plugin azure `
    -o none
az aks update --resource-group $resourceGroupName --name $aksName --attach-acr $containerRegistryName

Write-Output "Grabbing credentials to aks and putting them in %USERPROFILE%/.kube/config"
az aks get-credentials -g $resourceGroupName -n $aksName

Write-Output "Setting kubectl context to '$aksname'"
kubectl config use-context $aksName

$currentContext = kubectl config current-context
if ($currentContext -ne $aksName) {
    Write-Output "COULD NOT SET KUBECTL CONTEXT TO '$aksname'. SKIPPING KEDA SETUP"
}
else {
    Write-Output "Installing KEDA scale controller on '$aksname'"
    func kubernetes install --namespace keda
}

#Replace UseDevelopmentStorage=true to connectionstring
Write-Output "Replacing 'UseDevelopmentStorage=true' to storage account connection string in local.settings.json"
$settingsPath = "$PSScriptRoot/src/LoremText/local.settings.json"
$settingsContent = Get-Content -Path $settingsPath -Raw
$settingsContent = $settingsContent.Replace("UseDevelopmentStorage=true", $storageAccountConnectionString)
$settingsContent | Out-File -FilePath $settingsPath
