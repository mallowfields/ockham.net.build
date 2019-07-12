$fixtures_root = Join-Path $PSScriptRoot '.\fixtures' -Resolve

$PATHS = @{
  Source   = Join-Path $PSScriptRoot '..\..\src\psbuild' -Resolve
  Fixtures = $fixtures_root
  Scripts  = Join-Path $fixtures_root Scripts -Resolve 
  Templates = Join-Path $fixtures_root  Templates -Resolve
  BuildFiles = Join-Path $fixtures_root BuildFiles -Resolve
}

function Compare-Collections {

  param($a, $b)

  if ($a -eq $null) { throw 'Input cannot be null' }
  if ($b -eq $null) { throw 'Input cannot be null' }
  if ($a.Count -ne $b.Count) { throw "Collection 1 count $($a.Count) does not match collection 2 count $($b.Count)" }

  for ($i = 0 ; $i -lt $a.Count; $i++) {
    $itemA = $a[$i]
    $itemB = $b[$i]
    $itemA | Should -Be $itemB
  }
}
 
Export-ModuleMember -Variable PATHS -Function Compare-Collections
