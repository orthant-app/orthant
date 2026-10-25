# Checks a Release bundle is the one a release means to ship, before anything
# signs it: its compiled Dart (data\app.so) holds the update feed this
# release's channel checks, the project's update key (macOS's SUPublicEDKey,
# which every release's downloads are signed for) and the release's own name,
# and none of the feeds it must not check. A build made without the release's
# defines, or with a test's (a loopback feed, a throwaway key), fails here.
#
#   powershell -NoProfile -File tool\windows\check_release_build.ps1 -ReleaseName 1.1.0
#       -Feed https://updates.orthant.app/appcast-win.xml [-Bundle build\windows\x64\runner\Release]
#
# Run from the repository's root. The strings are read as the bytes the
# snapshot stores them in: ASCII text is one byte a character there.
#
# ASCII only: PowerShell 5.1 reads a BOM-less script as ANSI.
param(
  [Parameter(Mandatory = $true)] [string]$ReleaseName,
  [Parameter(Mandatory = $true)] [string]$Feed,
  [string]$Bundle = 'build\windows\x64\runner\Release'
)
$ErrorActionPreference = 'Stop'

function Fail([string]$why) { Write-Error "check_release_build: $why"; exit 1 }

$feeds = @('https://updates.orthant.app/appcast-win.xml', 'https://updates.orthant.app/appcast-win-beta.xml')
if ($feeds -cnotcontains $Feed) { Fail "$Feed is not one of the release feeds" }
$plist = Get-Content -Raw 'macos\Runner\Info.plist'
$m = [regex]::Match($plist, '<key>SUPublicEDKey</key>\s*<string>([A-Za-z0-9+/=]+)</string>')
if (-not $m.Success) { Fail 'no SUPublicEDKey in macos\Runner\Info.plist' }
$key = $m.Groups[1].Value

$so = Join-Path $Bundle 'data\app.so'
if (-not (Test-Path $so)) { Fail "no $so`: build the release first" }
# .NET resolves a relative path against the process's directory, not
# PowerShell's location: hand it a full one.
$so = (Resolve-Path $so).Path
# Latin-1 maps every byte to one character, so an ordinal search of the text
# is a search of the bytes.
$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($so))
foreach ($need in @($Feed, $key)) {
  if (-not $text.Contains($need)) { Fail "app.so does not hold '$need': not built with this release's defines" }
}
# The name must be a whole string the snapshot holds, not the start of a longer
# one (1.0.3 in 1.0.30, 1.0.3-beta.1 in 1.0.3-beta.10). The snapshot stores a
# string's characters straight after its length, whose last byte is zero, and
# follows them with zeros or the next object's header (measured): a whole name
# has a zero before it and no version character after it.
$whole = '(?<=\x00)' + [regex]::Escape($ReleaseName) + '(?![0-9A-Za-z.+-])'
if (-not [regex]::IsMatch($text, $whole)) { Fail "app.so does not hold '$ReleaseName' as a whole name: not built with this release's defines" }
foreach ($other in @($feeds | Where-Object { $_ -cne $Feed }) + @('http://127.0.0.1')) {
  if ($text.Contains($other)) { Fail "app.so holds '$other', which this release must not check" }
}
'app.so: feed {0}, the project key, release name {1}' -f $Feed, $ReleaseName
