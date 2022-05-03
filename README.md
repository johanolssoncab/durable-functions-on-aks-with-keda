# Azure Durable Functions V4 in AKS

> :warning: **Secrets**: This repository does **NOT** currently contain any secret.
> **Secrets** is being produced by **`setupAzure.ps1`** and is stored in the **`local.settings.json`** file.
> **Secrets** is being produced as a base64 encoded **secret** in the **`.yaml`** file located in the **`manifest`** directory (after running the **`createManifestAndPushToACR.ps1`** script).
> Above mentioned files is only for local development purpose.
> You have been warned!

## Prerequisites

- Azure CLI
- Azure Functions Core Tools
- kubectl
- Docker

## Application

The Application `LoremText` located in the `/src` folder is a Azure Function V4 project. The application ingest(generates) sentences and triggers a Fan Out Orchestration that will remove all vowels from the sentence.

The project consist of 4 Functions.

1. Function: `GenerateText`

   - HttpTrigger (Route: `api/text`)
     - Generating random sentences and is publishing them on a Storage Account Queue named `text-submitted`

2. Function: `TextProcessor`

   - QueueTrigger
     - Reads messages from the queue named `text-submitted` and is triggering the orchestration `GetWordsWithoutVowels`

3. Function: `GetWordsWithoutVowels`

   - OrchestrationTrigger
     - Ingest a sentence and splits the sentence by `<space>` and Fans out to the ActivityTrigger `RemoveVowels`. The function then Fans In and is returning the sentence without vowels.

4. Function: `RemoveVowels`

   - ActivityTrigger
     - Ingests a word and will remove and return the word without any vowels.

## Infrastructure

The infrastructure needed for this is:

1. Resource Group
2. Storage Account
3. Storage Account Queue
4. Azure Container Registry
5. Azure Kubernetes Service (AKS)

To setup this infrastructure you have two options:

1. Run the `setupAzure.ps1` script.

   - This script will prompt for any input needed.

2. Setup the infrastructure manually following the steps below.

### Manually setup the infrastructure

1. Setup names for resources

   ```powershell
   $subscription = "<Azure Subscription Name>"
   $resourceGroupName = "<Azure Resource Group Name>"
   $location = "westeurope"
   $storageAccountName "<Azure Storage Account Name>"
   $containerRegistryName = "<Azure Container Registry Name>"
   $aksName = "<Azure Kubernetes Service Name>"
   ```

2. Login to Azure

   ```powershell
   az login
   ```

3. Set Azure Subscription

   ```powershell
     az account set --subscription "$subscription"
   ```

4. Create Resource Group

   ```powershell
   az group create --name $resourceGroupName --location $location -o none
   ```

5. Create Container Registry

   ```powershell
   az acr create `
       --resource-group $resourceGroupName `
       --name $containerRegistryName `
       --sku Basic `
       --admin-enabled true

   az acr identity assign `
       --identities [system] `
       --name $containerRegistryName
   ```

6. Create Storage Account

   ```powershell
   az storage account create `
       --resource-group $resourceGroupName `
       --name $storageAccountName `
       --location $location `
       --kind "StorageV2" `
       --sku "Standard_LRS" `
       --access-tier "hot" `
       --https-only "true"
   ```

7. Create Storage Account Queue

   ```powershell
   $queueName = "text-submitted"

   $storageAccountKey = $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query "[0].value") -replace '"', ''

   $storageAccountConnectionString = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$storageAccountKey;EndpointSuffix=core.windows.net"

   az storage queue create `
       --name $queueName `
       --account-key $storageAccountKey `
       --account-name $storageAccountName `
       --connection-string $storageAccountConnectionString
   ```

8. Create Azure Kubernetes Service

   ```powershell
   az aks create `
       --resource-group $resourceGroupName `
       --name $aksName `
       --node-count 1 `
       --generate-ssh-keys `
       --network-plugin azure

   az aks update --resource-group $resourceGroupName --name $aksName --attach-acr $containerRegistryName

   az aks get-credentials -g $resourceGroupName -n $aksName

   #setting kubectl to use the newly created context
   kubectl config use-context $aksName
   ```

9. Install KEDA

   ```powershell
   #setting kubectl to use the newly created context
   kubectl config use-context $aksName

   func kubernetes install --namespace keda
   ```

10. Replace `UseDevelopmentStorage=true` in the `local.settings.json`

    Get the storage account connection string by running:

    ```powershell
    $storageAccountKey = $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query "[0].value") -replace '"', ''

    $storageAccountConnectionString = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$storageAccountKey;EndpointSuffix=core.windows.net"

    Write-Output $storageAccountConnectionString
    ```

    Take the output and replace the `UseDevelopmentStorage=true` text in the `local.settings.json` file.

