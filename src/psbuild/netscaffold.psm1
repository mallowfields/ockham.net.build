#------------------------------
# Imports
#------------------------------
if($null -eq $(Get-Module basicutils)) { Import-Module (Join-Path $PSScriptRoot 'basicutils.psm1')  }
Confirm-Module Test-FSPath pathutils
Confirm-Module Test-FSPath netbuild
Confirm-Module Test-FSPath vsdata

#------------------------------
# Internal functions
#------------------------------ 
$project_types = newobj @{
  Folder        = newobj @{
    Guid     = '{2150E333-8FDC-42A3-9474-1A3956D46DE8}'
    Template = $null
  }
  SharedProject = newobj @{
    Guid      = '{D954291E-2A0B-460D-934E-DC6B0785DB48}'
    Templates = newobj @{
      shproj    = @'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Label="Globals">
    <ProjectGuid>$guid1$</ProjectGuid>
    <MinimumVisualStudioVersion>14.0</MinimumVisualStudioVersion>
  </PropertyGroup>
  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <Import Project="$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v$(VisualStudioVersion)\CodeSharing\Microsoft.CodeSharing.Common.Default.props" />
  <Import Project="$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v$(VisualStudioVersion)\CodeSharing\Microsoft.CodeSharing.Common.props" />
  <PropertyGroup />
  <Import Project="$projectname$.projitems" Label="Shared" />
  <Import Project="$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v$(VisualStudioVersion)\CodeSharing\Microsoft.CodeSharing.$language$.targets" />
</Project>
'@
      projitems = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MSBuildAllProjects>$(MSBuildAllProjects);$(MSBuildThisFileFullPath)</MSBuildAllProjects>
    <HasSharedItems>true</HasSharedItems>
    <SharedGUID>$guid1$</SharedGUID>
  </PropertyGroup>
  <PropertyGroup Label="Configuration">
    <Import_RootNamespace>$rootnamespace$</Import_RootNamespace>
  </PropertyGroup>
  <ItemGroup>
  </ItemGroup>
</Project> 
'@
    }
  } 
  CSharp        = newobj @{ 
    Core               = newobj @{
      Guid      = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'  
      Templates = newobj @{
        Program = @'
using System;

namespace $rootnamespace$
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Hello World!");
        }
    }
}
'@
        Class   = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace $rootnamespace$ 
{
    public class Class1 {

    }
}
'@
      }
    } 
    ASPNETCore         = newobj @{
      Guid      = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'  
      Templates = newobj @{
        Program = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace $rootnamespace$
{
    public class Program
    {
        public static void Main(string[] args)
        {
            BuildWebHost(args).Run();
        }

        public static IWebHost BuildWebHost(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                .UseStartup<Startup>()
                .Build();
    }
}
'@

        Startup = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace $rootnamespace$
{
    public class Startup
    {
        // This method gets called by the runtime. Use this method to add services to the container.
        // For more information on how to configure your application, visit https://go.microsoft.com/fwlink/?LinkID=398940
        public void ConfigureServices(IServiceCollection services)
        {
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            } 
        }
    }
}
'@
      }
    } 
    ClassLibrary       = newobj @{
      Guid      = '{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}'
      Templates = @( 
        'CSharp\ClassLibrary\template.csproj' ,
        'CSharp\ClassLibrary\SimpleClass.cs' 
      )
    } 
    ConsoleApplication = newobj @{
      Guid      = '{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}'
      Templates = @( 
        'CSharp\ConsoleApplication\template.csproj' 
        'CSharp\ConsoleApplication\program.cs' 
      )
    } 
        
  } 
  VisualBasic   = newobj @{
    Core = newobj @{
      Guid = '{F184B08F-C81C-45F6-A57F-5ABD9991F28F}'
    }
  }
}
 
function Set-SolutionPath {

  param($project)
    
  foreach ($childProject in $project.ChildProjects) {
    $childProject.SolutionPath = $project.SolutionPath + '\' + $childProject.SolutionPath

    Set-SolutionPath $childProject
  } 
}
 
<#
    .SYNOPSIS
    Get the first matching element within a project xml structure, and optionally create a new one if
    no match is found
