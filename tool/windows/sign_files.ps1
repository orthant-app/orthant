# Authenticode-signs Orthant's own executables and libraries: every .exe and
# .dll under -Bundle that carries no signature, and every -File named. A file
# its publisher already signed (the Visual C++ runtime, Microsoft's) is kept
# as it is; one whose signature is anything but valid or absent stops the run.
# Prints what it signed and kept, by name; SignTool's own output, which can
# name the signer, goes only to -Log.
#
#   & tool\windows\sign_files.ps1 -SignTool <signtool.exe> -SignArgs @('/q', '/fd', 'SHA256', ...)
#       [-Bundle <folder>] [-File <path>, ...] -Log <file>
#   & tool\windows\sign_files.ps1 -SignTool <signtool.exe> -SignArgs @(...) -Log <file> -InnoCommand
#
# -InnoCommand signs nothing: it prints the same signing as the command line
# Inno Setup's SignTool directive takes (make_installer.ps1's -SignTool), with
# Inno's $q for every quote and $f for the file, so the uninstaller and the
# installer are signed exactly as the app's files are. Inno runs that command
# with no shell, so it holds no quote PowerShell 5.1 would have to pass on.
#
# Called with &, from PowerShell: -SignArgs is an array, which powershell -File
# would pass as one string. -SignArgs is everything between "sign" and the
# file. Any exit code but 0 fails, 2 included: SignTool's "completed with
# warnings" is how a timestamp that failed is reported, and a signature
# without one expires with its three-day certificate.
#
# ASCII only: PowerShell 5.1 reads a BOM-less script as ANSI.
param(
  [Parameter(Mandatory = $true)] [string]$SignTool,
  [Parameter(Mandatory = $true)] [string[]]$SignArgs,
  [string]$Bundle = '',
  [string[]]$File = @(),
  [Parameter(Mandatory = $true)] [string]$Log,
  [switch]$InnoCommand
)
$ErrorActionPreference = 'Stop'

function Fail([string]$why) { Write-Error "sign_files: $why"; exit 1 }

if (-not (Test-Path $SignTool)) { Fail "no SignTool at $SignTool" }
if ($InnoCommand) {
  $quoted = foreach ($a in @($SignTool, 'sign') + $SignArgs) {
    if ($a -match '"') { Fail "a signing argument holds a quote: $a" }
    if ($a -match '\s') { '$q' + $a + '$q' } else { $a }
  }
  (@($quoted) + '$f') -join ' '
  exit 0
}
$targets = @()
if ($Bundle) {
  if (-not (Test-Path $Bundle)) { Fail "no bundle at $Bundle" }
  $root = (Resolve-Path $Bundle).Path
  foreach ($item in @(Get-ChildItem -Path $root -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Sort-Object FullName)) {
    $name = $item.FullName.Substring($root.Length + 1)
    $status = (Get-AuthenticodeSignature -FilePath $item.FullName).Status
    if ($status -eq 'NotSigned') { $targets += $item.FullName }
    elseif ($status -eq 'Valid') { "kept $name (signed by its publisher)" }
    else { Fail "$name is ${status}: neither unsigned nor validly signed" }
  }
}
foreach ($f in $File) {
  if (-not (Test-Path $f)) { Fail "no file at $f" }
  $targets += (Resolve-Path $f).Path
}
if ($targets.Count -eq 0) { Fail 'nothing to sign' }

# Appended to, never emptied: the signing and the check share one log.
if (-not (Test-Path $Log)) { New-Item -ItemType File -Force -Path $Log | Out-Null }
foreach ($target in $targets) {
  # A native tool's stderr becomes an error in PowerShell 5.1 when redirected:
  # SignTool's exit code is the verdict.
  $ErrorActionPreference = 'Continue'
  $said = & $SignTool sign @SignArgs $target 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  Add-Content -Path $Log -Value ("[sign {0}] exit {1}`r`n{2}" -f $target, $code, $said)
  if ($code -ne 0) { Fail ("SignTool exited {0} signing {1}; its output is in the diagnostics" -f $code, (Split-Path $target -Leaf)) }
  'signed {0}' -f (Split-Path $target -Leaf)
}
