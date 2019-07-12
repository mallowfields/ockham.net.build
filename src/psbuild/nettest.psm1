#------------------------------
# Imports
#------------------------------
if($null -eq $(Get-Module basicutils)) { Import-Module (Join-Path $PSScriptRoot 'basicutils.psm1')  }
Confirm-Module Test-FSPath pathutils
Confirm-Module Test-FSPath netbuild
 
#------------------------------
# Exported functions
#------------------------------ 
<#
    .SYNOPSIS
    Run GenAPI.exe and git diff to compare the API surfaces of a reference project and implementation project
#>
function Test-API {
  param([string]$SolutionDirectory, [string]$ModuleName, [string]$ToolsPath, [string]$Configuration, [string]$OutputPath, [switch]$Quiet)

  $apiDir = [System.IO.Path]::Combine($SolutionDirectory, 'ref', $moduleName)
  $srcDir = [System.IO.Path]::Combine($SolutionDirectory, 'src', $moduleName)

  $genApi = "$ToolsPath\bin\GenAPI\GenAPI.exe"

  function _Warn ($message) {
    if (!$Quiet) { Write-Warning $message }
    return
  }

  if (!(Test-Path $apiDir)) {  
    return _Warn "Reference project not found. Expected path: $apiDir" 
  }
     
  $apiBinDir = "$apiDir\bin\$Configuration"
  if (!(Test-Path $apiBinDir)) {
    return _Warn "Reference project bin output path not found. Expected path: $apiBinDir" 
  }

  if (!(Test-Path $OutputPath)) { mkdir $OutputPath | Out-Null }

  $apiAsmName = Get-AssemblyName $apiDir
  $apiAsmPath = Get-AssemblyPath $apiBinDir $apiAsmName

  if (Test-IsEmpty $apiAsmPath) {
    foreach ($childDir in @(Get-ChildItem $apiBinDir -Directory)) {
      $apiAsmPath = Get-AssemblyPath $($childDir.FullName) $apiAsmName
      if ($null -ne $apiAsmPath) { break; }
    } 
  }
    
  if (Test-IsEmpty $apiAsmPath) {
    return _Warn "Api assembly $apiAsmName not found in reference bin output path $apiBinDir or any child directories"
  }

  if (!(Test-Path $srcDir)) {
    return _Warn "Source project not found. Expected path: $srcDir"
  }

  $outBin = "$srcDir\bin\$Configuration"
  if (!(Test-Path $outBin)) {
    return _Warn "Source project bin output path not found. Expected path: $outBin"
  }

  $outBinPaths = New-Object System.Collections.Generic.List[string]
  $outAsmName = Get-AssemblyName $srcDir

  $outAsmPath = Get-AssemblyPath $outBin $outAsmName
  if ($null -ne $outAsmPath) {
    # Single output assembly
    $outBinPaths.Add($outAsmPath)
  }
  else {
    foreach ($childDir in @(Get-ChildItem $outBin -Directory)) {
      $outAsmPath = Get-AssemblyPath $($childDir.FullName) $outAsmName
      if ($null -ne $outAsmPath) { 
        $outBinPaths.Add($outAsmPath)
      }
    } 
  }
          
  if ($outBinPaths.Count -eq 0) {
    return _Warn "No assemblies found in source bin output path $outBin"
  }

  if (Test-IsEmpty $OutputPath) {
    $OutputPath = Join-Path $(Join-Path $($env:TEMP) Test) $([Guid]::NewGuid().ToString('n'))
  }
  else {
    Remove-Item "$OutputPath\API*.cs"
    Remove-Item "$OutputPath\API*.diff"
  }

  if (!(Test-Path $OutputPath)) { mkdir $OutputPath | Out-Null }
     
  Write-Host "Generating API files to $OutputPath"

  $apiOut = Join-Path $OutputPath 'API_Ref.cs'

  &$genApi $apiAsmPath -out:$apiOut -apiOnly

  foreach ($binPath in $outBinPaths) {
    $binDir = Split-Path $binPath -Parent
    $itemOut = Join-Path $OutputPath $('API_' + $(Split-Path $binDir -Leaf) + '.cs')
    $diffOut = [regex]::Replace($itemOut, '.cs$', '.diff')
         
    &$genApi $binPath -out:$itemOut -apiOnly
    git diff --no-index $apiOut $itemOut > $diffOut
  }
}