#>
function Get-ProjectElement {

  [CmdletBinding(DefaultParameterSetName = "Label")]
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    [System.Xml.XmlNode]$xProject,
        
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ElementName,

    [Parameter(ParameterSetName = "Label", Mandatory = $false)]
    [string]$Label,
         
    [Parameter(ParameterSetName = "Filter", Mandatory = $false)]
    [scriptblock]$Filter,
         
    [switch]$Create
  )

  if ($xProject -is [System.Xml.XmlDocument]) {
    $xProject = $xProject.DocumentElement
  }
  elseif ($xProject -isnot [System.Xml.XmlElement]) {
    throw (New-Object System.InvalidCastException "Provided value cannot be used as a XmlElement")
  }

  [System.Xml.XmlElement]$xGroup = $null
  $allElements = $xProject.SelectNodes('//*') | Where-Object { $_.LocalName -eq $ElementName }
     
  switch ($PsCmdlet.ParameterSetName) {
    Label {
      if (Test-IsEmpty $Label) { 
        $xGroup = $allElements | Select-Object -First 1 
      }
      else {
        $xGroup = $allElements | Where-Object { $_.GetAttribute('Label') -eq $Label } | Select-Object -First 1
      }
    }
    Filter {
      $xGroup = $allElements | Where-Object $Filter | Select-Object -First 1
    }
  }

  if (($null -eq $xGroup) -and $Create) {
    $xDoc = $xProject.OwnerDocument 
    $xGroup = $xProject.AppendChild($xDoc.CreateElement($ElementName))
    if (Test-IsNotEmpty $Label) {
      $xGroup.SetAttribute('Label', $Label)
    } 
  }
     
  return $xGroup
}

#------------------------------
# Exported functions
#------------------------------ 

function New-ProjectGuid {
  [Guid]::NewGuid().ToString('b').ToUpper()
}

<#
    .SYNOPSIS
    Find the first index of a string within a collection that matches the provided pattern

    .PARAMETER InputObject
    An enumerable collection of strings

    .PARAMETER Pattern
    The string pattern to match against using the -like operator

    .PARAMETER Regex
    Treat Pattern as a regular expression

    .PARAMETER Escape
    Use Regex.Escape() on Pattern before matching
#>
function Find-Line {
  param([System.Collections.Generic.IEnumerable[string]]$InputObject, $Pattern, [switch]$Regex, [switch]$Escape, [int]$StartIndex = 0)

  if ($Regex -and $Escape) {
    $Pattern = [regex]::Escape($Pattern)
  }

  $i = $StartIndex
  if ($StartIndex -gt 0) {
    $InputObject = [string[]]@($InputObject | Select-Object -Skip $StartIndex)
  }
  foreach ($line in $InputObject) {
    if ($Regex) {
      if ($line -match $pattern) { return $i }
    }
    else {
      if ($line -like $pattern) { return $i }
    }
    $i += 1
  } 

  return -1
}

<#
    .SYNOPSIS
    Initialize Visual Studio template variables with basic settings
#>
function New-TemplateVars {
    
  param([string]$ProjectName, [string]$AssemblyName, [string]$RootNamespace, [string]$Language) 

  $result = @{
    projectname     = $ProjectName
    safeprojectname = [regex]::Replace($ProjectName, '[^\w\d]+', '') 
    guid1           = New-ProjectGuid
    guid2           = New-ProjectGuid
    guid3           = New-ProjectGuid
    guid4           = New-ProjectGuid
    guid5           = New-ProjectGuid
  } 

  if (Test-IsNotEmpty $AssemblyName) { $result['assemblyname'] = $AssemblyName }
  if (Test-IsNotEmpty $Language) { $result['language'] = $Language }

  if (Test-IsNotEmpty $RootNamespace) { 
    $result['rootnamespace'] = $RootNamespace
  }
  else {
    $result['rootnamespace'] = $result['safeprojectname']
  }

  return $result
}

<#
    .SYNOPSIS
    Replace Visual Studio template variable placeholders
#>
function Set-TemplateVars {

  param([string]$Content, [hashtable]$Variables)

  foreach ($varName in $Variables.Keys) {
    $varTag = $varName
    if (!$varTag.StartsWith('$')) { $varTag = '$' + $varTag }
    if (!$varTag.EndsWith('$')) { $varTag = $varTag + '$' }
    $Content = $Content.Replace($varTag, $Variables[$varName])
  }

  return $Content
}

<#
    .SYNOPSIS
    Create a blank Visual Studio solution file
