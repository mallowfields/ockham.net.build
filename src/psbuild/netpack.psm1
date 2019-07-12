#------------------------------
# Imports
#------------------------------
if($null -eq $(Get-Module basicutils)) { Import-Module (Join-Path $PSScriptRoot 'basicutils.psm1')  }
Confirm-Module Test-FSPath pathutils
Confirm-Module Test-FSPath netbuild

#------------------------------
# Internal functions
#------------------------------
function Refresh-EnvVars {
  foreach ($level in "Machine", "User") {
    [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
      # For Path variables, append the new values, if they're not already in there
      if ($_.Name -match 'Path$') { 
        $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select-Object -unique) -join ';'
      }
      $_
    } | Set-Content -Path { "Env:$($_.Name)" }
  }
}

#------------------------------
# Exported functions
#------------------------------ 
<#
    .SYNOPSIS
    Ensure nuget is downloaded on this computer and in the PATH variable
#>  
function Confirm-Nuget {
  $nugetDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Nuget', 'bin')
  $nugetPath = [System.IO.Path]::Combine($nugetDir, 'nuget.exe')

  # Make the bin directory
  if (![System.IO.Directory]::Exists($nugetDir)) {
    mkdir $nugetDir | Out-Null
    Write-Host "Created directory $nugetDir"
  }

  # Download nuget.exe
  if (![System.IO.File]::Exists($nugetPath)) {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile('https://dist.nuget.org/win-x86-commandline/latest/nuget.exe', $nugetPath)
    $wc.Dispose()
    Write-Host "Downloaded nuget.exe to $nugetDir"
  }

  # Add the path to the user's PATH variable 
  if (@($env:Path.Split(';') | Where-Object { $_ -eq $nugetDir }).count -eq 0) {
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $userPath += ';' + $nugetDir
    [System.Environment]::SetEnvironmentVariable('PATH', $userPath, 'User') 
    . Refresh-EnvVars

    Write-Host "Added $nugetDir to user's PATH variable"
  } 
} 


<#
    .SYNOPSIS
    Reads the contents of a .nuspec file into a PowerShell object

    .DESCRIPTION
    Read-Nuspec parses the XML contents of a .nuspec file into a structure PowerShell object (psobject). Optionally, it
    can also use the file path patterns within the files/file tags to find all the actual files on the file system
    that will be included in the package.

    .PARAMETER NuspecPath
    The full path to the .nuspec file to parse

    .PARAMETER ExpandFiles
    If this switch parameter is specified, the source paths in all files/file tags will be processed to identify all the
    actual files on the file system that would be included in the package. 

    .EXAMPLE

    PS C:\>Read-Nuspec MyPackage.nuspec 

    This command parses the nuspec file and displays the contents in the host 

    .EXAMPLE

    PS C:\>$packageInfo = Read-Nuspec MyPackage.nuspec -ExpandFiles
    PS C:\>Write-Host $packageInfo.FullPaths

    This command displays the full list of matching files on the file system that would be included in the package
    if nuget pack is executed on the nuspec.

