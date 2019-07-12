Import-Module "$PSScriptRoot\_setup.psm1"
Import-Module "$PSScriptRoot\_scaffold-helpers.psm1"
Import-Module "$($PATHS.Source)\netbuild.psm1"

function Nuke ($Path) {
  try { 
    Remove-Item $(Split-Path $Path -Parent) -Force -Recurse -ErrorAction SilentlyContinue
  }
  catch {
    Write-Warning "Failed to remove directory $(Split-Path $Path -Parent): $_"
  }
}

Describe 'netbuild' {

  Context 'Get-MSBuildPath' {
    It 'validates Visual Studio version' {
      { Get-MSBuildPath -Year 1986 } | Should -Throw 'argument was out of the range'
    }
  } 

  Context 'Join-BuildArgs' {
    It 'concatenates project name, configuration' { 
      $dummyPath = 'C:\Foo\Bar.csproj'
      $src = Join-BuildArgs $dummyPath Release
      $src | Should -Be @('build', $dummyPath, '-c', 'Release')
         
      $src = Join-BuildArgs $dummyPath Release -MSBuild
      $src | Should -Be @($dummyPath, '/p:Configuration=Release') 
    }

    It 'converts property args' {
      $extraArgs = @{
        Foo            = 'Bar'
        SpecialVersion = '1.2.3.23-rc4'
      }

      $dummyPath = 'C:\Foo\Bar.csproj'
      $src = Join-BuildArgs $dummyPath Release -BuildProps $extraArgs
      Compare-Collections $src @('build', $dummyPath, '-c', 'Release', '/p:Foo=Bar', '/p:SpecialVersion=1.2.3.23-rc4') 

      $src = Join-BuildArgs $dummyPath Release -BuildProps $extraArgs -MSBuild
      Compare-Collections $src @($dummyPath, '/p:Configuration=Release', '/p:Foo=Bar', '/p:SpecialVersion=1.2.3.23-rc4')

    }

    It 'appends free form args' {
      $extraArgs = @('a', 'blah', 'x=yzb')

      $dummyPath = 'C:\Foo\Bar.csproj'
      $src = Join-BuildArgs $dummyPath Release -BuildArgs $extraArgs
      Compare-Collections $src @('build', $dummyPath, '-c', 'Release', 'a', 'blah', 'x=yzb') 

      $src = Join-BuildArgs $dummyPath Release -BuildArgs $extraArgs -MSBuild
      Compare-Collections $src @($dummyPath, '/p:Configuration=Release', 'a', 'blah', 'x=yzb')
    }
  }

  Context Get-ProjectFile {
    
    It 'finds exact match' {
      $sln = New-DummySolution FindTest
      $prj = New-DummyProject lib CSharp.Core $sln
      Get-ProjectFile $prj | Should -Be $prj
      Nuke $sln
    }

    It 'finds match without extension' {
      $sln = New-DummySolution FindTest
      $prj = New-DummyProject lib CSharp.Core $sln
      $prjNoExt = $prj.Replace('.csproj', '')
      Get-ProjectFile $prjNoExt | Should -Be $prj
      Nuke $sln
    }

    It 'finds project in folder' {
      $sln = New-DummySolution FindTest
      $prj = New-DummyProject lib CSharp.Core $sln
      Get-ProjectFile $(Split-Path $prj -Parent) | Should -Be $prj
      Nuke $sln
    }

    It 'finds project in current folder' {
      $sln = New-DummySolution FindTest
      $prj = New-DummyProject lib CSharp.Core $sln
      Set-CurrentDirectory $(Split-Path $prj -Parent)
      Get-ProjectFile | Should -Be $prj
      Set-CurrentDirectory $module_root
      Nuke $sln
    }

    It 'works with relative paths' {
      $sln = New-DummySolution FindTest
      $prj = New-DummyProject lib CSharp.Core $sln
      Set-CurrentDirectory $(Split-Path $sln -Parent)
      Get-ProjectFile lib | Should -Be $prj
      Set-CurrentDirectory $module_root
      Nuke $sln
    }
     
    It 'throws error for non-existent start path' {
      Get-ProjectFile 'X:\Y\ZizzerZazzer\Zuz' 2>$null
      $Error[0].Exception.Message | Should -Match 'not found'
    }

    It 'throws error if no project in directory' {
      Get-ProjectFile 'C:\Users' 2>$null  
      $Error[0].Exception.Message | Should -Match 'No project file found in directory'
    } 
  }
 
  Context Get-SolutionDir {
    It 'finds the nearest directory containing a .sln file' { 
      $expected = Join-Path $PATHS.BuildFiles '..' -Resolve
      Get-SolutionDir $PATHS.Templates | Should -Be $expected
    }
  }
 
  Context Convert-BuildExpression { 
    It 'replaces property values' {
      $props = @{ 
        TargetFramework = 'net45' 
        Configuration   = 'Release'
      };

      $raw = "'`$(TargetFramework)|`$(Configuration)'=='net45|Debug'"
      Convert-BuildExpression $raw $props | Should -Be "'net45|Release'=='net45|Debug'" 
    } 

    It 'removes non-existent properties' {
      $props = @{ 
        TargetFramework = 'net45' 
        Configuration   = 'Release'
      };

      $raw = "'`$(NotDefined)'==''"
      Convert-BuildExpression $raw $props | Should -Be "''==''" 
    } 
  }

  # See https://docs.microsoft.com/en-us/visualstudio/msbuild/msbuild-conditions
  Context Invoke-BuildExpression {
    It 'supports == operator' { 
      Invoke-BuildExpression "'C:\Users'=='C:\Users'" | Should -BeExactly $true
      Invoke-BuildExpression "'C:\Users'=='C:\Windows'" | Should -BeExactly $false
    }

    It 'supports != operator' { 
      Invoke-BuildExpression "'C:\Users'!='C:\Users'" | Should -BeExactly $false
      Invoke-BuildExpression "'C:\Users'!='C:\Windows'" | Should -BeExactly $true
    }

    It 'supports And operator' { 
      Invoke-BuildExpression "('A'=='A') And ('B'=='B')" | Should -BeExactly $true
      Invoke-BuildExpression "('A'=='A') And ('B'=='C')" | Should -BeExactly $false
    }

    It 'supports Or operator' { 
      Invoke-BuildExpression "('A'=='A') Or ('B'=='C')" | Should -BeExactly $true
      Invoke-BuildExpression "('A'=='B') Or ('B'=='C')" | Should -BeExactly $false
    }

    It 'supports < operator' { 
      Invoke-BuildExpression "(1 < 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 < 1)" | Should -BeExactly $false
    }

    It 'supports > operator' { 
      Invoke-BuildExpression "(2 > 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 > 2)" | Should -BeExactly $false
    }

    It 'supports <= operator' { 
      Invoke-BuildExpression "(1 <= 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 <= 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 <= 1)" | Should -BeExactly $false
    }

    It 'supports >= operator' { 
      Invoke-BuildExpression "(2 >= 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 >= 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 >= 2)" | Should -BeExactly $false
    }

    It 'supports < operator (escaped)' { 
      Invoke-BuildExpression "(1 &lt; 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 &lt; 1)" | Should -BeExactly $false
    }

    It 'supports > operator (escaped)' { 
      Invoke-BuildExpression "(2 &gt; 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 &gt; 2)" | Should -BeExactly $false
    }

    It 'supports <= operator (escaped)' { 
      Invoke-BuildExpression "(1 &lt;= 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 &lt;= 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 &lt;= 1)" | Should -BeExactly $false
    }

    It 'supports >= operator (escaped)' { 
      Invoke-BuildExpression "(2 &gt;= 1)" | Should -BeExactly $true
      Invoke-BuildExpression "(2 &gt;= 2)" | Should -BeExactly $true
      Invoke-BuildExpression "(1 &gt;= 2)" | Should -BeExactly $false
    }
  }

  Context Get-ProjectProperties {
    
    It 'walks full tree' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
      $props = Get-ProjectProperties $testProj

      $props['Product'] | Should -Be 'Test'
      $props['GrandparentProp'] | Should -Be 'grandparent'
      $props['ParentProp'] | Should -Be 'parent'
      $props['DefaultProp'] | Should -Be 'new value'
      $props['AssemblyName'] | Should -Be 'test.lib'
    }

    It 'evaluates property expressions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
      $props = Get-ProjectProperties $testProj

      $props['SemVer'] | Should -Be '1.2.3'
      $props['FileVersion'] | Should -Be '1.2.3.98'
    }

    It 'evaluates property group condition expressions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
        
      $props = Get-ProjectProperties $testProj 
      $props['TestProp'] | Should -Be 'Initial Value'

      $props = Get-ProjectProperties $testProj @{ ForceDefault = 'True' }
      $props['TestProp'] | Should -Be 'Default Value'

      $props = Get-ProjectProperties $testProj @{ Configuration = 'Debug' }
      $props['PackageVersion'] | Should -Be '1.2.3-rc98-debug' 
        
      $props = Get-ProjectProperties $testProj @{ Configuration = 'Release'; ReleaseMode = 'Release' }
      $props['PackageVersion'] | Should -Be '1.2.3' 
    }

    It 'evaluates property condition expressions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve

      $props = Get-ProjectProperties $testProj @{ ExcludeProp = 'True' }
      $props['TestProp'] | Should -Be 'Default Value' 
    }

    It 'evaluates import condition expressions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve

      $props = Get-ProjectProperties $testProj @{ IncludeSpecialProps = 'True' }
      $props['TestProp'] | Should -Be 'Special Value' 
    }
  }

  Context Find-ProjectProperty {
 
    It 'finds simple prop' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve

      $info = Find-ProjectProperty $testProj AssemblyName
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[2]/AssemblyName'
      $info.Expression | Should -Be 'test.lib'
    }
     
    It 'finds parent props' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
      $propsProj = Join-Path $PATHS.BuildFiles 'Project\props.csproj' -Resolve

      $info = Find-ProjectProperty $testProj FileVersion
      $info.FilePath | Should -Be $propsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[2]/FileVersion'
      $info.Expression | Should -Be '$(SemVer).$(MinorBuildVersion)'
    }

    It 'finds grandparent props' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
      $dirProj = Join-Path $PATHS.BuildFiles 'dirprops.csproj' -Resolve

      $info = Find-ProjectProperty $testProj Product
      $info.FilePath | Should -Be $dirProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/Product'
      $info.Expression | Should -Be 'Test'
    }
     
    It 'finds nearest prop' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve
      $propsProj = Join-Path $PATHS.BuildFiles 'Project\props.csproj' -Resolve

      $info = Find-ProjectProperty $testProj BaseProp
      $info.FilePath | Should -Be $propsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[2]/BaseProp'
      $info.Expression | Should -Be 'overridden'

      $info = Find-ProjectProperty $testProj DefaultProp
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[2]/DefaultProp'
      $info.Expression | Should -Be 'new value'
    }

    It 'respects property group conditions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve 
      $propsProj = Join-Path $PATHS.BuildFiles 'Project\props.csproj' -Resolve
        
      $info = Find-ProjectProperty $testProj TestProp
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/TestProp'
      $info.Expression | Should -Be 'Initial Value'
        
      $info = Find-ProjectProperty $testProj TestProp @{ ForceDefault = 'True' }
      $info.FilePath | Should -Be $propsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[6]/TestProp'
      $info.Expression | Should -Be 'Default Value'
    }

    It 'respects import conditions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve 
      $sppropsProj = Join-Path $PATHS.BuildFiles 'Project\specialprops.csproj' -Resolve
        
      $info = Find-ProjectProperty $testProj TestProp  
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/TestProp'
      $info.Expression | Should -Be 'Initial Value'

      $info = Find-ProjectProperty $testProj TestProp @{ IncludeSpecialProps = 'True' }
      $info.FilePath | Should -Be $sppropsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/TestProp'
      $info.Expression | Should -Be 'Special Value'

    }

    It 'respects property conditions' {
      $testProj = Join-Path $PATHS.BuildFiles 'Project\test.csproj' -Resolve 
      $propsProj = Join-Path $PATHS.BuildFiles 'Project\props.csproj' -Resolve
         
      $info = Find-ProjectProperty $testProj TestProp 
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/TestProp'
      $info.Expression | Should -Be 'Initial Value'

      $info = Find-ProjectProperty $testProj TestProp @{ ExcludeProp = $true }
      $info.FilePath | Should -Be $propsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[6]/TestProp'
      $info.Expression | Should -Be 'Default Value'
    }

  }

  Context Set-ProjectProperty {
    
    It 'sets a simple property' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      Set-ProjectProperty $testProj AssemblyName 'NewAsmName'
        
      $info = Find-ProjectProperty $testProj AssemblyName
      $info.FilePath | Should -Be $testProj
      $info.XPath | Should -Be '/Project/PropertyGroup[2]/AssemblyName'
      $info.Expression | Should -Be 'NewAsmName'

      Remove-Item $tempDir -Force -Recurse 
    }

    It 'sets a parent property' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve 
      $propsProj = Join-Path $tempDir 'Project\props.csproj' -Resolve 

      Set-ProjectProperty $testProj ParentProp 'NewValue'
        
      $info = Find-ProjectProperty $testProj ParentProp
      $info.FilePath | Should -Be $propsProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/ParentProp'
      $info.Expression | Should -Be 'NewValue'

      Remove-Item $tempDir -Force -Recurse 
    }
    
    It 'sets a grandparent property' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      $dirProj = Join-Path $tempDir 'dirprops.csproj' -Resolve

      Set-ProjectProperty $testProj Product 'NewProduct'
        
      $info = Find-ProjectProperty $testProj Product
      $info.FilePath | Should -Be $dirProj
      $info.XPath | Should -Be '/Project/PropertyGroup[1]/Product'
      $info.Expression | Should -Be 'NewProduct'

      Remove-Item $tempDir -Force -Recurse 
    }

  }


  Context Set-ProjectVersion {
    
    It 'directly sets minor build' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      Set-ProjectVersion $testProj -MinorBuild -Version 478
      $props = Get-ProjectProperties $testProj
      $props['MinorBuildVersion'] | Should -Be 478

      Remove-Item $tempDir -Force -Recurse 
    }

    It 'resets minor build when incrementing build' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      Set-ProjectVersion $testProj -Build -Increment

      $props = Get-ProjectProperties $testProj
      $props['BuildVersion'] | Should -Be 4
      $props['MinorBuildVersion'] | Should -Be 0

      Remove-Item $tempDir -Force -Recurse
    }
    
    It 'resets build and minor build when incrementing minor' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      Set-ProjectVersion $testProj -Minor -Increment

      $props = Get-ProjectProperties $testProj
      $props['MinorVersion'] | Should -Be 3
      $props['BuildVersion'] | Should -Be 0
      $props['MinorBuildVersion'] | Should -Be 0

      Remove-Item $tempDir -Force -Recurse
    }

    It 'resets minor, build and minor build when incrementing major' {
      $tempDir = [System.IO.Path]::Combine($env:TEMP, 'netbuild', [Guid]::NewGuid().ToString('n'))
      mkdir $tempDir | Out-Null
      Copy-Item "$($PATHS.BuildFiles)\*" $tempDir -Recurse

      $testProj = Join-Path $tempDir 'Project\test.csproj' -Resolve
      Set-ProjectVersion $testProj -Major -Increment

      $props = Get-ProjectProperties $testProj
      $props['MajorVersion'] | Should -Be 2
      $props['MinorVersion'] | Should -Be 0
      $props['BuildVersion'] | Should -Be 0
      $props['MinorBuildVersion'] | Should -Be 0

      Remove-Item $tempDir -Force -Recurse
    }

  }

  Context Get-AssemblyName {
    It 'uses explicit AssemblyName project property' {
      $slnFile = New-DummySolution CleanTest
      $prjFile = New-DummyProject lib CSharp.Core $slnFile
      $prjDir = Split-Path $prjFile -Parent

      Set-ProjectProperty $prjFile AssemblyName 'Example.Lib'

      # Check expected function result
      Get-AssemblyName $prjFile | Should -Be Example.Lib

      # Confirm this is actually what is built
      dotnet build $prjFile 
      $(Get-ChildItem "$prjDir\bin\Debug\*\Example.Lib.dll").Count | Should -Be 1
             
      Remove-Item (Split-Path $slnFile -Parent) -Force -Recurse
    }

    It 'falls back to project file base name' {
      $slnFile = New-DummySolution CleanTest
      $prjFile = New-DummyProject lib CSharp.Core $slnFile
      $prjDir = Split-Path $prjFile -Parent
             
      # Check expected function result
      Get-AssemblyName $prjFile | Should -Be lib

      # Confirm this is actually what is built
      dotnet build $prjFile 
      $(Get-ChildItem "$prjDir\bin\Debug\*\lib.dll").Count | Should -Be 1
             
      Remove-Item (Split-Path $slnFile -Parent) -Force -Recurse
    }
  }

  Context 'Invoke-Clean' {

    It 'removes root bin and obj dir' {
      $slnFile = New-DummySolution CleanTest
      $prjFile = New-DummyProject lib CSharp.Core $slnFile
      $prjDir = Split-Path $prjFile -Parent

      # Create bin, obj and confirm they exist
      dotnet build $prjFile
      $(Get-ChildItem "$prjDir\bin\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\*" -Recurse).Count | Should -BeGreaterThan 0

      Invoke-Clean $prjDir 

      # Bin cleaned, obj not:
      Test-Path "$prjDir\bin" | Should -Be $false
      $(Get-ChildItem "$prjDir\obj\*" -Recurse).Count | Should -BeGreaterThan 0
            
      # Create bin, obj and confirm they exist
      dotnet build $prjFile
      $(Get-ChildItem "$prjDir\bin\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\*" -Recurse).Count | Should -BeGreaterThan 0

      Invoke-Clean $prjDir -Obj

      # Both:
      Test-Path "$prjDir\bin" | Should -Be $false
      Test-Path "$prjDir\obj" | Should -Be $false
             
      Remove-Item (Split-Path $slnFile -Parent) -Force -Recurse
    } 

    It 'removes configuration-specific bin and obj dir' {
      $slnFile = New-DummySolution CleanTest
      $prjFile = New-DummyProject lib CSharp.Core $slnFile
      $prjDir = Split-Path $prjFile -Parent

      # Create bin, obj and confirm they exist
      dotnet build $prjFile
      dotnet build $prjFile -c Release
      $(Get-ChildItem "$prjDir\bin\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\bin\Release\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Release\*" -Recurse).Count | Should -BeGreaterThan 0

      Invoke-Clean $prjDir -Configuration Release

      # bin\Release cleaned, others not:
      $(Get-ChildItem "$prjDir\bin\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      Test-Path "$prjDir\bin\Release" | Should -Be $false
      $(Get-ChildItem "$prjDir\obj\Release\*" -Recurse).Count | Should -BeGreaterThan 0
            
      # Create bin, obj and confirm they exist
      dotnet build $prjFile -c Release
      $(Get-ChildItem "$prjDir\bin\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\bin\Release\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Release\*" -Recurse).Count | Should -BeGreaterThan 0
            
      Invoke-Clean $prjDir -Configuration Release -Obj

      # Both bin\Release and obj\Release cleaned:
      $(Get-ChildItem "$prjDir\bin\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      $(Get-ChildItem "$prjDir\obj\Debug\*" -Recurse).Count | Should -BeGreaterThan 0
      Test-Path "$prjDir\bin\Release" | Should -Be $false
      Test-Path "$prjDir\obj\Release" | Should -Be $false
             
      Remove-Item (Split-Path $slnFile -Parent) -Force -Recurse
    } 
  } 
}