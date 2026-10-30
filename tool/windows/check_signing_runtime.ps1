# Verifies the private native signing runtime before use, and optionally the
# selected hostfxr/CoreCLR paths from one freshly traced signing phase.
# Trace bodies and failures must stay in encrypted diagnostics.
#
# Selected-path trace formats (not candidate paths):
# https://github.com/dotnet/runtime/blob/b753199016332cbf257e70c417aa5d1d02202dc7/src/native/corehost/fxr_resolver.cpp
# https://github.com/dotnet/runtime/blob/v10.0.0/src/native/corehost/hostpolicy/hostpolicy.cpp
# ASCII only for PowerShell 5.1.
param(
  [Parameter(Mandatory = $true)] [string]$Root,
  [string]$CoreHostTrace = '',
  [string]$DotnetHostTrace = '',
  [int]$ExpectedLoads = 0,
  [DateTime]$StartedUtc = [DateTime]::MinValue
)
$ErrorActionPreference = 'Stop'

function Fail([string]$Why) { throw "check_signing_runtime: $Why" }
function FullPath([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { Fail 'a runtime root is missing' }
  (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
}
function Serviced10([string]$Version) {
  $Version -match '^10\.\d+\.\d+$' -and [Version]$Version -ge [Version]'10.0.14'
}

$Root = FullPath $Root
foreach ($name in 'DOTNET_ROOT', 'DOTNET_ROOT_X64') {
  if ((FullPath ([Environment]::GetEnvironmentVariable($name))) -ine $Root) { Fail 'the native runtime roots do not match the private root' }
}
foreach ($relative in 'shared\Microsoft.NETCore.App', 'host\fxr') {
  $directory = Join-Path $Root $relative
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { Fail 'the private runtime inventory is missing' }
  $versions = @(Get-ChildItem -LiteralPath $directory -Directory)
  if (-not $versions.Count) { Fail 'the private runtime inventory is empty' }
  foreach ($version in $versions) {
    if (-not (Serviced10 $version.Name)) { Fail 'the private runtime inventory must contain only serviced .NET 10' }
    $library = if ($relative -eq 'host\fxr') { 'hostfxr.dll' } else { 'coreclr.dll' }
    if (-not (Test-Path -LiteralPath (Join-Path $version.FullName $library) -PathType Leaf)) { Fail 'a private runtime library is missing' }
  }
}
if (-not $CoreHostTrace -and -not $DotnetHostTrace -and $ExpectedLoads -eq 0) {
  'private signing runtime inventory verified (.NET 10, minimum 10.0.14)'
  return
}
if ($ExpectedLoads -lt 1 -or $StartedUtc -eq [DateTime]::MinValue) { Fail 'trace validation needs the phase start time and expected signing count' }
$traces = @(
  @{ Path = $CoreHostTrace; Pattern = '(?m)^Resolved fxr \[([^\r\n]+)\]\.\.\.\r?$'; Relative = 'host\fxr'; Library = 'hostfxr.dll' },
  @{ Path = $DotnetHostTrace; Pattern = "(?m)^CoreCLR path = '([^'\r\n]+)', CoreCLR dir = '[^'\r\n]+'\r?$"; Relative = 'shared\Microsoft.NETCore.App'; Library = 'coreclr.dll' }
)
foreach ($trace in $traces) {
  if (-not $trace.Path -or -not (Test-Path -LiteralPath $trace.Path -PathType Leaf)) { Fail 'a signing host trace is missing' }
  if ((Get-Item -LiteralPath $trace.Path).LastWriteTimeUtc -lt $StartedUtc.ToUniversalTime()) { Fail 'a signing host trace predates this phase' }
  $loads = [regex]::Matches([IO.File]::ReadAllText($trace.Path), $trace.Pattern)
  if ($loads.Count -ne $ExpectedLoads) { Fail 'the signing host trace does not prove every expected runtime load' }
  $prefix = (Join-Path $Root $trace.Relative) + '\'
  foreach ($load in $loads) {
    $path = $load.Groups[1].Value
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { Fail 'a signing host selected a runtime outside the private root' }
    $suffix = $path.Substring($prefix.Length)
    $parts = $suffix.Split('\')
    if ($parts.Count -ne 2 -or -not (Serviced10 $parts[0]) -or $parts[1] -ine $trace.Library) { Fail 'a signing host selected an unexpected runtime library' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail 'a selected private runtime library is missing' }
  }
}
'verified {0} private .NET 10 signing runtime loads (hostfxr and CoreCLR)' -f $ExpectedLoads
