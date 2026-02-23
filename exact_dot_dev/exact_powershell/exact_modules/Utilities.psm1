function Assert-Path {
  <#
  .SYNOPSIS
      Calls Resolve-Path but works for files that don't exist.
  .REMARKS
      From http://devhawk.net/blog/2010/1/22/fixing-powershells-busted-resolve-path-cmdlet
  #>
  param (
    [string] $FileName
  )

  $FileName = Resolve-Path $FileName -ErrorAction SilentlyContinue `
    -ErrorVariable _frperror
  if (-not($FileName)) {
    $FileName = $_frperror[0].TargetObject
  }

  return $FileName
}
