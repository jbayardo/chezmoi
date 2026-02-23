function global:bc { .\bxl -cache }

function global:bcm { .\bxl -cache -minimal }

function global:bt {
  $TestName = $args
  $regex = "((\[Fact\])|(\[Theory\]\s*(\[InlineData\([^\)]+\)\]\s*)*))\s*public.*?$TestName\("
  Write-Output "Regex: $regex"
  $Files = rg -iU --files-with-matches -g '*.cs' $regex | ForEach-Object { $_.Trim() | Resolve-Path }
  
  foreach ($file in $Files) {
    Write-Output "File: $file"
    $content = Get-Content $file
    $Match = (($content | Select-String "namespace") -split ' ')[1]
    Write-Output "Content: $content"
    Write-Output $Match
  }
  # $Namespace = rg -U --no-filename --no-line-number -g '*.cs' "namespace\s+([^\s]+)" $Files[0] | ForEach-Object { $_.Trim() }

  # Write-Host $Namespace
}

function global:adodbuild {
  $branch = (git rev-parse --abbrev-ref HEAD | Out-String).Trim()
  $dropName = $(Get-Date -UFormat "%Y%m%d%H%M%S")
  .\bxl -minimal -DeployConfig Release
  .\dropout $dropName
  $qualifiedDropName = "jubayard/$dropName"
  az pipelines run --detect --project Domino --id 13959 --branch $branch --parameters "DropName=$qualifiedDropName"
}

# TODO: run bxl test from name only
# TODO: build and test aliases
# TODO: build bisect (replace tools or engine version)
