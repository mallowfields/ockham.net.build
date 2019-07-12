function newobj([hashtable]$properties) {
  New-Object psobject -Property $properties
}
 
$vs_project_types = newobj @{
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
    Core         = newobj @{
      Guid = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'   
    } 
    ASPNETCore   = newobj @{
      Guid = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'   
    } 
    ClassLibrary = newobj @{
      Guid = '{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}' 
    } 
    Console      = newobj @{
      Guid = '{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}' 
    } 
  } 
  VisualBasic   = newobj @{
    Core = newobj @{
      Guid = '{F184B08F-C81C-45F6-A57F-5ABD9991F28F}'
    }
  }
}
  
function Get-ProjectTypeGuid {

  param([object]$InputObject)

  if ($null -eq $InputObject) { return $null }

  if ($InputObject -is [guid]) {
    return $InputObject.ToString('B').ToUpper()
  }
     
  if ($InputObject -is [string]) {
    if ([string]::IsNullOrEmpty($InputObject)) { return $null }

    # Test if string is a guid
    [guid]$guid = [Guid]::Empty
    if ([Guid]::TryParse($InputObject, [ref]$guid)) {
      return $guid.ToString('B').ToUpper()
    }

    # Test if string is a known project type name
    switch -Regex ($InputObject.ToLower()) {
      '^(solution)?folder$' { return $vs_project_types.Folder.Guid }
      '^shared(project)?$' { return $vs_project_types.SharedProject.Guid }
      '^(csharp\.)?core$' { return $vs_project_types.CSharp.Core.Guid }
      '^(csharp\.)?aspnetcore$' { return $vs_project_types.CSharp.ASPNETCore.Guid }
      '^(csharp\.)?classlibrary$' { return $vs_project_types.CSharp.ClassLibrary.Guid }
      '^(csharp\.)?console$' { return $vs_project_types.CSharp.Console.Guid }
      '^visualbasic\.core$' { return $vs_project_types.VisualBasic.Core.Guid } 
    }


    if ((Test-Path $InputObject) -and ($InputObject.ToLower().EndsWith("proj"))) {
      # Guess from project file
      $fullPath = (Get-Item $InputObject).FullName
      $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
      if ($ext -eq '.shproj') { return $vs_project_types.SharedProject.Guid }

      try {  
        $xProject = ([xml][string](Get-Content $InputObject)).DocumentElement
        if (![string]::IsNullOrEmpty($xProject.Sdk)) {
          $sdk = $xProject.Sdk.ToLower()
          switch ($sdk) {
            microsoft.net.sdk { 
              switch ($ext) {
                .csproj { return $vs_project_types.CSharp.Core.Guid }
                .vbproj { return $vs_project_types.VisualBasic.Core.Guid }
              }
            }

          }
        }
      }
      catch { }
    }
  }

  return $null

}

Export-ModuleMember -Variable vs_project_types -Function Get-ProjectTypeGuid
