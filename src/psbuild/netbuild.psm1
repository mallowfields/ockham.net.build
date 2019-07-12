#------------------------------
# Imports
#------------------------------
if($null -eq $(Get-Module basicutils)) { Import-Module (Join-Path $PSScriptRoot 'basicutils.psm1')  }
Confirm-Module Test-FSPath pathutils

#------------------------------
# Internal functions
#------------------------------
#Map of MSBuild operations to corresponding PowerShell operation
# Note: *the keys are regular expressions*
# See https://docs.microsoft.com/en-us/visualstudio/msbuild/msbuild-conditions
$_buildOps = @( 
  @('=='    , ' -eq ' ),
  @('\!='   , ' -ne ' ),
  @(' And ' , ' -and '),
  @(' Or '  , ' -or ' ),
  @('&gt;=' , ' -ge ' ),
  @('&lt;=' , ' -le ' ),
  @('&gt;'  , ' -gt ' ),
  @('&lt;'  , ' -lt ' ),
  @('>='    , ' -ge ' ),
  @('<='    , ' -le ' ),
  @('>'     , ' -gt ' ),
  @('<'     , ' -lt ' )
)

$_msbuildPaths = @{ } 
$_vsYearMap = @{
  2019 = '16.0'
  2017 = '15.0'
  2015 = '14.0'
  2013 = '12.0'
  2012 = '11.0'
  2010 = '10.0'
  2008 = '9.0'
  2005 = '8.0'
  2003 = '7.1'
  2002 = '7.0'
}

#------------------------------
# Internal functions
#------------------------------

<#
    .SYNOPSIS 
    Write a message to the debug stream without prompting the user
#>
function Write-QuietDebug { 
  param([string]$message)

  $dbgPreference = $DebugPreference
  $DebugPreference = 'Continue'
  Write-Debug $message
  $DebugPreference = $dbgPreference
}

<#
  .SYNOPSIS
  Encapsulate implementation details of VS installation to find the most recent msbuild.exe executable