#>
function New-Solution {

  param([string]$SolutionDir, [string]$SolutionName)

  if (Test-IsEmpty $SolutionDir) { 
    $SolutionDir = Get-CurrentDirectory 
  }
  else {
    $SolutionDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-CurrentDirectory), $SolutionDir))
  }
     
  if (!(Test-Path $SolutionDir)) { mkdir $SolutionDir | Out-Null }
  $slnFile = [System.IO.Path]::Combine($SolutionDir, $SolutionName + '.sln')
  $slnGuid = [Guid]::NewGuid()

  [System.IO.File]::WriteAllText($slnFile, @"
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio 15
VisualStudioVersion = 15.0.27428.2027
MinimumVisualStudioVersion = 10.0.40219.1
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution 
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(NestedProjects) = preSolution 
	EndGlobalSection
	GlobalSection(ExtensibilityGlobals) = postSolution
		SolutionGuid = $($slnGuid.ToString('B').ToUpper())
	EndGlobalSection
EndGlobal
"@)
    
  return $slnFile
}

<#
    .SYNOPSIS
    Get the tree of all project in a solution
#>
function Get-ProjectGraph {
    
  param([string]$SolutionFile)

  $projects = @{ }

  $solutionContent = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($SolutionFile))
  $i = Find-Line $solutionContent '^Project' -Regex
  while ($i -gt -1) {
    $line = $solutionContent[$i]
    $typeGuid = $line.Substring(9, 38)
    $info = [string[]]$(Invoke-Expression $line.Substring(51))
    $projectName = $info[0]
    $projectPath = $info[1]
    $projectGuid = $info[2]
    $projects[$projectGuid] = newobj @{
      Guid          = $projectGuid
      TypeGuid      = $typeGuid
      Name          = $projectName
      Path          = $projectPath 
      ParentProject = $null
      SolutionPath  = $projectName
      ChildProjects = [System.Collections.Generic.List[object]]::new()
    }
         
    $i = Find-Line $solutionContent '^EndProject' -Regex -StartIndex $($i + 1)
    $i = Find-Line $solutionContent '^Project' -Regex -StartIndex $($i + 1)
  }

  $i = Find-Line $solutionContent 'GlobalSection(NestedProjects) = preSolution' -Regex -Escape

  if ($i -gt -1) {
    $j = Find-Line $solutionContent '^\s*EndGlobalSection\s*$' -Regex -StartIndex $i
    $i += 1
    while ($i -lt $j) {
      $line = $solutionContent[$i]
      $m = [regex]::Match($line, '(?<childguid>\{[^}]{36}\})\s*=\s*(?<parentguid>\{[^}]{36}\})')
      if ($m.Success) {
        $childProject = $projects[$m.Groups['childguid'].Value]
        $parentProject = $projects[$m.Groups['parentguid'].Value]
        $childProject.ParentProject = $parentProject
        $parentProject.ChildProjects.Add($childProject)
      }
      $i += 1
    }
  } 

  foreach ($project in $projects.Values) {
    if ($null -ne $project.ParentProject) { continue; }
    Set-SolutionPath $project
  }

  foreach ($project in @($projects.Values)) {
    $projects[$project.SolutionPath] = $project
  }

  return $projects
}

<#
    .SYNOPSIS 
    Add a new solution folder to a solution 
