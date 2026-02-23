<#
.SYNOPSIS
Runs builds with specified parameters.

.DESCRIPTION
This script runs builds with the specified parameters in CloudBuild.

.PARAMETER Spec
Path to json file with specification of builds to run. If the spec is missing, it's read from the pipeline input.

.PARAMETER Batmon
Specifies the API URL.

.PARAMETER Separate
Indicates whether to run builds separately. By default, builds are not run separately.

.PARAMETER Version
Tools version to use. Must be generated with scoobydoobydoo

.PARAMETER NumBuilds
Specifies the number of builds to run per variant. The default value is 1.

.PARAMETER Username
Specifies the username for tracking. This parameter is optional.

.PARAMETER Blob
Enable Blob cache

.PARAMETER DatacenterWideEphemeral
Enable Datacenter-Wide L2 cache

.PARAMETER BuildWideEphemeral
Enable Build-Wide L2 cache

.PARAMETER CASaaS
Enable CASaaS L2 cache

#>
[CmdletBinding()]
Param(
  [String] $Spec = $null,
  [String] $Batmon = "https://cloudbuild.microsoft.com",
  [ValidateSet('Separate', 'Common', 'Implementation', 'Undefined')]
  [String] $Namespacing = 'Separate',
  [String] $Version = $null,
  [String] $CloudBuildDrop = $null,
  [int] $NumBuilds = 1,
  [String] $Username = $null,
  [Switch] $Blob = $false,
  [Switch] $DatacenterWideEphemeral = $false,
  [Switch] $BuildWideEphemeral = $false,
  [Switch] $CASaaS = $false,
  [String] $OverrideCacheInstance = $null,
  [Switch] $OverrideEngine = $false,
  [Switch] $OverrideRunners = $false
)

# Spec must be a json file with a list of entries like this:
# {
#   "Schedule": "clone",
#   "ReferenceBuildId": "18a4b992-db94-34eb-65f6-682065fb5f7e",
#   "Builders": 12,
#   "Engine": "QuickBuild",
#   "Stamp": "SN_S19",
#   "CacheInstanceOverride": "..."
# }

if ([string]::IsNullOrEmpty($Username)) {
  $Username = "$([Environment]::UserName)_$(Get-Date -Format "yyyyMMddHHmmss")"
}

$Variants = @()
if (![string]::IsNullOrEmpty($Spec) -and (Test-Path -PathType Leaf $Spec)) {
  if ($Spec -like "*.json") {
    $Variants += Get-Content -Path $Spec | ConvertFrom-Json
  }
  elseif ($Spec -like "*.yaml" -or $Spec -like "*.yml") {
    $Variants += Get-Content -Path $Spec | ConvertFrom-Yaml
  }
  elseif ($Spec -like "*.csv") {
    $Variants += Import-Csv -Path $Spec
  }
  elseif ($Spec -like "*.xml") {
    $Variants += Get-Content -Path $Spec | ConvertFrom-Xml
  }
  elseif ($Spec -like "*.kql") {
    $Variants = runq -Query $Spec
  }
  else {
    throw "Spec must be a json file"
  }
}
else {
  foreach ($item in $input) {
    $Variants += $item
  }
}

$BuildXLFlagsBaseline = @(
  # "/incrementalScheduling-", # Incremental scheduling messes with performance
  # "/historicMetadataCache-" # Historic metadata cache messes with performance
);
$BuildXLFlagsBaselineCB = @();
$BuildXLFlagsBaselineRM = @();

$QuickBuildFlagsBaseline = @(
  "-LogCacheClientToKusto" # Ensure cache logs go to Kusto
  # "-notest" # Do not run tests
);
$QuickBuildFlagsBaselineCB = @();
$QuickBuildFlagsBaselineRM = @(
  "-eucu"
  # ,
  # "--AutoDisableCodeSignValidationWhenSigningIsDisabled",
  # "--enablechangelistcc false",
  # "--PushPackagesInBuild false",
  # "--ForceDisableGuardian true",
  # "--buildcop false",
  # "--QTestAttemptCount 1"
);