#>
function Find-MSBuildPath {
  param([string]$vsDir)

  if (!(Test-Path $vsDir)) { 
    Write-QuietDebug $($vsDir + ' does not exist')
    return $null; 
  }
    
  Write-QuietDebug $('Searching ' + $vsDir)

  $fileInfo = @(Get-ChildItem $vsDir -Recurse -Filter msbuild.exe | Where-Object { !($_.FullName -match 'amd64') } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
  if ($null -ne $fileInfo) {
    Write-QuietDebug $('Found msbuild.exe at ' + $fileInfo.FullName)
    return $fileInfo.FullName 
  }
  else {
    return $null
  }
} 

#------------------------------
# Exported functions
#------------------------------ 
<#
    .SYNOPSIS
    Find the path to the msbuild executable. Finds the most recent version if neither Year nor InstallName is specified 

    .PARAMETER Refresh
    Research, even if a path was previously found

    .PARAMETER Year
    The Visual Studio year version to use (2017, 2015, etc)

    .PARAMETER InstallName
    The name of the side-by-side Visual Studio installation (supported in VS2017+)
#>
function Get-MSBuildPath {

  [cmdletbinding()]
  param([switch]$Refresh, $Year, [string]$InstallName)

  $hasYear = $null -ne $Year
  $hasInstall = Test-IsNotEmpty $InstallName
  $hasFullKey = $hasYear -and $hasInstall

  if ($hasYear) {
    [int]$intYear = 0
    if (![int]::TryParse($Year.ToString(), [ref]$intYear)) {
      throw New-Object System.ArgumentException "Cannot parse year '$Year' as an integer'", 'Year'
    }
    $Year = $intYear

    if (($Year -lt 2017) -and (!$_vsYearMap.ContainsKey($Year))) {
      throw New-Object System.ArgumentOutOfRangeException Year
    }
  }

  $suffixes = New-Object System.Collections.Generic.List[string]

  if ($hasFullKey) {
    $suffixes.Add('\' + $Year + '\' + $InstallName)
  }
  elseif ($hasYear) {
    if ($Year -ge 2017) {
      $suffixes.Add('\' + $Year)
    }
    if ($_vsYearMap.ContainsKey($Year)) {
      $suffixes.Add(' ' + $_vsYearMap[$Year])
    }
  }
  elseif ($hasInstall) {
    foreach ($Year in (2020..2017)) {
      $suffixes.Add('\' + $Year + '\' + $InstallName)
    } 
  }
  else {
    foreach ($Year in (2020..2010)) {
      $suffixes.Add('\' + $Year)
    } 
    foreach ($VersionNum in $_vsYearMap.Values) {
      $suffixes.Add(' ' + $VersionNum)
    } 
  }
     
  $programFilesx86Base = ${env:ProgramFiles(x86)}
  if (Test-IsEmpty $programFilesx86Base) {
    $programFilesx86Base = $env:ProgramFiles
  }

  foreach ($suffix in $suffixes) {

    $tempPath = $null
    if ($_msbuildPaths.ContainsKey($suffix)) {
      $tempPath = $_msbuildPaths[$suffix]
      if (!$Refresh -and (Test-FSPath $tempPath)) {
        Write-QuietDebug $('Retrieving cached path ' + $tempPath)
        return $tempPath
      }
    }
         
    $vsDir = $programFilesx86Base + '\Microsoft Visual Studio' + $suffix
    $tempPath = Find-MSBuildPath $vsDir

    if (Test-FSPath $tempPath) {
      $_msbuildPaths[$suffix] = $tempPath
      return $tempPath
    } 

    # Earlier versions were in own MSBuild Get-ChildItem
    if ($suffix.Trim() -match '^\d+.\d+$') {
      $msBuildDir = $programFilesx86Base + '\MSBuild\' + $suffix.Trim()
      $tempPath = Find-MSBuildPath $msBuildDir

      if (Test-FSPath $tempPath) {
        $_msbuildPaths[$suffix] = $tempPath
        return $tempPath
      }
    } 
  } 
}

<#
    .SYNOPSIS
    Construct a list of command line arguments from the configuration name, project properties, and arbitrary additional arguments

    .PARAMETER ProjectFileName
    The file name of the project. If ommitted, default msbuild / dotnet build behavior will find first project in the current directory

    .PARAMETER Configuration
    The configuration name to build (Debug, Release, etc)

    .PARAMETER BuildProps
    A hashtable of project / build properties to inject

    .PARAMETER BuidArgs
    Additional arbitrary command line arguments

    .PARAMETER MSBuild
    Construct arguments to be passed directly to msbuild.exe instead of to dotnet.exe
#>
function Join-BuildArgs {

  param([string]$ProjectFileName, [string]$Configuration, [hashtable]$BuildProps, [string[]]$BuildArgs, [switch]$MSBuild)

  $allArgs = New-Object System.Collections.Generic.List[string]

  if ($MSBuild) {
    # Args to msbuild.exe
    if (Test-IsNotEmpty $ProjectFileName) {
      $allArgs.Add($ProjectFileName)
    }
    $allArgs.Add("/p`:Configuration=$Configuration")  
  }
  else {
    # Args to dotnet.exe
    $allArgs.Add('build')
    if (Test-IsNotEmpty $ProjectFileName) {
      $allArgs.Add($ProjectFileName)
    }
    $allArgs.Add('-c')
    $allArgs.Add($Configuration)
  }
    
  if ($null -ne $BuildProps) {
    foreach ($k in $BuildProps.Keys) {
      $propArg = "/p`:$k=" + $BuildProps[$k].ToString()
      $allArgs.Add($propArg)
    } 
  }
    
  if ($null -ne $BuildArgs) {
    $allArgs.AddRange($BuildArgs)
  }

  # The comma in front causes the array to be returned intact rather than as a series of pipe elements
  return , $allArgs.ToArray()
}

<#
    .SYNOPSIS
    Get and verify the existence of a project file with the specified file name, or within the specified directory
#>
function Get-ProjectFile {
  param([string]$ProjectPath)

  if (Test-IsEmpty $ProjectPath) {
    $ProjectPath = Get-CurrentDirectory
  }
  elseif (!($ProjectPath -match '^(\\\\|[A-Z]:)')) {
    $ProjectPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($(Get-CurrentDirectory), $ProjectPath))
  }

  if (!(Test-FSPath $ProjectPath)) {
    if ([System.IO.Path]::GetExtension($ProjectPath) -notlike '*proj') {
      $projFiles = Get-ChildItem "$ProjectPath.*proj"
      if ($projFiles.Count -gt 0) {
        return $projFiles[0].FullName
      }
    }

    Write-Error "Project file $ProjectPath not found"
    return 
  }
     
  if ([System.IO.Directory]::Exists($ProjectPath)) {
    $projFiles = [System.IO.Directory]::GetFiles($ProjectPath, '*.*proj')
    if ($projFiles.Count -gt 0) {
      $ProjectPath = $projFiles[0]
      Write-Host "Using project file $ProjectPath"
    }
    else {
      Write-Error "No project file found in directory $ProjectPath"
      return
    }
  }
  elseif ([System.IO.File]::Exists($ProjectPath)) {
    return $ProjectPath
  }
  else {
    Write-Error "Path $ProjectPath not found"
    return 
  } 

  return $ProjectPath
}

<#
    .SYNOPSIS
    Find the solution directory containing the start path
#>
function Get-SolutionDir {
  param([string]$StartPath)

  $startDir = Join-Path $StartPath . -Resolve
  $tempDir = $startDir 
  $continue = $true
  while ($continue) {
    $slnFile = Get-ChildItem $tempDir -Filter *.sln | Select-Object -First 1
    if ($null -ne $slnFile) {
      return $tempDir
    }
    else {
      $tempParent = Split-Path $tempDir -Parent
      if ($tempParent -eq $tempDir) {
        $continue = $false
      }
      else {
        $tempDir = $tempParent
      }
    } 
  }

  Write-Error "No solution file found in any directory containing start path $startDir"
}
 
<#
    .SYNOPSIS 
    Substitute current values of existing build properties into a raw build property value expression
#>
function Convert-BuildExpression {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RawString, 
        
    [Parameter(Mandatory = $false)]
    [hashtable]$BuildProps
  )

  if (Test-IsEmpty $RawString) { return $null }
  $result = $RawString
  foreach ($k in $BuildProps.Keys) {
    $result = $result.Replace('$(' + $k + ')', $BuildProps[$k])
  }

  # Now remove any remaining property expressions (they refer to undefined properties)
  $result = [regex]::Replace($result, '\$\(\w*\)', '')

  return $result
}

<#
    .SYNOPSIS 
    Invoke an msbuild condition expression to determine if it is true or false    
#>
function Invoke-BuildExpression {
  param([string]$Expression) 

  foreach ($pair in $_buildOps) {
    $Expression = [regex]::Replace($Expression, $pair[0], $pair[1], 'IgnoreCase') # $Expression.Replace($k, $_buildOps[$k], [StringComparer]::InvariantCultureIgnoreCase)
  }

  $result = $null
  try {
    $result = Invoke-Expression $Expression
  }
  catch { <# ignore #> }

  return $result
}
 
<#
    .SYNOPSIS
    Test an msbuild element condition expression. *Returns true if expression is $null, false if expression is non-null but empty*
#>
function Test-BuildCondition {
  param([object]$Source, [hashtable]$BuildProps)

  if ($null -eq $Source) { return $true; } # No condition, so do include element
  if ($Source -is [System.Xml.XmlElement]) { return Test-BuildCondition $Source.Condition $BuildProps }
  if ($Source -is [string]) {
    $convertedExpression = Convert-BuildExpression $Source $BuildProps
    return Invoke-BuildExpression $convertedExpression
  }
  throw (New-Object System.ArgumentException "Source")
}

<#
    .SYNOPSIS
    Get the resolved build properties from a project, walking all references, substituting
    values in expressions, and evaluating conditions on both property groups and properties
#>
function Get-ProjectProperties {
  param([string]$ProjectPath, [hashtable]$BuildProps)

  $props = @{ }
  $x = New-Object xml
  $x.Load($ProjectPath)
  if ($null -eq $BuildProps) { 
    $BuildProps = @{ }
  }
     
  foreach ($childNode in $x.DocumentElement.ChildNodes) {
    if ($childNode -isnot [System.Xml.XmlElement]) { continue; }
    if (!(Test-BuildCondition $childNode $BuildProps)) { continue; } 

    if ($childNode.Name -eq 'PropertyGroup') { 
      foreach ($propNode in $childNode.ChildNodes) {
        if ($propNode -isnot [System.Xml.XmlElement]) { continue; }
        if (!(Test-BuildCondition $propNode $BuildProps)) { continue; } 
        $BuildProps[$propNode.Name] = $props[$propNode.Name] = Convert-BuildExpression $propNode.InnerText $BuildProps
      }
    }
    elseif ($childNode.Name -eq 'Import') { 
      $relativePath = $childNode.Project
      $fullPath = $(Join-Path $(Split-Path $ProjectPath -Parent) $relativePath -Resolve -ErrorAction SilentlyContinue)
      if (Test-FSPath $fullPath) {
        $subProps = Get-ProjectProperties $fullPath -BuildProps $BuildProps
        foreach ($key in $subProps.Keys) {
          $BuildProps[$key] = $props[$key] = $subProps[$key]
        }
      }
    }
  } 

  return $props
}


<#
    .SYNOPSIS 
    Find the actual file name and XPath where a project property is first defined. This 
    walks up referenced projects to any depth
#>
function Find-ProjectProperty {
  param(
    [string]$ProjectPath,
    [string]$PropertyName,
    [hashtable]$ProjectProperties
  )

  if (!(Test-Path $ProjectPath)) {
    Write-Error "Project file '$ProjectPath' not found"
    return 
  }
     
  $projectFullPath = Join-Path $ProjectPath . -Resolve -ErrorAction SilentlyContinue

  if (![System.IO.File]::Exists($projectFullPath)) {
    Write-Error "Project file '$projectFullPath' not found"
    return 
  }

  if ($null -eq $ProjectProperties) { $ProjectProperties = @{ } 
  }

  $xPathElements = New-Object System.Collections.Generic.List[string]  
  $xPathElements.Add('')
  $xPathElements.Add('Project')
     
  $xProject = New-Object xml
  $xProject.Load($projectFullPath)
  $pgIndex = 1 
     
  $resultXPath = ''
  $resultFilePath = $projectFullPath
  $finalResult = $null

  foreach ($childNode in $xProject.DocumentElement.ChildNodes) {
    if ($childNode -isnot [System.Xml.XmlElement]) { continue; }

    if ($childNode.Name -eq 'PropertyGroup') {
        
      if (Test-BuildCondition $childNode $ProjectProperties) { 
        $xPathElements.Add('PropertyGroup[' + $pgIndex + ']')

        foreach ($propNode in $childNode.ChildNodes) { 
          if ($propNode -isnot [System.Xml.XmlElement]) { continue; }
          if (!(Test-BuildCondition $propNode $ProjectProperties)) { continue; } 
          $propValue = $ProjectProperties[$propNode.Name] = Convert-BuildExpression $propNode.InnerText $ProjectProperties

          if ($propNode.Name -eq $PropertyName) {
            $xPathElements.Add($propNode.Name)
            $resultXPath = [string]::Join('/', $xPathElements)
                     
            $finalResult = New-Object psobject -Property @{
              FilePath   = $resultFilePath
              XPath      = $resultXPath
              Expression = $propNode.InnerText
              Value      = $propValue
            } 
          }
        } 

        $xPathElements.RemoveAt($xPathElements.Count - 1) 
      } 

      $pgIndex += 1

    }
    elseif ($childNode.Name -eq 'Import') {
      if (!(Test-BuildCondition $childNode $ProjectProperties)) { continue; }

      $relativePath = $childNode.Project
      $fullPath = $(Join-Path $(Split-Path $ProjectPath -Parent) $relativePath -Resolve -ErrorAction SilentlyContinue)
      if (Test-FSPath $fullPath) {
        $subResult = Find-ProjectProperty $fullPath $PropertyName $ProjectProperties
        if ($null -ne $subResult) {
          $finalResult = $subResult
        }
      }
    }
  } 

  return $finalResult
}


<#
    .SYNOPSIS
    Set the first occurence of the specified project property name
#>
function Set-ProjectProperty {

  param(
    [string]$ProjectPath,
    [string]$PropertyName,
    [string]$Value #,
    # [switch]$Create
  )

  $ProjectPath = Get-ProjectFile $ProjectPath 

  $propInfo = Find-ProjectProperty $ProjectPath $PropertyName

  if ($null -eq $propInfo) {
    <#
        if($Create) {
            $xProject = New-Object xml
            $xProject.PreserveWhitespace = $true
            $xProject.Load($ProjectPath)

            $propGroup = $xProject.DocumentElement.ChildNodes | Where-Object { $_.Name -eq 'PropertyGroup'} | Select-Object -First 1
            if($null -eq $propGroup) {
                # Need to get xmlns if present...
                $propGroup = $xProject.CreateElement('PropertyGroup')
            }

            $xProp = $xProject.SelectSingleNode($propInfo.XPath)
            $xProp.InnerText = $Value

            $xProject.Save($propInfo.FilePath)
        } else {
        #>
    Write-Error "Property $PropertyName not found"
    return
    #} 
  }
  else {
    $xProject = New-Object xml
    $xProject.PreserveWhitespace = $true
    $xProject.Load($propInfo.FilePath)
    $xProp = $xProject.SelectSingleNode($propInfo.XPath)
    $xProp.InnerText = $Value

    $xProject.Save($propInfo.FilePath)
  } 
}
 
<#
    .SYNOPSIS
    Update a version number element on a target project. Correctly updates the applicable referenced
    file if the version numbers are in a separate referenced project file.
#>  
function Set-ProjectVersion {
 
  [CmdletBinding()]
  param(
    [string]$ProjectPath,
    [switch]$Increment,
    [switch]$Major,
    [switch]$Minor,
    [switch]$Build,
    [switch]$MinorBuild,
    [string]$VersionName,
    [int]$Version
  )
      
  $ProjectPath = Get-ProjectFile $ProjectPath 

  if ($VersionName -eq '') {
    if ($Major) {
      $VersionName = 'MajorVersion'
    }
    elseif ($Minor) {
      $VersionName = 'MinorVersion'
    } 
    elseif ($Build) {
      $VersionName = 'BuildVersion'
    }
    elseif ($MinorBuild) {
      $VersionName = 'MinorBuildVersion'
    }
  }
     
  $propInfo = Find-ProjectProperty $ProjectPath $VersionName
  if ($null -eq $propInfo) {
    Write-Error "Property $VersionName not found"
    return
  }

  $xProject = New-Object xml
  $xProject.PreserveWhitespace = $true
  $xProject.Load($propInfo.FilePath)
  $xProp = $xProject.SelectSingleNode($propInfo.XPath)

  if ($Increment) {
    $currentValue = [int]$xProp.InnerText
    $Version = $currentValue + 1
  }

  $xProp.InnerText = $Version

  $xProject.Save($propInfo.FilePath)

  if ($Major) {
    Set-ProjectVersion $ProjectPath -Minor -Version 0 -ErrorAction SilentlyContinue 
  }
  elseif ($Minor) {
    Set-ProjectVersion $ProjectPath -Build -Version 0 -ErrorAction SilentlyContinue 
  }
  elseif ($Build) {
    Set-ProjectVersion $ProjectPath -MinorBuild -Version 0 -ErrorAction SilentlyContinue 
  }
}

<#
    .SYNOPSIS
    Get the base name of the assembly that will be built by a project
#> 
function Get-AssemblyName {
  param([string]$ProjectPath)

  $projectFile = Get-ProjectFile $ProjectPath
  $props = Get-ProjectProperties $projectFile 

  if ($props.ContainsKey('AssemblyName')) { return $props['AssemblyName'] }
  return (Get-Item $projectFile).BaseName
}

<#
    .SYNOPSIS
    Get the full file path of the assembly that will be built by a project
#> 
<#
function Get-AssemblyPath {
    param([string]$ProjectPath, [string]$Configuration, [string]$Framework)

    $projectFile = Get-ProjectFile $ProjectPath

    if(Test-IsEmpty $Configuration) {
        $Configuration = 'Release'
    }

    $props = Get-ProjectProperties $projectFile @{ Configuration = $Configuration; TargetFramework = $Framework }
    $ext = 'dll'
    $asmBaseName = (Get-Item $projectFile).BaseName
    if($props.ContainsKey('AssemblyName')) { $asmBaseName=  $props['AssemblyName'] }

    if($props['OutputType'] -eq 'Exe') {
        $ext = 'exe'
    }

    return $null
}
#>

<#
    .SYNOPSIS
    Find a matching .dll or .exe file with the given directory and base name
#> 
function Find-AssemblyFile {
  param([string]$DirectoryPath, [string]$AssemblyBaseName)

  $dllPath = Join-Path $DirectoryPath "$AssemblyBaseName.dll"
  if (Test-Path $dllPath) { return $dllPath }

  $exePath = Join-Path $DirectoryPath "$AssemblyBaseName.exe"
  if (Test-Path $exePath) { return $exePath }

  return $null
}

<#
    .SYNOPSIS
    Clear all contents of the bin and optionally obj folders
#>
function Invoke-Clean {
  param([string]$ProjectDirectory, [string]$Configuration, [switch]$Obj)

  if (!(Test-Path $ProjectDirectory)) { return }

  if (Test-IsEmpty $Configuration) {
    if (Test-Path "$ProjectDirectory\bin") {
      Write-Host "  Clearing $ProjectDirectory\bin"
      Remove-Item "$ProjectDirectory\bin" -Force -Recurse -ErrorAction SilentlyContinue
    }
    if ($Obj -and (Test-Path "$ProjectDirectory\obj")) {
      Write-Host "  Clearing $ProjectDirectory\obj"
      Remove-Item "$ProjectDirectory\obj" -Force -Recurse -ErrorAction SilentlyContinue
    } 
  }
  else {
    if (Test-Path "$ProjectDirectory\bin\$Configuration") {
      Write-Host "  Clearing $ProjectDirectory\bin\$Configuration"
      Remove-Item "$ProjectDirectory\bin\$Configuration" -Force -Recurse -ErrorAction SilentlyContinue
    }
    if ($Obj -and (Test-Path "$ProjectDirectory\obj\$Configuration")) {
      Write-Host "  Clearing $ProjectDirectory\obj\$Configuration"
      Remove-Item "$ProjectDirectory\obj\$Configuration" -Force -Recurse -ErrorAction SilentlyContinue
    } 
  } 
}

<#
    .SYNOPSIS 
    Build the project at the specified path

    .PARAMETER ProjectPath
    The path to the project file or containing directory

    .PARAMETER Configuration
    The configuration name to build (Debug, Release, etc)

    .PARAMETER BuildProps
    A hashtable of project / build properties to inject

    .PARAMETER BuidArgs
    Additional arbitrary command line arguments

    .PARAMETER MSBuild
    Build using msbuild.exe instead of 'dotnet build'
#>
function Invoke-Build {
  param([string]$ProjectPath, [string]$Configuration, [hashtable]$BuildProps, [string[]]$BuildArgs, [switch]$MSBuild, [switch]$Clean)
    
  $ProjectPath = Get-ProjectFile $ProjectPath
    
  if (!(Test-Path $ProjectPath)) { return }

  if (Test-IsEmpty $Configuration) { $Configuration = 'Release' }

  if ([System.IO.File]::Exists($ProjectPath)) {
    $ProjectDirectory = Split-Path $ProjectPath -Parent
    $ProjectFileName = Split-Path $ProjectPath -Leaf
  }
  else {
    $ProjectDirectory = $ProjectPath
    $ProjectFileName = $null
  }
    
  if ($Clean) {
    Invoke-Clean $ProjectDirectory -Configuration $Configuration
  }

  $initialDir = Get-CurrentDirectory
  Set-CurrentDirectory $ProjectDirectory

  $allArgs = Join-BuildArgs -ProjectFileName $ProjectFileName -Configuration $Configuration -BuildProps $BuildProps -BuildArgs $BuildArgs -MSBuild:$MSBuild

  $outFile = Join-Path $env:TEMP invoke-build.out.txt

  if ($MSBuild) {
    $msbuildPath = Get-MSBuildPath
    &$msbuildPath $allArgs | Tee-Object $outFile
  }
  else {
    &dotnet $allArgs | Tee-Object $outFile
  }
     
  Set-CurrentDirectory $initialDir

  $buildOutput = [System.IO.File]::ReadAllText($outFile)
  if ($buildOutput -match 'Build FAILED') {
    Write-Error 'Build failed'
  }
}
 
Export-ModuleMember -Function Get-MSBuildPath, Join-BuildArgs, Get-ProjectFile, Set-ProjectProperty, Find-ProjectProperty, Set-ProjectVersion, `
  Convert-BuildExpression, Invoke-BuildExpression, Test-BuildCondition, Get-ProjectProperties, Get-SolutionDir, Get-AssemblyName, Get-AssemblyPath, `
  Invoke-Clean, Invoke-Build
    