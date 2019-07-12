Import-Module "$PSScriptRoot\_setup.psm1"
Import-Module "$($PATHS.Source)\pathutils.psm1"

Describe 'pathutils' {

    Context Test-FSPath {
        It 'returns true for relative path that exists' {
            $relativePath = '.\temp-file.txt'
            'Hello world' > $relativePath
            $result = Test-FSPath $relativePath
            $result | Should -Be $true
            Remove-Item $relativePath            
        }

        It 'returns true for an absolute path that exists' {
            $absPath = "$env:TEMP\temp-file.txt"
            'Hello world' > $absPath
            $result = Test-FSPath $absPath
            $result | Should -Be $true
            Remove-Item $absPath     
        } 

        It 'returns true for UNC path' {
            $absPath = [regex]::Replace("$env:TEMP\temp-file.txt", '^([a-zA-Z])(\:)', '\\localhost\$1$')
            'Hello world' > $absPath
            $result = Test-FSPath $absPath
            $result | Should -Be $true
            Remove-Item $absPath      
        }

        It 'returns false for valid PowerShell non-file system path' {
            $result = Test-FSPath function:\Test-FSPath
            $result | Should -Be $false
        }

        It 'returns true for a path not supported by PowerShell Test-Path' {
            $absPath = "$env:TEMP\temp-file[weird-chars.txt"
            [System.IO.File]::WriteAllText($absPath, 'Hello world')
            $result = Test-FSPath $absPath
            $result | Should -Be $true 
             [System.IO.File]::Delete($absPath)
        } 
    }

    Context 'Set-CurrentDirectory' {
        It 'syncs Environment.CurrentDirectory to powershell Location' {
            # Intentionally make different:
            Set-Location C:\
            [Environment]::CurrentDirectory = 'C:\Windows'

            (Get-Location).Path | Should -Not -Be $([Environment]::CurrentDirectory) 

            Set-CurrentDirectory 
            (Get-Location).Path | Should -Be $([Environment]::CurrentDirectory) 
            [Environment]::CurrentDirectory | Should -Be 'C:\'
        }

        It 'sets both Environment.CurrentDirectory and powershell Location' {
            # Intentionally make different:
            Set-Location C:\
            [Environment]::CurrentDirectory = 'C:\Windows'

            (Get-Location).Path | Should -Not -Be $([Environment]::CurrentDirectory) 

            Set-CurrentDirectory C:\Users
            (Get-Location).Path | Should -Be C:\Users
            [Environment]::CurrentDirectory  | Should -Be C:\Users
        }
    }

    Context 'Get-CurrentDirectory' {
        It 'syncs Environment.CurrentDirectory to powershell Location' {
            # Intentionally make different:
            Set-Location C:\Users
            [Environment]::CurrentDirectory = 'C:\Windows'

            (Get-Location).Path | Should -Not -Be $([Environment]::CurrentDirectory) 

            $p = Get-CurrentDirectory 
            $p | Should -Be C:\Users
            (Get-Location).Path | Should -Be C:\Users
            [Environment]::CurrentDirectory | Should -Be C:\Users
        }

        It 'syncs powershell Location to Environment.CurrentDirectory if powershell is not in FileSystem context' {
            # Intentionally make different:
            Set-Location HKLM:\SOFTWARE
            [Environment]::CurrentDirectory = 'C:\Windows'

            (Get-Location).Path | Should -Not -Be $([Environment]::CurrentDirectory) 

            $p = Get-CurrentDirectory 
            $p | Should -Be C:\Windows
            (Get-Location).Path | Should -Be C:\Windows
            [Environment]::CurrentDirectory | Should -Be C:\Windows
        }
    } 
}