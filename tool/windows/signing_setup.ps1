# Fetches the Authenticode signing tools at pinned versions, checks each
# package's SHA-256, unpacks them, and writes the Artifact Signing metadata
# the client reads. Prints the tools' paths and versions, never the account's
# names; writes SIGNTOOL, SIGNING_DLIB and SIGNING_METADATA to $env:GITHUB_ENV
# when it is set.
#
#   powershell -NoProfile -File tool\windows\signing_setup.ps1 -Dir <folder>
#       -Endpoint https://<region>.codesigning.azure.net -Account <name>
#       -CertificateProfile <name> [-CorrelationId <text>]
#
# SignTool from Microsoft.Windows.SDK.BuildTools rather than the machine's own
# SDK, and the Artifact Signing client ("dlib") from its NuGet package rather
# than its installer, which needs administrator rights and fetches "the
# latest" SDK and .NET as it runs: the pair the release signs with is the pair
# pinned here. Its upstream Major roll-forward policy selects private .NET 10.
#
# ASCII only: PowerShell 5.1 reads a BOM-less script as ANSI.
param(
  [Parameter(Mandatory = $true)] [string]$Dir,
  [Parameter(Mandatory = $true)] [string]$Endpoint,
  [Parameter(Mandatory = $true)] [string]$Account,
  [Parameter(Mandatory = $true)] [string]$CertificateProfile,
  [string]$CorrelationId = ''
)
$ErrorActionPreference = 'Stop'
# PowerShell 5.1 redraws a progress bar as Invoke-WebRequest reads, which
# made the larger package take 18.9 s rather than 2.2 s (measured).
$ProgressPreference = 'SilentlyContinue'

function Fail([string]$why) { Write-Error "signing_setup: $why"; exit 1 }

# Each package: its id, version and SHA-256 (the .nupkg, as nuget.org serves
# it; its SHA-512 there agrees), and the file wanted from it.
$packages = @(
  @{ Id = 'microsoft.windows.sdk.buildtools'; Version = '10.0.26100.4188'
     Sha256 = '180deb372659029864c10a0c04787833234d64aacd1d2c0661d2c00295d8e022'
     File = 'bin\10.0.26100.0\x64\signtool.exe'; Name = 'SIGNTOOL' },
  @{ Id = 'microsoft.artifactsigning.client'; Version = '1.0.128'
     Sha256 = '74bd7d27e6ce1051409c38d9b46bc8df0400ecd643d51ffbf2ac00869061e40b'
     File = 'bin\x64\Azure.CodeSigning.Dlib.dll'; Name = 'SIGNING_DLIB' }
)

if ($Endpoint -notmatch '^https://[a-z0-9]+\.codesigning\.azure\.net/?$') {
  Fail 'the endpoint is not an Artifact Signing endpoint (https://<region>.codesigning.azure.net)'
}
if (-not $Account.Trim() -or -not $CertificateProfile.Trim()) { Fail 'the account and the certificate profile are required' }

# PATH does not control IJW's native host resolution. Both roots must select
# the fresh job-owned install, containing only serviced .NET 10.
& (Join-Path $PSScriptRoot 'check_signing_runtime.ps1') -Root $env:DOTNET_ROOT

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
# .NET (the unzip, the metadata's write) resolves a relative path against the
# process's directory, not PowerShell's location: a full one from here on.
$Dir = (Resolve-Path $Dir).Path
$found = @{}
foreach ($p in $packages) {
  $nupkg = Join-Path $Dir ('{0}.{1}.nupkg' -f $p.Id, $p.Version)
  $url = 'https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg' -f $p.Id, $p.Version
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $nupkg
  $hash = (Get-FileHash $nupkg -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hash -cne $p.Sha256) { Fail ("{0} {1} has SHA-256 {2}, not the pinned {3}" -f $p.Id, $p.Version, $hash, $p.Sha256) }
  $unpacked = Join-Path $Dir ('{0}.{1}' -f $p.Id, $p.Version)
  if (Test-Path $unpacked) { Remove-Item -Recurse -Force $unpacked }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $unpacked)
  $path = Join-Path $unpacked $p.File
  if (-not (Test-Path $path)) { Fail "no $($p.File) in $($p.Id) $($p.Version)" }
  $found[$p.Name] = $path
  '{0} {1}: {2} ({3})' -f $p.Id, $p.Version, $path, (Get-Item $path).VersionInfo.FileVersion
}

# The client signs with the first credential that answers; every one but the
# Azure CLI's (which azure/login has signed in) is excluded, so a failure has
# one cause.
$metadata = [ordered]@{
  Endpoint = $Endpoint.TrimEnd('/')
  CodeSigningAccountName = $Account
  CertificateProfileName = $CertificateProfile
  ExcludeCredentials = @('EnvironmentCredential', 'WorkloadIdentityCredential',
    'ManagedIdentityCredential', 'SharedTokenCacheCredential', 'VisualStudioCredential',
    'VisualStudioCodeCredential', 'AzurePowerShellCredential', 'AzureDeveloperCliCredential',
    'InteractiveBrowserCredential')
}
if ($CorrelationId) { $metadata['CorrelationId'] = $CorrelationId }
$metadataPath = Join-Path $Dir 'metadata.json'
[IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
$found['SIGNING_METADATA'] = $metadataPath
'metadata: {0}' -f $metadataPath

if ($env:GITHUB_ENV) {
  foreach ($name in 'SIGNTOOL', 'SIGNING_DLIB', 'SIGNING_METADATA') {
    Add-Content -Path $env:GITHUB_ENV -Value ('{0}={1}' -f $name, $found[$name]) -Encoding ASCII
  }
}