<#
    .SYNOPSIS
    Convert $true to 'Pass', $false to 'Fail'
#>
function Get-ResultVerb ([bool]$Passed) {
  return $(if ($Passed) { 'Pass' } else { 'Fail' })
}
 
<#
    .SYNOPSIS
    Summarize xunit test results and API diff results to a single test output artifact
#>
function Get-TestSummary {
  param([string]$SolutionDirectory, [string]$ModuleName)

  $apiDir = [System.IO.Path]::Combine($SolutionDirectory, 'tests', 'results', $ModuleName, 'api')
  $testsDir = [System.IO.Path]::Combine($SolutionDirectory, 'tests', 'results', $ModuleName, 'unit')
     
  $results = New-Object System.Collections.Generic.List[psobject]
     
  $resultsBaseDir = [System.IO.Path]::Combine($SolutionDirectory, 'tests', 'results')

  if (Test-Path $apiDir) { 
    foreach ($diffFile in (Get-ChildItem $apiDir -Filter '*.diff')) { 
      $itemPassed = $true

      $diffContent = [System.IO.File]::ReadAllText($diffFile.FullName).Trim()
      $itemPassed = $diffContent.Length -eq 0 

      $results.Add((New-Object psobject -Property @{
            Type      = 'API Diff'
            Framework = $diffFile.Name.Substring(4).Replace('.diff', '')
            Result    = $(Get-ResultVerb $itemPassed)
            File      = $diffFile.FullName.Replace($resultsBaseDir, '.')
          }))
    }
  }

  if (Test-Path $testsDir) {
    foreach ($testXml in (Get-ChildItem $testsDir -Filter *.xml)) {
      $itemPassed = $true

      $xTest = New-Object xml
      $xTest.Load($testXml.FullName)
      $failCount = $xTest.DocumentElement.SelectNodes('//test[@result!="Pass"]').Count
      $itemPassed = ($failCount -eq 0)
             
      $results.Add((New-Object psobject -Property @{
            Type      = 'xUnit'
            Framework = $testXml.Name.Split('-')[1].Replace('.xml', '')
            Result    = $(Get-ResultVerb $itemPassed)
            File      = $testXml.FullName.Replace($resultsBaseDir, '.')
          }))
    }
  }

  $results
}


<#
    .SYNOPSIS
    Execute API and/or unit tests, and build an overall test summary

    .PARAMETER ProjectDirectory
    The src directory of the project to test

    .PARAMETER Configuration
    The build configuration to use. Default Release

    .PARAMETER Unit 
    Whether to execute Unit tests

    .PARAMETER API
    Whether to execute API comparison tests
      
    .PARAMETER Clean
    Whether to clean the project before building for API test 

    .PARAMETER BuildProps
    Addition build properties to use when when building for API test

    .PARAMETER BuildArgs
    Additional build arguments to use when building for API test

