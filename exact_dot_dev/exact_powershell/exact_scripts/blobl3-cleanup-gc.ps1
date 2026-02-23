# Run the following:
# CloudBuildLogs
# | where PreciseTimeStamp > ago(7d)
# | where Service == 'CacheGCWorker'
# | where Message has 'RocksDbException'
# | extend GcInstance = extract("gc-([A-Za-z0-9-]+)-[0-9]+-.*", 1, PodName)
# | summarize max(PreciseTimeStamp) by GcInstance
az login --tenant pme.gbl.msidentity.com

$resourceGroups = @(
)

$Subscription = "2ab82c67-48f1-42ca-a817-67f4013eca86"

foreach ($resourceGroup in $resourceGroups) {
  $targetStorageAccount = az storage account list --subscription $Subscription --resource-group $resourceGroup | ConvertFrom-Json | Where-Object { $_.name.Substring(10).StartsWith("00000") } | ForEach-Object { $_.name } | Select-Object -First 1

  if ($targetStorageAccount) {
    $containers = az storage container list --subscription $Subscription --account-name $targetStorageAccount | ConvertFrom-Json

    $targetContainer = $containers | Where-Object { $_.name -like "checkpoints-*" } | ForEach-Object { $_.name } | Select-Object -First 1

    if ($targetContainer) {
      Write-Host "Deleting container: $($targetContainer) in storage account: $($targetStorageAccount)"
      az storage container delete --subscription $Subscription --name $targetContainer --account-name $targetStorageAccount
      Write-Host "Deleted container: $($targetContainer) in storage account: $($targetStorageAccount)"
    }
    else {
      Write-Host "No container with prefix 'checkpoints-' found in storage account: $($targetStorageAccount)"
    }
  }
  else {
    Write-Host "No storage account with '00000' found in resource group: $resourceGroup"
  }
}