Import-Module "$PSScriptRoot\_setup.psm1"
Import-Module "$($PATHS.Source)\basicutils.psm1" 

Describe 'basicutils' {

  Context Test-IsEmpty {
    It 'returns true for $null' {
      $result = Test-IsEmpty $null
      $result | Should -Be $true
    }

    It 'returns true for empty string' {
      $result = Test-IsEmpty $([string]::Empty)
      $result | Should -Be $true
    }

    It 'returns true for whitespace string' {
      $result = Test-IsEmpty " `r`n `t "
      $result | Should -Be $true
    }

    It 'returns false for non-empty string' {
      $result = Test-IsEmpty a
      $result | Should -Be $false
    } 
  }

  Context Test-IsNotEmpty {
    It 'returns false for $null' {
      $result = Test-IsNotEmpty $null
      $result | Should -Be $false
    }

    It 'returns false for empty string' {
      $result = Test-IsNotEmpty $([string]::Empty)
      $result | Should -Be $false
    }

    It 'returns false for whitespace string' {
      $result = Test-IsNotEmpty " `r`n `t "
      $result | Should -Be $false
    }

    It 'returns true for non-empty string' {
      $result = Test-IsNotEmpty a
      $result | Should -Be $true
    } 
  } 

  Context 'Join-HashTables' {
    It 'returns a hashtable' {
      $result = Join-HashTables 
      $result | Should -BeOfType HashTable
    }

    It 'joins two tables' {
      $result = Join-HashTables @{ a = 'b' } @{ c = 'x' }
      $result.Count | Should -Be 2
      $result['a'] | Should -Be 'b'
      $result['c'] | Should -Be 'x'
    }

    It 'joins multiple tables and is case-insensitive' {
      $result = Join-HashTables @{ a = 'b' } @{ c = 'x' } @{ C = 'foo' }
      $result.Count | Should -Be 2
      $result['a'] | Should -Be 'b'
      $result['c'] | Should -Be 'foo'
    }

    It 'ignores null input' {
      $result = Join-HashTables @{ a = 'b' } $null @{ C = 'foo' }
      $result.Count | Should -Be 2
      $result['a'] | Should -Be 'b'
      $result['c'] | Should -Be 'foo'
    }
  } 
 
  Context Confirm-Module {
    It 'Loads modules relative to the calling file' {
      Get-Module '_example' | Should -BeNullOrEmpty
      
      Confirm-Module Get-Greeting _example
      Get-Module '_example' | Should -Not -BeNullOrEmpty

      Get-Greeting | Should -Be 'Hello!'
    }

    It 'Loads modules relative to the given path' {
      Get-Module 'A-Module' | Should -BeNullOrEmpty
      
      Confirm-Module Get-Answer A-Module -ModuleDir $PATHS.Scripts
      Get-Module 'A-Module' | Should -Not -BeNullOrEmpty

      Get-Answer | Should -BeExactly 42
    }
  }
}
