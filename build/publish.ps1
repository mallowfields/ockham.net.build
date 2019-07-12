Import-Module "$PSScriptRoot\version.psm1"
$version = $module_version
 
$thisDir = $PSScriptRoot

function Join-FSPath ($BasePath, $RelativePath, [Switch]$Resolve) {
  $result = [System.IO.Path]::Combine($BasePath, $RelativePath)
  if($Resolve) { 
    $result = [System.IO.Path]::GetFullPath($result)
  }
  $result
}

function Publish-Module {

  param([string]$ModuleName, [string]$OutputDir, [string]$InputDir)

  Write-Host "Publishing $ModuleName.psm1 to $OutputDir"

  if($null -eq $InputDir) { $InputDir = '.' }
  $inDir   = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($thisDir,$InputDir))
  $content = [System.IO.File]::ReadAllText((Join-FSPath $inDir "$ModuleName.psm1"))

  $content = @"
Write-Host "Loading $ModuleName version $version" 


"@ + $content;

  if (!(Test-Path $OutputDir)) { mkdir $OutputDir | Out-Null }
  $outFile = Join-FSPath $OutputDir "$ModuleName.psm1"
  [System.IO.File]::WriteAllText($outFile, $content)
}

$publishDir = Join-FSPath $thisDir ..\publish -Resolve
$toolsDir   = Join-FSPath $thisDir ..\ref\ockham.net\tools
$srcDir     = Join-FSPath $thisDir '..\src\psbuild' -Resolve

foreach($dir in @($publishDir, $toolsDir)) {
  if(!(Test-Path $dir)) { mkdir $dir | Out-Null }

  Publish-Module basicutils $dir -InputDir $srcDir 
  Publish-Module pathutils $dir -InputDir $srcDir 
  Publish-Module netbuild $dir -InputDir $srcDir 
  Publish-Module nettest $dir  -InputDir $srcDir 
  Publish-Module netpack $dir  -InputDir $srcDir 
  Publish-Module netscaffold $dir -InputDir $srcDir 
  Publish-Module vsdata $dir  -InputDir $srcDir 
}