## Create image and manifest

To create the docker image and manifest you have two options.

1. Run the `createManifestAndPushToACR.ps1` script.
2. Do it manually following the steps below.

### Manually create image and manifest

1. Setup names for resources

   ```powershell
     $subscription = "<Azure Subscription Name>"
     $containerRegistryName = "<Azure Container Registry Name From Before>"
   ```

2. Login to Azure

   ```powershell
   az login
   ```

3. Set Azure Subscription

   ```powershell
     az account set --subscription "$subscription"
   ```

4. Get the ACR login server and set image name

   ```powershell
   $loginServer = $(az acr show --name $containerRegistryName -o json | ConvertFrom-Json).loginserver

   $imageName = "$loginServer/lorem-text-processor:latest"
   ```

5. Build docker image

   Use powershell to navigate to the root directory where the [`Dockerfile`](src/LoremText/Dockerfile) is located .

   ```powershell
   docker build -t $imageName .
   ```

6. Login to ACR

   ```powershell
   az acr login --name $containerRegistryName
   ```

7. Push image to ACR

   ```powershell
   docker push $imageName
   ```

8. Generate the manifest `.yaml`

   Use powershell to navigate to the root directory where the [`Azure function project`](src/LoremText/) is located.

   ```powershell
   func kubernetes deploy --name lorem-text-functions --image-name "$imageName" --min-replicas 1 --dry-run > "./manifests/lorem-text-function-deploy.yaml"
   ```

#### Manifest

The manifest for the Azure function is a bit special and consist of two deployments and services (http service, and the QueueTrigger/orchestration). Each deployment activates separate functions using the notation below

```yaml
env:
  - name: AzureFunctionsJobHost__functions__0
    value: GenerateText
```

this specifies which functions that should be available to that service, other functions is disabled.

There is a pretty simple explanation for this. The QueueTigger/Orchestration can scale independently using the KEDA scale controller installed earlier in this process.

## Deploy to AKS

To deploy the application to the AKS cluster created earlier you can do the following.

1. Check kubectl configuration

   Make sure your kubectl is targeting the correct context.

   ```powershell
   kubectl config get-contexts
   ```

   > The `CURRENT` column should have a star (\*) assigned to the context you've created earlier.

2. Deploy to AKS

   Run the following command to deploy the application to AKS.

   ```powershell
   cd src/LoremText/manifests

   kubectl apply -f ./lorem-text-function-deploy.yaml
   ```

3. Get External IP

   ```powershell
     kubectl get services
   ```

   The result should look something like this, browse to the **20.86.195.138** to verify the function app is up and running.

   | NAME                      | TYPE         | CLUSTER-IP   | EXTERNAL-IP       | PORT(S)      |
   | ------------------------- | ------------ | ------------ | ----------------- | ------------ |
   | kubernetes                | ClusterIP    | 10.0.0.1     | <none>            | 443/TCP      |
   | lorem-text-functions-http | LoadBalancer | 10.0.110.209 | **20.86.195.138** | 80:31184/TCP |

4. Trigger GenerateText Function

   Browse to the `/api/text` route of the external ip address you got in the previous step.

   The message that was generated should be returned to the browser.

5. Verify KEDA scaling

   Run the following to watch all pods and see basic statuses of them.

   ```powershell
   kubectl get pods -w
   ```

   You can verify the scale controller by spamming the `/api/text` route and see that `lorem-text-functions-` pod will scale out depending on the queue depth of the queue created earlier.

   > The `lorem-text-functions-http` will not scale as this is only the http endpoint (Generate Text) function that will deliver messages to the queue.

6. Look at the application log

   Check logs of a pod using theses commands:

   **Http Trigger Pod**

   ```powershell
   kubectl logs -l app=lorem-text-functions-http --follow --tail 1000
   ```

   **Orchestration Pod**

   ```powershell
   kubectl logs -l app=lorem-text-functions --follow --tail 1000
   ```

## Clean up resources

1. Remove the resource group you've created.

   ```powershell
   az group delete --name "<Resource Group Name>" --yes
   ```

## Other notes

The [Text Generator HttpTrigger](src/LoremText/TextGenerator.cs) and the [Orchestration functions](src/LoremText/TextOrchestration.cs) cannot be in the same class. This causes the container to not know which Pod is responsible for handling the Orchestration with the error message `Metadata generation failed for function <function-name>`.

## Suggestions and|or feedback

I don't have much experience with either kubernetes and/or containers.so feedback to make the `manifest.yml` easier to read or some tips would be awesome!

Is there steps i can simplify and|or skip, let me know.

Reach out to me on this Github repo issues or in the Teams app!

Take care!