if (![string]::IsNullOrEmpty($Version)) {
  if ($OverrideEngine) {
    $BuildXLDrop = "https://cloudbuild.artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/0.1.0-$($Version)?root=release/win-x64";
    $QuickBuildDrop = "https://cloudbuild.artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/$($Version)?root=/retail/amd64/ClientTools"
  }

  if ($OverrideRunners) {
    $BuildRunnersDrop = "https://cloudbuild.artifacts.visualstudio.com/DefaultCollection/_apis/drop/drops/$($Version)?root=/retail/amd64/BuildRunners"
  }
}

if (![string]::IsNullOrEmpty($CloudBuildDrop)) {
  $QuickBuildDrop = "$($CloudBuildDrop)?root=/retail/amd64/ClientTools"
  $RedmanDrop = "$($CloudBuildDrop)?root=/retail/amd64/Tools"
  $SourceControlToolsDrop = "$($CloudBuildDrop)?root=/retail/amd64/App/SourceControlTools"
  $WorkflowToolsDrop = "$($CloudBuildDrop)?root=/retail/amd64/App/WorkflowTools"
  $BuildRunnersDrop = "$($CloudBuildDrop)?root=/retail/amd64/App/BuildRunners"
  $SigningToolsDrop = "$($CloudBuildDrop)?root=/retail/amd64/App/SigningTools"
}

$requesters = New-Object System.Collections.Generic.HashSet[string]
$commands = @()

function ComputeCacheWorld($seed, $build) {
  $hasher = [System.Security.Cryptography.SHA256]::Create();
  $identifier = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed));
  $identifier = [System.BitConverter]::ToString($identifier).Replace("-", "").ToLower();
  $hasher.Dispose();

  $universe = $identifier.Substring(0, 8);
  $namespace = $identifier.Substring(9, 4);

  # WARNING: this salt is equivalent to a -eucu build :)
  $salt = "$($identifier)$($build)"

  return @{
    "Salt"      = $salt;	
    "Universe"  = $universe;
    "Namespace" = $namespace;	
  }
}

function Get-RegionCode($stampName) {
  $regions = @{
    "SN" = "South Central US"
    "BN" = "East US 2"
    "BY" = "West US"
    "CO" = "West US"
    "DM" = "Central US"
    "MW" = "West US 2"
    "HK" = "East Asia"
    "CH" = "North Central US"
  }
  $regionCode = $stampName.Substring(0, 2)

  if ($regions.ContainsKey($regionCode)) {
    return $regions[$regionCode].Replace(" ", "").ToLower()
  }
  else {
    return "unknown"
  }
}

function Get-StampShortRegionName($stampName) {
  return $stampName.Substring(0, 2).ToLower();
}

function Get-StampShortName($stampName) {
  return $stampName.Replace("_", "").ToLower();
}