#>
function Invoke-Test {

  param([string]$ProjectDirectory, [string]$Configuration, [switch]$Unit, [switch]$API, [switch]$Clean, [hashtable]$BuildProps, [string[]]$BuildArgs)

  if (Test-IsEmpty $ProjectDirectory) {
    $ProjectDirectory = [System.IO.Directory]::GetCurrentDirectory()
  }

  if (Test-IsEmpty $Configuration) {
    $Configuration = 'Release'
  }

  $startTime = [datetime]::Now
  $sw = [System.Diagnostics.Stopwatch]::StartNew()

  $toolsDir = $PSScriptRoot

  Import-Module "$toolsDir\BuildUtils.psm1"
  Import-Module "$toolsDir\TestUtils.psm1"

  $initialDir = Get-CurrentDirectory 
  $solutionDir = Get-SolutionDir $ProjectDirectory
  $solutionName = $(Get-ChildItem "$solutionDir\*.sln" | Select-Object -First 1).BaseName
  $moduleName = ''

  $standardDirNames = @{ src = ''; tests = ''; api = '' }

  $projectParentDirName = Split-Path $ProjectDirectory -Leaf
  if (!$standardDirNames.ContainsKey($projectParentDirName)) {
    $moduleName = $projectParentDirName
  }
  $hasModuleName = Test-IsNotEmpty $moduleName
  
  $apiDir = [System.IO.Path]::Combine( $solutionDir, 'ref'  , $moduleName)
  $srcDir = [System.IO.Path]::Combine( $solutionDir, 'src'  , $moduleName)
  $testDir = [System.IO.Path]::Combine( $solutionDir, 'tests', $moduleName)

  Write-Banner ".NET Test Script" 
  Write-Host " Solution : $solutionName"
  if ($hasModuleName) {  
    Write-Host " Module   : $moduleName"
  } 
  Write-Host " Paths:"
  Write-Host "   Tools       : $toolsDir"
  Write-Host "   Solution    : $solutionDir"
  Write-Host "     Reference : $apiDir"
  Write-Host "     Source    : $srcDir"
  Write-Host "     Test      : $testDir"
  Write-Bar 
 
  if ($Unit) {
    Write-Banner "Running Unit Tests"

    $unitOutDir = [System.IO.Path]::Combine($solutionDir, 'tests', 'results', $moduleName, 'unit')
    
    Set-CurrentDirectory $testDir 
    Remove-Item "$unitOutDir\*.xml" -Force -ErrorAction SilentlyContinue
    dotnet xunit -xml "$unitOutDir\xunit.xml"
  }

  if ($API) { 
    if ($Clean) {
      Write-Banner "Cleaning"
      Invoke-Clean $apiDir  -Configuration $Configuration
      Invoke-Clean $srcDir  -Configuration $Configuration
      Invoke-Clean $testDir -Configuration $Configuration
    }

    #if($Build -or $Clean) {
    Write-Banner "Rebuilding"
    Set-CurrentDirectory $solutionDir    
    dotnet restore

    Invoke-Build $apiDir  -Configuration $Configuration -BuildProps $BuildProps -BuildArgs $BuildArgs 
    Invoke-Build $srcDir  -Configuration $Configuration -BuildProps $BuildProps -BuildArgs $BuildArgs   
    #}
   
    Write-Banner "Checking API surface"
    $apiOutDir = [System.IO.Path]::Combine($solutionDir, 'tests', 'results', $moduleName, 'api')
    Test-API -SolutionDirectory $solutionDir -ModuleName $moduleName -ToolsPath $toolsDir -Configuration $Configuration -OutputPath $apiOutDir
  }

  $sw.Stop()

  if ($Unit -or $API) { 
    Write-Banner "Generating summary"
    $results = Get-TestSummary -SolutionDirectory $solutionDir -ModuleName $moduleName

    $resultsDir = [System.IO.Path]::Combine($solutionDir, 'tests', 'results')

    $resultBaseName = "$resultsDir\result"
    if ($hasModuleName) {
      $resultBaseName = "$resultsDir\result.$moduleName"
    }

    Remove-Item "$resultBaseName.*" -Force -ErrorAction SilentlyContinue

    $fail = (@($results | Where-Object { $_.Result -ne 'Pass' }).Count -gt 0)
    $resultName = $(if ($fail) { 'Failed' } else { 'Passed' })
    $outFile = "$resultBaseName.$($resultName.ToLower()).htm"

    $outDir = Split-Path $outFile -Parent
    if (!(Test-Path $outDir)) { mkdir $outDir | Out-Null }
    $elapsedStr = "$($sw.Elapsed.TotalSeconds.ToString('f3')) s"

    "Solution   : $solutionName" > $outFile
    if ($hasModuleName) {
      "Module     : $moduleName" >> $outFile
    }
    "Result     : $resultName" >> $outFile
    "Start Time : $($startTime.ToString('ddd yyyy-MM-dd HH:mm:ss'))" >> $outFile
    "Elapsed    : $elapsedStr" >> $outFile

    $results | Select-Object Type, Framework, Result, File | Format-Table >> $outFile

    if ($fail) {
      Write-Warning $(
        "****************************************************************************`r`n" +
        "* FAIL!  One or more tests failed. Total elapsed: $elapsedStr `r`n" +
        "****************************************************************************"
      )
    }
    else {
      Write-Host "****************************************************************************"
      Write-Host "* Success!  All tests passed in $elapsedStr "
      Write-Host "****************************************************************************"
    }
  }

  Set-CurrentDirectory $initialDir
}

Export-ModuleMember -Function Test-API, Get-TestSummary, Get-ResultVerb
