# Behavioral signing-runtime guards. No SDK, signing credential or network needed.
# powershell -NoProfile -File tool\windows\test_signing_runtime.ps1
# ASCII only for PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$check = Join-Path $PSScriptRoot 'check_signing_runtime.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('orthant-runtime-test-' + [Guid]::NewGuid().ToString('N'))
$savedRoot = $env:DOTNET_ROOT
$savedX64 = $env:DOTNET_ROOT_X64
$script:passed = 0
$script:failed = 0

function Expect([string]$Name, [bool]$Allowed, [hashtable]$Arguments) {
  $actual = $true
  try { & $check @Arguments | Out-Null } catch { $actual = $false }
  if ($actual -eq $Allowed) { $script:passed++; "ok $Name" }
  else { $script:failed++; "not ok $Name (expected allowed=$Allowed, got $actual)" }
}
function Runtime([string]$Version) {
  foreach ($relative in "shared\Microsoft.NETCore.App\$Version\coreclr.dll", "host\fxr\$Version\hostfxr.dll") {
    $path = Join-Path $temp $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    Set-Content -Path $path -Value ''
  }
}
function Traces([string]$Root = $temp, [string]$Version = '10.0.14', [int]$Loads = 1) {
  # Exact formats from dotnet/runtime: .NET8 fxr_resolver.cpp and .NET10
  # hostpolicy.cpp (create_coreclr). These are selected-path records, not
  # candidate probing paths. See the source links in check_signing_runtime.
  $fxr = "Resolved fxr [$Root\host\fxr\$Version\hostfxr.dll]..."
  $clr = "CoreCLR path = '$Root\shared\Microsoft.NETCore.App\$Version\coreclr.dll', CoreCLR dir = '$Root\shared\Microsoft.NETCore.App\$Version\'"
  Set-Content -Path (Join-Path $temp 'ijw.log') -Value (@($fxr) * $Loads)
  Set-Content -Path (Join-Path $temp 'host.log') -Value (@($clr) * $Loads)
}
try {
  New-Item -ItemType Directory -Path $temp | Out-Null
  $env:DOTNET_ROOT = $temp
  $env:DOTNET_ROOT_X64 = $temp
  Expect 'missing private root is refused' $false @{ Root = (Join-Path $temp 'absent') }
  Expect 'an empty root is refused' $false @{ Root = $temp }
  Runtime '8.0.33'
  Expect 'only .NET 8 is refused' $false @{ Root = $temp }
  Runtime '10.0.14'
  Expect '10 alongside 8 is refused' $false @{ Root = $temp }
  Remove-Item -Recurse -Force (Join-Path $temp 'shared\Microsoft.NETCore.App\8.0.33'), (Join-Path $temp 'host\fxr\8.0.33')
  Runtime '9.0.14'
  Expect '10 alongside 9 is refused' $false @{ Root = $temp }
  Remove-Item -Recurse -Force (Join-Path $temp 'shared\Microsoft.NETCore.App\9.0.14'), (Join-Path $temp 'host\fxr\9.0.14')
  Expect 'serviced private 10 is allowed' $true @{ Root = $temp }
  $env:DOTNET_ROOT_X64 = $null
  Expect 'missing architecture root is refused' $false @{ Root = $temp }
  $env:DOTNET_ROOT_X64 = $temp
  $env:DOTNET_ROOT_X64 = Split-Path $temp
  Expect 'architecture root mismatch is refused' $false @{ Root = $temp }
  $env:DOTNET_ROOT_X64 = $temp
  $env:DOTNET_ROOT = Split-Path $temp
  Expect 'generic root mismatch is refused' $false @{ Root = $temp }
  $env:DOTNET_ROOT = $temp
  Runtime '10.0.13'
  Expect 'unserviced private 10 is refused' $false @{ Root = $temp }
  Remove-Item -Recurse -Force (Join-Path $temp 'shared\Microsoft.NETCore.App\10.0.13'), (Join-Path $temp 'host\fxr\10.0.13')
  $args = @{ Root = $temp; CoreHostTrace = (Join-Path $temp 'ijw.log'); DotnetHostTrace = (Join-Path $temp 'host.log'); ExpectedLoads = 1; StartedUtc = [DateTime]::UtcNow.AddSeconds(-5) }
  Expect 'missing trace is refused' $false $args
  Traces
  Expect 'private serviced 10 trace is allowed' $true $args
  (Get-Item $args.CoreHostTrace).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)
  Expect 'stale trace is refused' $false $args
  Traces 'C:\Program Files\dotnet'
  Expect 'global runtime trace is refused' $false $args
  Traces
  Set-Content -Path $args.CoreHostTrace -Value 'Resolved fxr [C:\Program Files\dotnet\host\fxr\10.0.14\hostfxr.dll]...'
  Expect 'global hostfxr with private CoreCLR is refused' $false $args
  Traces
  Set-Content -Path $args.DotnetHostTrace -Value "CoreCLR path = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\10.0.14\coreclr.dll', CoreCLR dir = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\10.0.14\'"
  Expect 'private hostfxr with global CoreCLR is refused' $false $args
  Traces $temp '8.0.33'
  Expect 'old runtime trace is refused' $false $args
  Traces
  Add-Content -Path $args.DotnetHostTrace -Value "CoreCLR path = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.33\coreclr.dll', CoreCLR dir = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.33\'"
  Expect 'good evidence cannot hide a global runtime load' $false $args
  Traces
  $args.ExpectedLoads = 2
  Expect 'one installer load cannot prove both subprocesses' $false $args
  Traces $temp '10.0.14' 2
  Expect 'both installer subprocess loads are allowed' $true $args
  Set-Content -Path $args.CoreHostTrace -Value 'Considering fxr version=[10.0.14]...'
  Expect 'candidate paths do not prove a selected hostfxr' $false $args
} finally {
  $env:DOTNET_ROOT = $savedRoot
  $env:DOTNET_ROOT_X64 = $savedX64
  Remove-Item -Recurse -Force $temp
}
"$script:passed passed, $script:failed failed"
if ($script:failed) { exit 1 }
