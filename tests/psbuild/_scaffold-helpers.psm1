Import-Module "$PSScriptRoot\_setup.psm1"

function newobj([hashtable]$properties) {
  New-Object psobject -Property $properties
}

$project_types = newobj @{
  Folder = newobj @{
    Guid     = '{2150E333-8FDC-42A3-9474-1A3956D46DE8}'
    Template = $null
  }
  CSharp = newobj @{
    SharedProject      = newobj @{
      Guid      = '{D954291E-2A0B-460D-934E-DC6B0785DB48}'
      Templates = @(
        'CSharp\SharedProject\template.shproj', 
        'CSharp\SharedProject\template.projitems'
      )
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
    Core               = newobj @{
      Guid      = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'
      Templates = @( 
        'CSharp\Core\template.csproj',
        'CSharp\Core\SimpleClass.cs' 
      )
    } 
  } 
}

function Get-ProjectType {
  param([string]$ProjectTypeName)

  $parts = $ProjectTypeName.Split('.')
  $result = $project_types
  foreach ($item in $parts) {
    $result = $result.$item
  }
  return $result
}

function Replace-TemplateVars {

  param([string]$Content, [hashtable]$Variables)

  foreach ($varName in $Variables.Keys) {
    $varTag = $varName
    if (!$varTag.StartsWith('$')) { $varTag = '$' + $varTag }
    if (!$varTag.EndsWith('$')) { $varTag = $varTag + '$' }
    $Content = $Content.Replace($varTag, $Variables[$varName])
  }

  return $Content
}

function Find-Line {
  param([System.Collections.Generic.IEnumerable[string]]$InputObject, $Pattern, [switch]$Regex, [switch]$Escape)

  if ($Regex -and $Escape) {
    $Pattern = [regex]::Escape($Pattern)
  }

  $i = 0
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

function New-DummySolution {
    
  param([string]$SolutionName)

  $slnGuid = [Guid]::NewGuid()
  $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild' , 'temp_projects', $slnGuid.ToString('n'))
  if (Test-Path $tempDir) { Remove-Item $tempDir -Force -Recurse }
  mkdir $tempDir | Out-Null

  $slnFile = [System.IO.Path]::Combine($tempDir, $SolutionName + '.sln')
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

function New-DummyProject {

  param([string]$ProjectName, [string]$ProjectTypeName, [string]$SolutionFile)
     
  $projectType = Get-ProjectType $ProjectTypeName
  $slnDir = Split-Path $SolutionFile -Parent
  $projDir = Join-Path $slnDir $ProjectName
    
  # Create the project directory
  if (Test-Path $projDir) { Remove-Item $projDir -Force -Recurse }
  mkdir $projDir | Out-Null
     
  # Render and save the project files
  $vars = @{
    guid1           = [Guid]::NewGuid().ToString('B').ToUpper()
    guid2           = [Guid]::NewGuid().ToString('B').ToUpper()
    guid3           = [Guid]::NewGuid().ToString('B').ToUpper()
    guid4           = [Guid]::NewGuid().ToString('B').ToUpper()
    projectname     = $ProjectName
    safeprojectname = $ProjectName
  }

  $mainFile = $null
    
  foreach ($srcPath in $projectType.Templates) {  
    $srcFile = Join-Path $PATHS.Templates $srcPath
    $srcText = [System.IO.File]::ReadAllText($srcFile)
    $outFileName = Split-Path $srcFile -Leaf
    if ($outFileName -like 'template.*') {
      $outFileName = $ProjectName + [System.IO.Path]::GetExtension($outFileName)
    }
         
    $outFile = [System.IO.Path]::Combine($projDir, $outFileName)
    if ($null -eq $mainFile) { $mainFile = $outFile }
    $srcText = Replace-TemplateVars $srcText $vars
    [System.IO.File]::WriteAllText($outFile, $srcText)
  }

  # Add the project to the solution
  $solutionContent = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($SolutionFile))
  $i = Find-Line $solutionContent 'Global'
     
  $projectGuid = $vars['guid1']

  # Insert the project
  $solutionContent.InsertRange($i, [string[]]@(
      "Project(`"$($projectType.Guid)`") = `"$ProjectName`", `"$ProjectName\$(Split-Path $mainFile -Leaf)`", `"$projectGuid`"",
      "EndProject" 
    ))
    
  $i = Find-Line $solutionContent '^\s+GlobalSection\(ProjectConfigurationPlatforms\) = postSolution' -Regex
  $i += 1

  # Insert project config info
  $solutionContent.InsertRange($i, [string[]]@(
      "`t`t$projectGuid.Debug|Any CPU.ActiveCfg = Debug|Any CPU",
      "`t`t$projectGuid.Debug|Any CPU.Build.0 = Debug|Any CPU",
      "`t`t$projectGuid.Release|Any CPU.ActiveCfg = Release|Any CPU",
      "`t`t$projectGuid.Release|Any CPU.Build.0 = Release|Any CPU"
    ))
    
  [System.IO.File]::WriteAllLines($SolutionFile, $solutionContent)

  return $mainFile
}

Export-ModuleMember -Function Get-ProjectType, New-DummyProject, New-DummySolution, Replace-TemplateVars, Fine-Line -Variable project_types

