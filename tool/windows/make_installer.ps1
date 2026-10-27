# Compiles Orthant's Windows installer from a release build's bundle, with
# Inno Setup 6 (ISCC.exe), and prints the installer's path, size and SHA-256.
#
#   powershell -NoProfile -File tool\windows\make_installer.ps1 -ReleaseName 1.1.0
#       [-Bundle build\windows\x64\runner\Release] [-OutDir build\dist]
#       [-SignTool '<command with $f for the file>']
#
# Run from the repository's root, after `flutter build windows --release`
# (a prerelease name needs `--dart-define=ORTHANT_RELEASE_NAME=<that name>`).
# The release name is the tag's own name (1.1.0, 1.1.0-beta.1); its base must
# be pubspec.yaml's version, and the bundle's executable must carry that
# version and build number, so an installer is never made from another
# build. -SignTool hands Inno a command it runs on the uninstaller and the
# installer it writes (Inno's own $f is the file).
#
# ASCII only: PowerShell 5.1 reads a BOM-less script as ANSI.
param(
  [Parameter(Mandatory = $true)] [string]$ReleaseName,
  [string]$Bundle = 'build\windows\x64\runner\Release',
  [string]$OutDir = 'build\dist',
  [string]$SignTool = ''
)
$ErrorActionPreference = 'Stop'

function Fail([string]$why) { Write-Error "make_installer: $why"; exit 1 }

$pubspec = Get-Content -Raw -Encoding UTF8 'pubspec.yaml'
$m = [regex]::Matches($pubspec, '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)\s*$')
if ($m.Count -ne 1) { Fail 'pubspec.yaml must hold exactly one version: X.Y.Z+N line' }
$version = $m[0].Groups[1].Value
$build = $m[0].Groups[2].Value

if ($ReleaseName -notmatch '^(\d+\.\d+\.\d+)(-[0-9A-Za-z.-]+)?$') { Fail "release name '$ReleaseName' is not a version" }
if ($Matches[1] -cne $version) { Fail "release name '$ReleaseName' is not pubspec.yaml's version $version" }
$prerelease = $Matches[2]

$exe = Join-Path $Bundle 'Orthant.exe'
if (-not (Test-Path $exe)) { Fail "no executable at ${exe}: build the release first" }
$info = (Get-Item $exe).VersionInfo
$exeVersion = '{0}.{1}.{2}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart
if ($exeVersion -cne $version -or [string]$info.FilePrivatePart -cne $build) {
  Fail ("the bundle's executable is {0} ({1}), not {2} ({3}): build this version first" -f $exeVersion, $info.FilePrivatePart, $version, $build)
}
# A prerelease name reaches the app only through ORTHANT_RELEASE_NAME: built
# without it the app calls itself by its three numbers while the installer and
# the feed say beta. A plain version needs nothing (the version resource's
# numbers are that name). The name is looked for in app.so as a whole name, so
# an app built as 1.1.0-beta.10 does not satisfy a requested 1.1.0-beta.1.
if ($prerelease) {
  $so = Join-Path $Bundle 'data\app.so'
  if (-not (Test-Path $so)) { Fail "no ${so}: build the release first" }
  # .NET resolves a relative path against the process's directory, which is
  # not PowerShell's location when this script is run in-process.
  $so = (Resolve-Path $so).Path
  $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($so))
  $whole = '(?<=\x00)' + [regex]::Escape($ReleaseName) + '(?![0-9A-Za-z.+-])'
  if (-not [regex]::IsMatch($text, $whole)) { Fail "app.so does not hold '$ReleaseName': build with --dart-define=ORTHANT_RELEASE_NAME=$ReleaseName" }
}
if (-not (Test-Path (Join-Path $Bundle 'WinSparkle.dll'))) { Fail "no WinSparkle.dll in ${Bundle}: the updater would not start" }
# The Visual C++ runtime the runner and its plugins link against (CMake puts
# it beside the executable): a per-user install cannot run Microsoft's runtime
# installer, so without these a machine that lacks the runtime cannot start
# the app.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  if (-not (Test-Path (Join-Path $Bundle $dll))) { Fail "no $dll in ${Bundle}: Orthant would not start where the Visual C++ runtime is not installed" }
}

# Inno Setup 6, the version GitHub's Windows runner image carries (where the
# release job finds it, in Program Files (x86)), or a per-user install.
$iscc = @($env:ISCC,
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')) |
  Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { Fail 'ISCC.exe not found: install Inno Setup 6, or set ISCC to its path' }
# ISCC.exe's own version resource reads 0.0.0.0 (measured, 6.7.1): its banner
# names the major version, and the installation's uninstaller beside it the
# exact one. The banner comes on stdout and the usage after it on stderr, and
# merged they arrive in either order (the usage first in 2 of 20 runs,
# measured), so the banner is looked for among every line.
$ErrorActionPreference = 'Continue'
$said = @(& $iscc '/?' 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
$ErrorActionPreference = 'Stop'
$banner = @($said | Where-Object { $_ -match '^Inno Setup \d+ ' })[0]
if ($banner -notmatch '^Inno Setup 6 ') { Fail "ISCC.exe at $iscc says '$(if ($banner) { $banner } else { $said[0] })', not Inno Setup 6" }
$uninstaller = Join-Path (Split-Path $iscc) 'unins000.exe'
$isccVersion = if (Test-Path $uninstaller) { ([string](Get-Item $uninstaller).VersionInfo.ProductVersion).Trim() } else { '6' }
# ChineseSimplified.isl (BOM-less UTF-8) targets Inno Setup 6.5.0 and later
# (windows/installer/orthant.iss), and an older Inno would garble its Chinese,
# so there is a floor. A version that cannot be read (the '6' above, or a
# ProductVersion of another shape) is not failed on.
$isccFloor = [version]'6.5.0'
$isccParsed = $null
if ([version]::TryParse($isccVersion, [ref]$isccParsed) -and $isccParsed -lt $isccFloor) {
  Fail "Inno Setup $isccVersion at $iscc is older than $isccFloor, which the installer's Chinese language files need: install Inno Setup $isccFloor or newer, or set ISCC to one"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$bundleFull = (Resolve-Path $Bundle).Path
$outFull = (Resolve-Path $OutDir).Path
$isccArgs = @('/Q', "/DAppVersion=$version", "/DAppBuild=$build", "/DReleaseName=$ReleaseName",
  "/DSourceDir=$bundleFull", "/O$outFull")
if ($SignTool) { $isccArgs += @("/SOrthantSign=$SignTool", '/DSignTool=OrthantSign') }
$isccArgs += 'windows\installer\orthant.iss'
# A native tool's stderr becomes an error in PowerShell 5.1 when its output is
# redirected (over SSH, in a CI log): ISCC's exit code is the verdict, so it
# runs with errors continuing.
$ErrorActionPreference = 'Continue'
& $iscc @isccArgs
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($code -ne 0) { Fail "ISCC.exe exited $code" }

$installer = Join-Path $outFull "Orthant-$ReleaseName-setup.exe"
if (-not (Test-Path $installer)) { Fail "ISCC.exe wrote no $installer" }
$item = Get-Item $installer
'{0} {1} bytes sha256 {2} (Inno Setup {3})' -f $item.FullName, $item.Length, (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant(), $isccVersion