#>
function Read-Nuspec {
  param([string]$NuspecPath, [switch]$ExpandFiles)

  $xNuspec = new-object xml
  $xNuspec.Load($NuspecPath)
  $xMetadata = $xNuspec.package.metadata
  $xFiles = $xNuspec.package.files

  $files = @()
  foreach ($xFile in $xFiles.file) {
    $files += $xFile.src
  }
     
  $fileMap = New-Object 'System.Collections.Generic.Dictionary[String,System.Collections.Generic.List[String]]' $([System.StringComparer]::OrdinalIgnoreCase)
  $noMatchPaths = @()
      
  if ($ExpandFiles) {
    $basePath = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($NuspecPath))
    foreach ($srcPath in $files) {
      $nuspecPathPattern = $srcPath
      $recurse = $false
      $isDir = $false
      $isSearch = $false
      $fileLeaf = Split-Path $srcPath -Leaf

      if ($srcPath.EndsWith('**')) {
        $srcPath = $srcPath.Substring(0, $srcPath.Length - 2)
        $isDir = $true
        $recurse = $true
      }
      elseif ($srcPath.EndsWith('*')) {
        $srcPath = $srcPath.Substring(0, $srcPath.Length - 1)
        $isDir = $true
      }
      else { 
        if ($fileLeaf.Contains('*')) {
          $isSearch = $true
          $srcPath = $srcPath.Substring(0, $srcPath.Length - $fileLeaf.Length)
        }
      }

      $absPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($basePath, $srcPath))
      $addFiles = $null

      try {
        if ($isDir) {
          $addFiles = (Get-ChildItem $absPath -Recurse:$recurse -ErrorAction Stop) | ForEach-Object { $_.FullName } 
        }
        elseif ($isSearch) {
          $absPath = [System.IO.Path]::Combine($absPath, $fileLeaf)
          $addFiles = (Get-ChildItem $absPath -Recurse:$recurse -ErrorAction Stop) | ForEach-Object { $_.FullName }  
        }
        else {
          $addFiles = @($absPath)
        }
      }
      catch [System.Management.Automation.ItemNotFoundException] {
        # Ignore
      }
             
      if (($null -eq $addFiles) -or ($addFiles.Count -eq 0)) {  
        $noMatchPaths += @($nuspecPathPattern)
      }
      else {
        foreach ($newFile in $addFiles) {
          if (!$fileMap.ContainsKey($newFile)) {
            $fileMap.Add($newFile, $(New-Object 'System.Collections.Generic.List[String]'))
          }
          $fileMap[$newFile].Add($nuspecPathPattern)
        } 
      }
    }
  } 

  return New-Object psobject -Property @{
    Version      = $xMetadata.version
    ID           = $xMetadata.id
    Title        = $xMetadata.title
    Authors      = $xMetadata.authors
    Owners       = $xMetadata.owners
    Copyright    = $xMetadata.copyright
    ProjectUrl   = $xMetadata.projectUrl
    Description  = $xMetadata.description
    Files        = [string[]]$files
    FullPaths    = [string[]]$fileMap.Keys
    FileMap      = $fileMap
    NoMatchPaths = [string[]]$noMatchPaths
  }
}

<#
    .SYNOPSIS
    Delete a package version from a nuget feed
#>
function Remove-Package {

  [CmdletBinding(DefaultParameterSetname = "ConfigSet")]
  param([Parameter(Mandatory = $true, Position = 0)][string]$PackageID,
    [Parameter(Mandatory = $true, Position = 1)][string]$Version,
    [Parameter(Mandatory = $true, Position = 2, ParameterSetname = "ConfigSet")][psobject]$Config,
    [Parameter(Mandatory = $true, Position = 2, ParameterSetname = "ExplicitParams")][string]$Source,
    [Parameter(Mandatory = $true, Position = 3, ParameterSetname = "ExplicitParams")][string]$ApiKey)

  if ($PSCmdlet.ParameterSetName -eq 'ExplicitParams') {
    $Config = New-Object psobject -Property @{
      DeleteUrl  = $Source
      ApiKey     = $ApiKey
      BackupPath = $null
    }
  } 

  Confirm-Nuget

    
  # Execute the nuget delete command
  nuget delete $PackageID $Version -Source $Config.DeleteUrl -ApiKey $Config.ApiKey -NonInteractive
}
 
<#
    .SYNOPSIS 
    Get a Hashtable of the names and urls of all nuget sources registered on the local machine
 #>
function Get-NugetSources {
  $sources = @{ }
  $lines = $(nuget sources)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $m = [regex]::Match($line, '^\s*\d+\.\s+(?<name>.+)\s+\['); 
    if ($m.Success) {  
      $sourceName = $m.Groups['name'].Value.Trim()
      $sourceUrl = $lines[$i + 1].Trim()
      $sources[$sourceName] = $sourceUrl
      $i++
    } 
  } 

  $sources
}


<#
    .SYNOPSIS
    Build and publish a package to a nuget feed, either by packing and pushing a .nuspec file,
    or by invoking dotnet build on a .NET Core project and then pushing

    .PARAMETER NuspecPath
    The relative path to a .nuspec or .*proj file. Extension may be omitted

    .PARAMETER Config
    An object with the properties RepoPath, ApiKey, DeleteUrl, and optionally BackupPath

    .PARAMETER Source
    The source alias (in local configuration) or full url to the package fee

    .PARAMETER ApiKey
    The nuget apikey for the target feed

    .PARAMETER CopyTo
    An array of paths to which the package should also be file-copied

    .PARAMETER Overwrite
    Overwrite an existing package version if it exists. Requires a feed that supports GET

    .PARAMETER IgnoreVersion
    Ignore mismatch between package version and the assembly version of the primary included .NET assembly

    .PARAMETER PushOnly
    Do not check for an existing package version. Use this when pushing to a feed that does not support GET

    .PARAMETER NoPackageAnalysis
    Supply the -NoPackageAnalysis argument to nuget pack

    .PARAMETER dotnetCLI
    Treat -NuspecPath as the path to a project file, and invoke 'dotnet build' instead of 'nuget pack'

    .PARAMETER DebugBuild
    When buiding with msbuild (-dotnetCLI switch), use Debug configuration
