param(
  [Parameter(Mandatory=$false)]
  [string]$filter = "*.cs"
)

$files = Get-ChildItem -Recurse -Filter $filter -File
$contents = $files | ForEach-Object -Parallel {
  $file = $_

  $content = Get-Content $file
  $content = $content.Replace("\r\n", "\n")
  $content = $content.Replace("\n", [Environment]::NewLine)

  @{
    File = $file
    Content = $content
  }
}

$contents | ForEach-Object {
  $file = $_.File | Resolve-Path -Relative
  $content = $_.Content

  Write-Output "---- Start file $file ----"
  Write-Output $content
  Write-Output "---- End file $file ----"
}