#>
function Add-SolutionFolder {

  param([string]$SolutionFile, [string]$FolderPath, [switch]$IgnoreExisting)
    
  $projects = Get-ProjectGraph $SolutionFile
  if ($projects.ContainsKey($FolderPath)) {
    if ($IgnoreExisting) { return $projects[$FolderPath].Guid }
    throw $(New-Object System.ArgumentException FolderPath "A project with path $FolderPath already exists in this solution")
  }

  $parts = $FolderPath.Split('\')
  $folderName = $parts | Select-Object -Last 1

  $parentGuid = $null
  $parentPath = $null
  if ($parts.Length -gt 1) { 
    $parentPath = [string]::Join('\', ($parts | Select-Object -First $($parts.Length - 1)))
    $parentGuid = Add-SolutionFolder $SolutionFile $parentPath -IgnoreExisting 
  } 
     
  # Add the project to the solution
  $solutionContent = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($SolutionFile))
  $i = Find-Line $solutionContent 'Global'
  $projectGuid = New-ProjectGuid

  # Insert the project
  $solutionContent.InsertRange($i, [string[]]@(
      "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$folderName`", `"$folderName`", `"$projectGuid`"",
      "EndProject" 
    ))

  if ($null -ne $parentGuid) {
    $i = Find-Line $solutionContent 'GlobalSection(NestedProjects) = preSolution' -Regex -Escape
    if ($i -eq -1) {
      $i = Find-Line $solutionContent 'GlobalSection(ExtensibilityGlobals) = postSolution' -Regex -Escape

      $solutionContent.InsertRange($i, [string[]]@(
          "`tGlobalSection(NestedProjects) = preSolution",
          "`tEndGlobalSection"
        ))
      $i += 1 
    }
    else {
      $i = Find-Line $solutionContent '^\s*EndGlobalSection\s*$' -Regex -StartIndex $i
    }

    $solutionContent.Insert($i, "`t`t$projectGuid = $parentGuid")
  }
     
  [System.IO.File]::WriteAllLines($SolutionFile, $solutionContent) 

  $projectGuid
}

<#
    .SYNOPSIS
    Add a new PropertyGroup element to a project xml structure
#>
function Add-PropertyGroup {

  param([System.Xml.XmlElement]$xProject, [hashtable]$Properties, [string]$Label)

  $xDoc = $xProject.OwnerDocument
  $xGroup = $xProject.AppendChild($xDoc.CreateElement('PropertyGroup'))
  if (Test-IsNotEmpty $Label) {
    $xGroup.SetAttribute('Label', $Label)
  }

  foreach ($key in $Properties.Keys) {
    $xProp = $xGroup.AppendChild($xDoc.CreateElement($key))
    $xProp.InnerText = $Properties[$key]
  }

  return $xGroup
}

<#
    .SYNOPSIS
    Add a new ItemGroup element to a project xml structure
#>
function Add-ItemGroup {

  param([System.Xml.XmlElement]$xProject, [string]$Label)

  $xDoc = $xProject.OwnerDocument
  $xGroup = $xProject.AppendChild($xDoc.CreateElement('ItemGroup'))
  if (Test-IsNotEmpty $Label) {
    $xGroup.SetAttribute('Label', $Label)
  } 

  return $xGroup
}


<#
    .SYNOPSIS
    Get the first matching ItemGroup element within a project xml structure, and optionally create a new one if
    no match is found
#>
function Get-ItemGroup {

  [CmdletBinding(DefaultParameterSetName = "Label")]
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    [System.Xml.XmlNode]$xProject,

    [Parameter(ParameterSetName = "Label", Mandatory = $false)]
    [string]$Label,
         
    [Parameter(ParameterSetName = "Filter", Mandatory = $false)]
    [scriptblock]$Filter,
         
    [switch]$Create
  )

  switch ($PSCmdlet.ParameterSetName) {
    Label { return Get-ProjectElement $xProject ItemGroup -Label  $Label  -Create:$Create }
    Filter { return Get-ProjectElement $xProject ItemGroup -Filter $Filter -Create:$Create }
  }
}


<#
    .SYNOPSIS
    Get the first matching PropertyGroup element within a project xml structure, and optionally create a new one if
    no match is found
#>
function Get-PropertyGroup {

  [CmdletBinding(DefaultParameterSetName = "Label")]
  param(
    [Parameter(Position = 0, Mandatory = $true)]
    [System.Xml.XmlNode]$xProject,

    [Parameter(ParameterSetName = "Label", Mandatory = $false)]
    [string]$Label,
         
    [Parameter(ParameterSetName = "Filter", Mandatory = $false)]
    [scriptblock]$Filter,
         
    [switch]$Create
  )

  switch ($PSCmdlet.ParameterSetName) {
    Label { return Get-ProjectElement $xProject PropertyGroup -Label  $Label  -Create:$Create }
    Filter { return Get-ProjectElement $xProject PropertyGroup -Filter $Filter -Create:$Create }
  }
}

<#
    .SYNOPSIS 
    Add an existing file to an existing project. Equivalent to Visual Studio Add > Existing Item

    .PARAMETER ProjectFile
    The path to the project file

    .PARAMETER FilePath
    The path to the file to add

    .PARAMETER ProjectPath
    Path within the project to which the source file should be copied. If blank, the file to
    be added must be within the project root folder

    .PARAMETER Mode
    Mode to add the file (Compile, None, etc). If not specified, mode is Compile

    .PARAMETER AsLink
    Add the file as a link. Requires ProjectPath to be set

    .PARAMETER Hidden
    Set the Visible=false attribute on the item

    .PARAMETER 