#>
function Publish-Package {
 
  [CmdletBinding(DefaultParameterSetname = "ConfigSet")]
  param([Parameter(Mandatory = $true, Position = 0)][string]$SpecPath,
    [Parameter(Mandatory = $true, Position = 1, ParameterSetname = "ConfigSet")][psobject]$Config,
    [Parameter(Mandatory = $true, Position = 1, ParameterSetname = "ExplicitParams")][string]$Source,
    [Parameter(Mandatory = $true, Position = 2, ParameterSetname = "ExplicitParams")][string]$ApiKey,
    [Parameter(Mandatory = $false)][string[]]$CopyTo,
    [switch]$Overwrite,
    [switch]$IgnoreVersion,
    [switch]$PushOnly,
    [switch]$NoPackageAnalysis,
    [switch]$dotnetCLI,
    [switch]$DebugBuild,
    [hashtable]$BuildProps)
        
  [System.IO.FileInfo[]]$specFiles

  $BuildConfigName = 'Release'
  if ($DebugBuild) { $BuildConfigName = 'Debug' }
     
  if (!$dotnetCLI) {
    if (!$SpecPath.ToLower().EndsWith('.nuspec')) {
      $SpecPath += '.nuspec'
    }

    try {
      $specFiles = [System.IO.FileInfo[]](@(Get-ChildItem $SpecPath -ErrorAction Stop))
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      Write-Warning 'No matching nuspec files found'
      return
    }
    catch {
      Write-Warning $Error[0]
      return
    }

    if ($specFiles.Count -eq 0) {
      Write-Warning 'No matching nuspec files found'
      return
    }
  }
  else {  
    $SpecPath = Get-ProjectFile $SpecPath 
    if (!(Test-FSPath $SpecPath)) { return; }

    $specFiles = [System.IO.FileInfo[]](@(Get-Item  $SpecPath))
  }

  if ($PSCmdlet.ParameterSetName -eq 'ExplicitParams') {
    # The URL for deleting a package must omit the trailing 'nuget' portion
    [Uri]$uri = $null
    try { 
      $uri = New-Object uri $Source
    }
    catch {
      $sources = Get-NugetSources
      if (!$sources.ContainsKey($Source)) {
        Write-Warning "Specified source '$Source' is not a valid Uri and is not a name of a source defined on this machine"
        return
      }
      $sourceUrl = $sources[$Source]
      $uri = New-Object Uri $sourceUrl
    }

    $Source = $uri.AbsoluteUri
    $deleteUri = $Source.Substring(0, $Source.Length - $uri.Segments[$uri.Segments.Count - 1].Length)

    $Config = New-Object psobject -Property @{
      RepoPath   = $Source
      ApiKey     = $ApiKey
      BackupPath = $null
      DeleteUrl  = $deleteUri
    }
  } 
    
  if (!$dotnetCLI) {
    Confirm-Nuget     
  } 
    
  foreach ($specFile in $specFiles) {
    $fullPath = $specFile.FullName

    Write-Banner $('Processing {0}' -f $specFile.Name)

    if (!$dotnetCLI) {
      Write-Host $('+ Checking files specified in nuspec')

      $info = Read-Nuspec $fullPath -ExpandFiles:(!$IgnoreVersion)

      if ($info.NoMatchPaths.Count -gt 0) {
        Write-Host $('  ERROR: The following file tags did not match any files on disk') 
        Write-Host $('    Current directory context : {0}' -f $((Get-Location).Path))
                
        foreach ($nuspecPathPattern in $info.NoMatchPaths) {
          Write-Host $('    nuspec path pattern       : {0}' -f $($nuspecPathPattern))
        }
        Write-Banner '!! Publish-Package aborted !!'
        return
      }
      # Write-Host $('  OK: All file tags matched at least one file on disk')

      foreach ($fPath in $info.FullPaths) {
        if (!(Test-FSPath $fPath)) {
          $nuspecPathPatterns = $info.FileMap[$fPath]
          Write-Host $('  ERROR: File specified in package does not exist on disk')
          Write-Host $('    Full file path            : {0}' -f $fPath)
          Write-Host $('    Current directory context : {0}' -f $((Get-Location).Path))
          Write-Host $('    nuspec path pattern       : {0}' -f $($nuspecPathPatterns[0]))
          Write-Banner '!! Publish-Package aborted !!'
          return
        }
      }
      Write-Host $('  OK: All files specified in nuspec found on disk')
    }
    else {
      $projectProps = Get-ProjectProperties $specFile.FullName -BuildProps $(Join-HashTables @{ Configuration = $BuildConfigName } $BuildProps)
      $missingProps = New-Object System.Collections.Generic.List[string]
      foreach ($propName in @('PackageID', 'FileVersion', 'PackageVersion')) {
        if (Test-IsEmpty $projectProps[$propName]) {
          $missingProps.Add($propName)
        } 
      }
            
      if ($missingProps.Count -gt 0) {
        Write-Host $('  ERROR: Missing one or more required project properties:')
        foreach ($propName in $missingProps) {
          Write-Host "    $propName"
        }
        Write-Banner '!! Publish-Package aborted !!'
        return

      }

      $assemblyName = $projectProps['AssemblyName']
      if (Test-IsEmpty $assemblyName) { $assemblyName = $specFile.BaseName }

      $info = New-Object psobject -Property @{
        ID               = $projectProps['PackageID']
        Version          = $projectProps['PackageVersion']
        FileVersion      = $projectProps['FileVersion']
        AssemblyFileName = $assemblyName
        FullPaths        = @()
      }
    }
         
    if (!$IgnoreVersion) {

      Write-Host $('+ Checking assembly file version')

      # Check the assembly file version
      $assemblyFiles = $info.FullPaths | Where-Object { $ext = [System.IO.Path]::GetExtension($_).ToLower(); return ($ext -eq '.dll' -or $ext -eq '.exe') }
             
      if ($dotnetCLI -or $($assemblyFiles.Count -gt 0)) {

        if ($dotnetCLI) {
          $assemblyVersion = $info.FileVersion
          $assemblyFileName = $info.AssemblyFileName
        }
        else {
          # First look for an assembly with the same name as the package ID
          $testAssembly = $assemblyFiles | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -eq $info.ID } | Select-Object -First 1

          if ($null -eq $testAssembly) {
            # Next look for the first .exe file
            $testAssembly = $assemblyFiles | Where-Object { [System.IO.Path]::GetExtension($_) -eq '.exe' } | Select-Object -First 1
          }  

          if ($null -eq $testAssembly) {
            # Next just take the first dll or exe
            $testAssembly = $assemblyFiles | Select-Object -First 1
          }

          $assemblyVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($testAssembly).FileVersion 
          $assemblyFileName = [System.IO.Path]::GetFileName($testAssembly)
        }

        $packageVersionString = [regex]::Replace($info.Version, '-.*$', '') # Remove non-release package suffix

        $packageVersion = New-Object Version $packageVersionString
        $versionMatched = $false

        if (!$packageVersion.Equals((New-Object Version $assemblyVersion))) {
          if (($packageVersion.Revision -eq -1) -and ($assemblyVersion.EndsWith('.0'))) {
            # Try again with truncated version
            $fileVersion = [regex]::Replace($assemblyVersion, '(\.0)$', '')
            $versionMatched = $packageVersion.Equals((New-Object Version $fileVersion)) 
          } 
        }
        else {
          $versionMatched = $true
        }

        if (!$versionMatched) {
          Write-Host $('  ERROR: Package version {0} does not match file version {1} of assembly {2}' -f $info.Version, $assemblyVersion, $assemblyFileName)
          Write-Banner '!! Publish-Package aborted !!'
          return
        }
        else {
          Write-Host $('  OK: Package version {0} matches file version {1} of assembly {2}' -f $info.Version, $assemblyVersion, $assemblyFileName)
        }
      }
    }
     
    if (!$PushOnly) { 
         
      Write-Host $('+ Checking for existing package version in repository')

      # Check if this version of the package already exists
      $existingPackage = $(nuget list $info.ID -Source $config.RepoPath -AllVersions -Prerelease).Split("`r`n") | ForEach-Object { 
        $parts = $_.Split(' ')
        New-Object psobject -Property @{
          ID      = $parts[0]
          Version = $parts[1]   
        }
      } | Where-Object { ($_.ID -eq $info.ID) -and ($_.Version -eq $info.Version) }

      if ($null -ne $existingPackage) {
        # If the package version already exists, either delete it or warn the user and exit
        if ($Overwrite) {
          Write-Host $('  Deleting existing package {0}.{1} from {2}' -f $info.ID, $info.Version, $Config.RepoPath) 

          # Execute the nuget delete command
          nuget delete $info.ID $info.Version -Source $Config.DeleteUrl -ApiKey $Config.ApiKey -NonInteractive
        }
        else {
          Write-Host $('  WARNING: Package {0}.{1} already exists on {2}. To overwrite, use the -Overwrite flag' -f $info.ID, $info.Version, $Config.RepoPath)
          Write-Banner '!! Publish-Package aborted !!'
          return  
        }
      }
      else {
        Write-Host $('  OK: Package {0}.{1} does not already exist on {2}' -f $info.ID, $info.Version, $Config.RepoPath)
      }
    }
         
    $nupkgFile = $info.ID + '.' + $info.Version + '.nupkg'

    # If the package already exists locally, delete it
    if (Test-FSPath $($info.ID + '.*.nupkg')) { Remove-Item $($info.ID + '.*.nupkg') }

    # Create the package
    Write-Host '+ Packaging nuspec'
    $packErr = Join-Path $env:TEMP nuget.err.txt
    $fnPack = { }  

    if ($dotnetCLI) {
      $projectDirectory = Set-CurrentDirectory $(Split-Path $fullPath -Parent)  
      $solutionDir = Get-SolutionDir $projectDirectory

      $defaultBuildProps = @{
        SolutionDir = $solutionDir
        ProjectDir  = $projectDirectory
      } 

      $buildArgs = @{
        ProjectPath   = $projectDirectory
        Configuration = $BuildConfigName
        BuildProps    = Join-HashTables $defaultBuildProps $BuildProps
      }

      # Invoke the Powershell cmdlet Invoke-Build
      $fnPack = { Invoke-Build @buildArgs }
      $nupkgFile = [System.IO.Path]::Combine($projectDirectory, 'bin', $BuildConfigName, $nupkgFile) 

    }
    else {
      $packArgs = New-Object System.Collections.Generic.List[string]
      $packArgs.Add('pack')
      $packArgs.Add($fullPath) 

      if ($NoPackageAnalysis) {
        $packArgs.Add('-NoPackageAnalysis')
      }

      # Invoke the command line program nuget.exe
      $fnPack = { &nuget $packArgs }
    }
          
    &$fnPack 2> $packErr

    $errText = [System.IO.File]::ReadAllText($packErr).Trim()
    if ($errText.Length -gt 0) {
      Write-Warning ('  ERROR: nuget pack failed : ' + [System.IO.File]::ReadAllLines($packErr)[0].Trim())
      Write-Banner '!! Publish-Package aborted !!'
      return
    }

    # Simple file Copy-Item to the backup folder
    if ((Test-IsNotEmpty $config.BackupPath) -and (Test-FSPath $config.BackupPath)) {
      Write-Host $('+ Backing up package to {0}' -f $config.BackupPath)
      Copy-Item $nupkgFile $config.BackupPath
    }

    # Additional simple file copies, if specified
    if ($null -ne $CopyTo -and $CopyTo.Count -gt 0) {
      foreach ($copyPath in $CopyTo) {
        if (Test-FSPath $copyPath) {
          Write-Host $('+ Copying package to {0}' -f $copyPath)
          Copy-Item $nupkgFile $copyPath
        }
      }
    }

    Write-Host '+ Pushing nupkg to repository'

    # Execute nuget push command
    nuget push $nupkgFile -Source $Config.RepoPath -ApiKey $Config.ApiKey 
        
    Write-Host $('+ Finished processing {0}' -f $nuspec.Name)
  } 

  Write-Banner 'Publish-Package complete'
}
 
Export-ModuleMember -Function Confirm-Nuget, Read-Nuspec, Remove-Package, Publish-Package 