foreach ($variant in $Variants) {
  if ($null -eq $variant.Engine) {
    throw "Engine must be specified. Must be BuildXL or QuickBuild"
  }

  if ([string]::IsNullOrEmpty($variant.CacheInstanceOverride)) {
    $variant | Add-Member -MemberType NoteProperty -Name CacheInstanceOverride -Value $null
    $variant.CacheInstanceOverride = $OverrideCacheInstance
  }

  $environment = 'CB'
  if ($null -ne $variant.Stamp -and ($variant.Stamp.Contains('_V') -or ($variant.Stamp.StartsWith('qci') -and (-not $variant.Stamp.Contains('qci_'))))) {
    $environment = 'RM'
  }

  $schedule = $variant.Schedule
  if ($null -eq $schedule) {
    throw "Schedule must be specified. Must be clone, ondemand, or buddy"
  }

  if ($schedule -eq 'clone') {
    $reference = $variant.ReferenceBuildId;
  }
  else {
    $reference = $variant.Commit;
  }
  if ($null -eq $reference) {
    throw "ReferenceBuildId or Commit must be specified depending on the Schedule"
  }

  $Configurations = @{};

  if ($Blob) {
    $Configurations.Add("Blob", @{
        "Implementation" = "Blob";
        "NumBuilds"      = $NumBuilds;
      });
  }

  if ($DatacenterWideEphemeral) {
    $Configurations.Add("DatacenterWideEphemeral", @{
        "Implementation" = "DatacenterWideEphemeral";
        "NumBuilds"      = $NumBuilds;
      });
  }

  if ($BuildWideEphemeral) {
    $Configurations.Add("BuildWideEphemeral", @{
        "Implementation" = "BuildWideEphemeral";
        "NumBuilds"      = $NumBuilds;
      });
  }

  if ($CASaaS) {
    $Configurations.Add("CASaaSOnly", @{
        "Implementation" = "CASaaSOnly";
        "NumBuilds"      = $NumBuilds;
      });
  }

  foreach ($configuration in $Configurations.GetEnumerator()) {
    $cname = $configuration.Key
    $cvalue = $configuration.Value

    for ($i = 0; $i -lt $cvalue.NumBuilds; $i += 1) {
      $salt = $null;
      $universe = $null;
      $namespace = $null;
      if ($Namespacing -eq 'Separate') {
        # TODO: because we currently don't have namespace hierarchies implemented, we need to use a different universe for
        # each experiment. This is because the ClusterState is partitioned per Universe, not Namespace. So if we don't change
        # the universe, we'll have machines that are in a different logical cache talk to each other.
        $seed = "$($Username)_$($cvalue.Implementation)_$($reference)_$($variant.CacheInstanceOverride)";
        $world = ComputeCacheWorld($seed, $i);
        $salt = $world.Salt;
        $universe = $world.Universe;
        $namespace = $world.Namespace;
      }
      elseif ($Namespacing -eq 'Common') {
        $seed = "$($Username)_$($variant.CacheInstanceOverride)";
        $world = ComputeCacheWorld($seed, 0);
        $salt = $world.Salt;
        $universe = $world.Universe;
        $namespace = $world.Namespace;
      }
      elseif ($Namespacing -eq 'Implementation') {
        $seed = "$($Username)_$($cvalue.Implementation)_$($reference)_$($variant.CacheInstanceOverride)";
        $world = ComputeCacheWorld($seed, 0);
        $salt = $world.Salt;
        $universe = $world.Universe;
        $namespace = $world.Namespace;
      }
      elseif ($Namespacing -eq 'Undefined') {
        $salt = $null;
        $universe = $null;
        $namespace = $null;
      }

      $genericRunnerOptions = $null;
      $specificRunnerOptions = $null;
      $engineFlags = @()

      if ($variant.Engine -eq "QuickBuild") {
        $engineFlags += $QuickBuildFlagsBaseline
        if ($environment -eq 'RM') {
          $engineFlags += $QuickBuildFlagsBaselineRM
        }
        elseif ($environment -eq 'CB') {
          $engineFlags += $QuickBuildFlagsBaselineCB
        }
    
        $engineFlags += @(
          "-Cache $($cvalue.Implementation)"
        );

        if ($null -ne $salt) {
          $engineFlags += "-CacheUniverse $($salt)";
        }

        if ($null -ne $universe -or $null -ne $namespace) {
          $engineFlags += "-CacheNamespace $($universe)_$($namespace)";
        }
      }
      elseif ($variant.Engine -eq "BuildXL") {
        $engineFlags += $BuildXLFlagsBaseline
        if ($environment -eq 'RM') {
          $engineFlags += $BuildXLFlagsBaselineRM
        }
        elseif ($environment -eq 'CB') {
          $engineFlags += $BuildXLFlagsBaselineCB
        }
  
        $engineFlags += @(
          "/p:EnableCacheClientLogFileTelemetry=1"
        );

        $genericRunnerOptions = @{
          "CacheFeatures" = "$($cvalue.Implementation)";
          # "CacheClientLogging" = "1";
        };

        if ($null -ne $salt) {
          $engineFlags += "/p:BUILDXL_FINGERPRINT_SALT=$($salt)";
          $genericRunnerOptions["CacheSalt"] = $salt;
        }

        if ($null -ne $universe) {
          $engineFlags += "/p:BUILDXL_CACHE_UNIVERSE=$($universe)";
          $genericRunnerOptions["CacheUniverse"] = $universe;
        }

        if ($null -ne $namespace) {
          $engineFlags += "/p:BUILDXL_CACHE_NAMESPACE=$($namespace)";
          $genericRunnerOptions["CacheNamespace"] = $namespace;
        }
      }

      if ($null -ne $variant.EngineFlags) {
        $engineFlags += $variant.EngineFlags;
      }

      if ($null -ne $cvalue.EngineFlags) {
        $engineFlags += $cvalue.EngineFlags;
      }
  
      $additionalCommandLineFlags = $engineFlags;
      $additionalCommandLineFlags = $additionalCommandLineFlags -join " ";

      $request = @{
        "ToolPaths"          = @{
        };
        "Requester"          = $Username;
        "Description"        = "$($Username)_$($cname)_$($i)";
        "BuildEngineOptions" = @{
        };
        "SendMail"           = $false;
        "InProbation"        = $true;
      }

      if ($environment -eq 'RM') {
        $request.Add("ComputeProviderOverride", "ResourceManager");
        # $request.Add("ComputePool", "communal-prod-westus-default-pool");
      }
      else {
        $request.Add("ComputeProviderOverride", "Autopilot");
      }

      $cacheInstance = $variant.CacheInstanceOverride
      if ($null -eq $cacheInstance -and ($cvalue.Implementation -eq "Blob" -or $cvalue.Implementation -eq "DatacenterWideEphemeral" -or $cvalue.Implementation -eq "BuildWideEphemeral")) {
        $cacheInstance = "$(Get-StampShortName $variant.Stamp)-prod-$(Get-StampShortRegionName $variant.Stamp)-stdblobl3";
      }

      if ($variant.Engine -eq "QuickBuild") {
        # $request.Add("AdditionalQuickBuildFlags", $additionalCommandLineFlags);
        $request.BuildEngineOptions.Add("Commandlineflags", $additionalCommandLineFlags);
      }
      else {
        $request.BuildEngineOptions.Add("Additionalcommandlineflags", $additionalCommandLineFlags);
      }

      if ($null -ne $variant.Builders) {
        $request.Add("MinBuilders", $variant.Builders);
        $request.Add("MaxBuilders", $variant.Builders);
      }

      if ($null -ne $variant.MinBuilders) {
        $request.Add("MinBuilders", $variant.MinBuilders);
      }

      if ($null -ne $variant.MaxBuilders) {
        $request.Add("MaxBuilders", $variant.MaxBuilders);
      }

      # if ($null -ne $cacheInstance) {
      #   $request.Add("BlobCacheInstanceOverride", $cacheInstance);
      # }

      if ($null -ne $variant.Stamp) {
        $request.Add("StampPreferences", $variant.Stamp);
      }

      if ($null -ne $variant.QuickBuildDrop) {
        $request.ToolPaths.Add("CloudBuildTools", $variant.QuickBuildDrop);
      }
      elseif ($null -ne $QuickBuildDrop) {
        $request.ToolPaths.Add("CloudBuildTools", $QuickBuildDrop);
      }

      if ($null -ne $RedmanDrop) {
        $request.ToolPaths.Add("Redman", $RedmanDrop);
      } 
      elseif ($null -ne $variant.RedmanDrop) {
        $request.ToolPaths.Add("Redman", $variant.RedmanDrop);
      }

      if ($null -ne $BuildXLDrop) {
        $request.ToolPaths.Add("DominoEngine", $BuildXLDrop);
      }
      elseif ($null -ne $variant.BuildXLDrop) {
        $request.ToolPaths.Add("DominoEngine", $variant.BuildXLDrop);
      }

      if ($null -ne $SourceControlToolsDrop) {
        $request.ToolPaths.Add("SourceControlTools", $SourceControlToolsDrop);
      }
      elseif ($null -ne $variant.SourceControlToolsDrop) {
        $request.ToolPaths.Add("SourceControlTools", $variant.SourceControlToolsDrop);
      }

      if ($null -ne $WorkflowToolsDrop) {
        $request.ToolPaths.Add("WorkflowTools", $WorkflowToolsDrop);
      }
      elseif ($null -ne $variant.WorkflowToolsDrop) {
        $request.ToolPaths.Add("WorkflowTools", $variant.WorkflowToolsDrop);
      }

      if ($null -ne $BuildRunnersDrop) {
        $request.ToolPaths.Add("BuildRunners", $BuildRunnersDrop);
      }
      elseif ($null -ne $variant.BuildRunnersDrop) {
        $request.ToolPaths.Add("BuildRunners", $variant.BuildRunnersDrop);
      }

      if ($null -ne $SigningToolsDrop) {
        $request.ToolPaths.Add("SigningTools", $SigningToolsDrop);
      }
      elseif ($null -ne $variant.SigningToolsDrop) {
        $request.ToolPaths.Add("SigningTools", $variant.SigningToolsDrop);
      }

      if ($null -ne $genericRunnerOptions) {
        $request.Add("GenericRunnerOptions", $genericRunnerOptions);
      }

      if ($null -ne $specificRunnerOptions) {
        $request.Add("SpecificRunnerOptions", $specificRunnerOp);
      }

      if ($schedule -eq 'clone') {
        $request.Add("BuildId", $variant.ReferenceBuildId);
      }
      elseif ($schedule -eq 'ondemand' -or $schedule -eq 'buddy') {
        $request.Add("BuildQueue", $variant.Queue);
        $request.Add("ChangeId", $variant.Commit);
      }
      
      if ($null -ne $variant.RmAgentOverrideBlobUrl) {
        $request.Add("RmAgentOverrideBlobUrl", $variant.RmAgentOverrideBlobUrl);
      }

      $item = @{
        "Schedule" = $schedule;
        "Request"  = $request;
      };

      $commands += $item;
      $requesters.Add($Username) | Out-Null;

      if ($i -eq 0) {
        Write-Host "Example for $($cname) ($($i)): $(ConvertTo-Json $item)"
      }
    }
  }
}

