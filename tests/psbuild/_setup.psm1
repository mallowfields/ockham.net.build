$fixtures_root = Join-Path $PSScriptRoot '.\fixtures' -Resolve

$PATHS = @{
  Source   = Join-Path $PSScriptRoot '..\..\src\psbuild' -Resolve
  Fixtures = $fixtures_root
  Scripts  = Join-Path $fixtures_root Scripts -Resolve 
}
 
Export-ModuleMember -Variable PATHS
