[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $subscription,
    [Parameter(Mandatory = $false)]
    [string]
    $containerRegistryName,
    [Parameter(Mandatory = $false)]
    [string]
    $dockerfileDirectory = "$PSScriptRoot/src/LoremText"
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

#Set container registry name
if (!$containerRegistryName) {
    $containerRegistryName = Read-Host "Enter a Container registry name:"
}

$loginServer = $(az acr show --name $containerRegistryName -o json | ConvertFrom-Json).loginserver
$imageName = "$loginServer/lorem-text-processor:latest"

Write-Output "Building '$imageName'"
docker build -t $imageName $dockerfileDirectory

Write-Output "Signing in to ACR, this may take some time..."
az acr login --name $containerRegistryName

Write-Output "Pushing '$imageName' to '$containerRegistryName'"
docker push $imageName

$oldLocation = $PSScriptRoot
Set-Location -Path $dockerfileDirectory
func kubernetes deploy --name lorem-text-functions --image-name "$imageName" --min-replicas 1 --dry-run > "./manifests/lorem-text-function-deploy.yaml"
Set-Location -Path $oldLocation