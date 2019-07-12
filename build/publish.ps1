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
$srcDir     = Join-FSPath $thisDir '..\src\psbuild' -Resolve

if(!(Test-Path $publishDir)) { mkdir $publishDir | Out-Null }

Publish-Module basicutils $publishDir -InputDir $srcDir 
Publish-Module pathutils $publishDir -InputDir $srcDir 
Publish-Module netbuild $publishDir -InputDir $srcDir 
Publish-Module nettest $publishDir  -InputDir $srcDir 
Publish-Module netpack $publishDir  -InputDir $srcDir 
Publish-Module netscaffold $publishDir -InputDir $srcDir 
Publish-Module vsdata $publishDir  -InputDir $srcDir 
