#------------------------------
# Exported functions
#------------------------------ 
<#
  Test whether the input value is null, or an empty or whitespace string
#>  
function Test-IsEmpty ([string]$Value) { return [string]::IsNullOrWhiteSpace($Value) }
 
<#
  Test whether the input value is a non-null string with no-whitespace characters
#>  
function Test-IsNotEmpty ([string]$Value) { return ![string]::IsNullOrWhiteSpace($Value) }
 
function Confirm-Module ([string]$CmdletName, [string]$ModuleName, [string]$ModuleDir) {
  if(Test-IsEmpty $ModuleDir) {
    # First try to get the directory of whichever script file called Confirm-Module
    $ModuleDir = Split-Path (Get-PSCallStack)[1].ScriptName -Parent
  }

  if(Test-IsEmpty $ModuleDir) {
    # Fall back to environment current directory. NOT the same as Get-Location, which could
    # return a non-filesystem context such as HKLM:\...
    $ModuleDir = [System.Environment]::CurrentDirectory
  }

  if (!(Test-Path "function:\$CmdletName")) { 
    $modulePath = "$ModuleDir\$ModuleName.psm1"
    if (!(Test-Path $modulePath)) {
      Write-Error "$ModuleName module is not loaded, and $ModuleName.psm1 not found in directory $ModuleDir"
      return
    }
    else {
      Import-Module $modulePath -Global
    }
  } 
}

<#
  .SYNOPSIS 
  Write a repeated character, defaulting to 120 x '='
#>
function Write-Bar {
  param([string]$Char = '=', [int]$Length = 120)
    
  if ([string]::IsNullOrEmpty($Char)) { $Char = '=' }
  $Char = $Char.Substring(0, 1)
  Write-Host $($Char * $Length)
}

<#
  .SYNOPSIS
  Write two full-line bars (Write-Bar) with a message in the line between them
#>
function Write-Banner {
  param([string]$Message, [string]$Char = '=')
     
  Write-Bar $Char 
  Write-Host " $Message"
  Write-Bar $Char
}
 
<#
  .SYNOPSIS 
  Create a new HashTable that merges the input HashTables. Entries in the later HashTables will overwrite 
  those from previous HashTables if the same key is present. None of the input HashTables is modified
#>
function Join-HashTables {
  param([hashtable]$Input1, [hashtable]$Input2, [hashtable]$Input3, [hashtable]$Input4, [hashtable]$Input5)

  $result = @{ }
  foreach ($h in @($Input1, $Input2, $Input3, $Input4, $Input5)) {
    if ($null -ne $h) {
      foreach ($k in $h.Keys) {
        $result[$k] = $h[$k]
      }
    }
  }

  , $result
}

function newobj([hashtable]$properties) {
  New-Object psobject -Property $properties
}

Export-ModuleMember -Function newobj, Confirm-Module, Join-HashTables, Test-IsEmpty, Test-IsNotEmpty, Write-Banner, Write-Bar