#>
function Add-ProjectFile {
    
  param(
    [string]$ProjectFile, 
    [string]$FilePath, 
    [string]$ProjectPath,

    [ValidateSet('Compile', 'None', 'EmbeddedResource', 'Content')]
    [string]$Mode,
        
    [ValidateSet('Never', 'Always', 'PreserveNewest')]
    [string]$CopyMode,

    [switch]$AsLink,
    [switch]$Hidden,
    [string]$ItemGroupLabel,
    [System.Xml.XmlElement]$ItemGroup
  )

  $ProjectFile = Get-ProjectFile $ProjectFile
  $FilePath = (Get-Item $FilePath).FullName
  if (Test-IsEmpty $Mode) { $Mode = 'Compile' }



}

<#
    .SYNOPSIS 
    Add a folder within a project. Equivalent to Visual Studio Add > New Folder
#>
function Add-ProjectFolder {
    
  param(
    [string]$ProjectFile,  
    [string]$ProjectPath 
  )



}

<#
    .SYNOPSIS 
    Add a PackageReference or DotNetCliToolReference element to an existing ItemGroup element
#>
function Add-PackageReference {

  [CmdletBinding()]
  param(
    [Parameter(ParameterSetName = 'Xml', Position = 0)]
    [System.Xml.XmlElement]$xPackageReferences,

    [Parameter(ParameterSetName = 'ProjectFile', Position = 0)]
    [string]$ProjectFile,

    [Parameter(Position = 1)]
    [string]$PackageId,

    [Parameter(Position = 2)]
    [string]$Version,

    [Parameter(Position = 3)]
    [string]$VersionRange,
    [switch]$ToolReference
  )

  $elementName = 'PackageReference'
  if ($ToolReference) { $elementName = 'DotNetCliToolReference' }

  $directToFile = $false
  if ($PSCmdlet.ParameterSetName -eq 'ProjectFile') {
    $directToFile = $true
    $xml = New-Object xml
    $xml.Load($ProjectFile)
    $xPackageRef = $xml.SelectSingleNode('//PackageReference')
  }

  $xRef = $xPackageReferences.AppendChild($xPackageReferences.OwnerDocument.CreateElement($elementName))
  $xRef.SetAttribute('Include', $PackageId)
  if (Test-IsNotEmpty $Version) { 
    $xRef.SetAttribute('Version', $Version)
  }
  elseif (Test-IsNotEmpty $VersionRange) {
    $xRef.SetAttribute('Version', $VersionRange)
  }
  $xRef
}


<#
    .SYNOPSIS
    Add an existing project to an existing solution. Equivalent to Add > Existing Project in Visual Studio
#>
function Add-Project {
  param(
    [string]$SolutionFile,
    [string]$ProjectFile, 
    [string]$ProjectType,
    [string]$SolutionFolder 
  )

  $parentGuid = $null
  $projectGuid = $null
  $ProjectFile = Get-ProjectFile $ProjectFile
  if (!(Test-FSPath $ProjectFile)) { return }

  $projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectFile)
  $relativePath = Get-RelativePath $SolutionFile $ProjectFile

  if (Test-IsNotEmpty $SolutionFolder) {
    $parentGuid = Add-SolutionFolder -SolutionFile $SolutionFile -FolderPath $SolutionFolder -IgnoreExisting
  }

  $props = Get-ProjectProperties $ProjectFile
  if ($props.ContainsKey('ProjectGuid')) { 
    $projectGuid = $props['ProjectGuid']
  }
  else {
    $projectGuid = New-ProjectGuid
  }

  # Add the project to the solution
  $solutionContent = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($SolutionFile))
  $i = Find-Line $solutionContent 'Global'

  $TypeGuid = Get-ProjectTypeGuid $ProjectType
  if (Test-IsEmpty $TypeGuid) { $TypeGuid = Get-ProjectTypeGuid $ProjectFile }
  if (Test-IsEmpty $TypeGuid) { 
    Write-Error 'Project type guid could not be determined'
    return
  }
     
  # Insert the project
  $solutionContent.InsertRange($i, [string[]]@(
      "Project(`"$TypeGuid`") = `"$projectName`", `"$relativePath`", `"$projectGuid`"",
      "EndProject" 
    ))

  if ($null -ne $parentGuid) {
    $i = Find-Line $solutionContent 'GlobalSection(NestedProjects) = preSolution' -Regex -Escape
    if ($i -eq -1) {
      $i = Find-Line $solutionContent 'GlobalSection(ExtensibilityGlobals) = postSolution' -Regex -Escape

      $solutionContent.InsertRange($i, [string[]]@(
          "`tGlobalSection(NestedProjects) = preSolution",
          "`tEndGlobalSection"
        ))
      $i += 1 
    }
    else {
      $i = Find-Line $solutionContent '^\s*EndGlobalSection\s*$' -Regex -StartIndex $i
    }

    $solutionContent.Insert($i, "`t`t$projectGuid = $parentGuid")
  }
     
  [System.IO.File]::WriteAllLines($SolutionFile, $solutionContent) 
  return $projectGuid
}
 