while ($true) {
  $forward = read-host "Schedule $($commands.Length) builds?"
  if ($forward -eq "Y" -or $forward -eq "y" -or $forward -eq "Yes" -or $forward -eq "yes") {
    break;
  }

  if ($forward -eq "N" -or $forward -eq "n" -or $forward -eq "No" -or $forward -eq "no") {
    exit;
  }
}

Write-Host "Launching $($commands.Length) builds..."

$Scope = $Batmon
if ($Batmon.Contains("cbci")) {
  $Scope = "https://cbci.microsoft.com"
}

$Token = (az account get-access-token --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 --scope "$Scope/.default" --query accessToken --output tsv).Trim();

# $Token = (Get-MsalToken -TenantId microsoft.com -ClientId a5a5dbed-8a88-40d9-94f3-f62bad35ad07 -RedirectUri "msala5a5dbed-8a88-40d9-94f3-f62bad35ad07://auth" -Scopes "$Batmon/.default" -Interactive).AccessToken

$output = New-Object System.Collections.Generic.List[object]
foreach ($item in Get-Random -Shuffle $commands) {
  $request = $item.Request
  $schedule = $item.Schedule
  if ($schedule -eq 'clone') {
    $Uri = "$batmon/ScheduleBuild/RequestCloneBuild"
  }
  elseif ($schedule -eq 'buddy') {
    $Uri = "$batmon/ScheduleBuild/submit"
    $request.Add("IsBuddyBuild", $true);
  }
  elseif ($schedule -eq 'ondemand') {
    $Uri = "$batmon/ScheduleBuild/submit"
  }

  $body = ConvertTo-Json $request -Compress -Depth 100

  $response = Invoke-WebRequest -SkipCertificateCheck -Uri "$Uri" -Method Post -Body "$body" -ContentType "application/json" -Headers @{"Authorization" = "Bearer $Token" }
  # Response: {"Succeeded":true,"ErrorMessage":"","UniqueSessionId":"8c2c5e35-31bd-4614-86c1-e0358d7c035f","BatmonHost":"qcijubayard.cnc.cbci.microsoft.com","BatmonHostInCorp":"qcijubayard.cnc.cbci.microsoft.com","SubmittedBuilds":[{"UniqueSessionId":"8c2c5e35-31bd-4614-86c1-e0358d7c035f","BuildQueue":"clonebuild_cloudbuild_retail"}]}
  Write-Host "Response: $response"
  $response = ConvertFrom-Json $response
  $item.Add("Response", $response)

  $output.Add($item) | Out-Null;
}

# $output | ConvertTo-Json -Depth 100

# Generate links to <BatmonHost>/build/<UniqueSessionId> and print them
foreach ($item in $output) {
  $response = $item.Response
  if ($response.Succeeded -eq $true) {
    $sessionId = $response.UniqueSessionId
    $batmonHost = $response.BatmonHostInCorp
    Write-Host "Build scheduled successfully: https://$($batmonHost)/build/$($sessionId)"
  }
  else {
    Write-Host "Build scheduling failed: $($response.ErrorMessage)"
  }
}

foreach ($requester in $requesters.GetEnumerator()) {
  Start-Process "$($Batmon)/user/$($requester)"
}