<#
    .SYNOPSIS
    Create a new Visual Studio Project

    .PARAMETER ProjectDir
    The directory for the new project file
    
    .PARAMETER ProjectName
    The base name of the new project file

    .PARAMETER SolutionFile
    The solution to which the project should be added

    .PARAMETER TemplatePath
    The path to the applicable .vstemplate file

    .PARAMETER TemplateProps
    The properties to provide to the template replacer. Typical guids, projectname, projectsafename, etc
    will be generated if not explicitly provided
#>
function New-Project {

  [CmdletBinding(DefaultParametersetname = "Direct")]
  param(
    [Parameter(Position = 0)]
    [string]$ProjectName, 

    [string]$ProjectDir, 
    [string]$SolutionFile,
    [string]$SolutionFolder,
    [string]$AssemblyName,
    [string]$RootNamespace,
 
    # Parameters to create project from scratch
    [Parameter(ParameterSetName = "Direct")]
    [ValidateSet('CSharp', 'VisualBasic', 'JavaScript', 'PowerShell', 'TypeScript')]
    [string]$Language,
          
    [Parameter(ParameterSetName = "Direct")] 
    [ValidateSet('Library', 'Console', 'ASP', 'Test', 'Shared')]
    [string]$ProjectKind, 

    [Parameter(ParameterSetName = "Direct")]
    [string[]]$FrameworkVersions,
        
    # Parameters to use a specific Visual Studio template file
    [Parameter(ParameterSetName = "Template")]
    [string]$TemplatePath, 

    [Parameter(ParameterSetName = "Template")]
    [hashtable]$TemplateProps,

    [Parameter(ParameterSetName = "Template")]
    [switch]$IgnoreWizard 
  )
      
  $typeGuid = $null
  $projectFile = $null
  $ext = $null

  if (Test-IsEmpty $Language   ) { $Language = 'CSharp' }
  if (Test-IsEmpty $ProjectKind) { $ProjectKind = 'Library' }

  if ((Test-IsEmpty $ProjectDir) -and (Test-IsNotEmpty $SolutionFile)) {
    if (Test-IsNotEmpty $SolutionFolder) {
      $ProjectDir = [System.IO.Path]::Combine($(Split-Path $SolutionFile -Parent), $SolutionFolder, $ProjectName) 
    }
    else {
      $ProjectDir = Join-Path $(Split-Path $SolutionFile -Parent) $ProjectName
    }  
  }

  if (!(Test-Path $ProjectDir)) { mkdir $ProjectDir | Out-Null }
    
  switch ($PsCmdlet.ParameterSetName) {
    Direct {
      if ($Language -match '^CSharp|VisualBasic$') {

        $xml = New-Object xml
        $vars = New-TemplateVars $ProjectName -RootNamespace $RootNamespace -Language $Language

        if ($ProjectKind -match '^Library|Console|Test|ASP$') {
          $isAsp = ($ProjectKind -eq 'ASP')
          $isConsole = ($ProjectKind -eq 'Console')
          $sdk = $(if ($isAsp) { 'Microsoft.NET.Sdk.Web' } else { 'Microsoft.NET.Sdk' })
          $ext = $(if ($Language -eq 'VisualBasic') { '.vbproj' } else { '.csproj' })
          $codeExt = $(if ($Language -eq 'VisualBasic') { '.vb' } else { '.cs' })
          $typeGuid = $project_types.$Language.Core.Guid

          $xProject = $xml.AppendChild($xml.CreateElement('Project'))
          $xProject.SetAttribute('Sdk', $sdk)

          # Determine target framework version(s)
          $compileProps = @{ }
          if (($null -eq $FrameworkVersions) -or ($FrameworkVersions.Count -eq 0)) {
            $compileProps['TargetFramework'] = 'netcoreapp2.0'
          }
          elseif ($FrameworkVersions.Count -eq 1) {
            $compileProps['TargetFramework'] = $FrameworkVersions[0]
          }
          else {
            $compileProps['TargetFrameworks'] = [string]::Join(';', $FrameworkVersions)
          } 

          if ($isConsole) {
            $compileProps['OutputType'] = 'Exe'
          }

          if (Test-IsNotEmpty $AssemblyName) { $compileProps['AssemblyName'] = $AssemblyName }
          if (Test-IsNotEmpty $RootNamespace) { $compileProps['RootNamespace'] = $RootNamespace }

          $xCompileProps = Add-PropertyGroup $xProject $compileProps 'Compile'
            
          $xPackages = $xml.CreateElement('ItemGroup')
          $xPackages.SetAttribute('Label', 'PackageReferences')
          $addPackages = $false
                    
          if ($ProjectKind -eq 'Test') {
            $x = $xCompileProps.AppendChild($xml.CreateElement('IsPackable')) 
            $x.InnerText = 'false'

            Add-PackageReference $xPackages Microsoft.NET.Test.Sdk 15.6.0 | Out-Null
            Add-PackageReference $xPackages xunit 2.3.1 | Out-Null
            Add-PackageReference $xPackages xunit.runner.visualstudio 2.3.1 | Out-Null
            Add-PackageReference $xPackages dotnet-xunit 2.3.1 -ToolReference | Out-Null
            $addPackages = $true
          }
          elseif ($isAsp) {
            Add-PackageReference $xPackages Microsoft.AspNetCore.All 2.0.7 | Out-Null
            $addPackages = $true

            $templateInfo = $project_types.$Language.ASPNETCore 
            [System.IO.File]::WriteAllText($(Join-Path $ProjectDir $('Program' + $codeExt)), $(Set-TemplateVars $templateInfo.Templates.Program $vars))
            [System.IO.File]::WriteAllText($(Join-Path $ProjectDir $('Startup' + $codeExt)), $(Set-TemplateVars $templateInfo.Templates.Startup $vars))
          }
          elseif ($ProjectKind -eq 'Console') {
            $templateInfo = $project_types.$Language.Core 
            [System.IO.File]::WriteAllText($(Join-Path $ProjectDir $('Program' + $codeExt)), $(Set-TemplateVars $templateInfo.Templates.Program $vars))
          }

          if ($addPackages) {
            $xProject.AppendChild($xPackages) | Out-Null
          }


        }
        elseif ($ProjectKind -eq 'Shared') {
                
          $template = $project_types.SharedProject
          $typeGuid = $template.Guid
          $ext = '.shproj'

          $shprojXml = Set-TemplateVars $template.Templates.shproj $vars
          $xml.LoadXml($shprojXml)

          $projitemsXml = Set-TemplateVars $template.Templates.projitems $vars
          [System.IO.File]::WriteAllText($(Join-Path $ProjectDir $($ProjectName + '.projitems')), $projitemsXml)

        } 
                 
        $projectFile = Join-Path $ProjectDir $($ProjectName + $ext)
        $xml.Save($projectFile) 
      } 
    }
    Template { 
      # Init basic template properties
      if ($null -eq $TemplateProps) { $TemplateProps = @{ } 
      }

      $TemplateProps = Join-HashTables $(New-TemplateVars $ProjectName) $TemplateProps  
    }
  } 
     
  if ($null -eq $typeGuid) {
    throw (New-Object System.NotImplementedException)
  }

  Add-Project -SolutionFile $SolutionFile -ProjectFile $projectFile -ProjectType $typeGuid -SolutionFolder $SolutionFolder
}


Export-ModuleMember -Function Set-TemplateVars, New-Solution, New-Project, Get-ProjectGraph, Add-SolutionFolder, Add-Project, Get-ProjectTypeGuid