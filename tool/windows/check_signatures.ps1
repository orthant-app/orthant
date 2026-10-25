# Checks Authenticode signatures: every file named, and every .exe and .dll
# under every folder named, must be Valid (a chain Windows trusts, the file
# unchanged since it was signed) and timestamped (Artifact Signing's
# certificates last three days, and a signature with no timestamp dies with
# its certificate). Prints each file's verdict by name; who signed it, and
# who issued that, go only to -Log.
#
#   powershell -NoProfile -File tool\windows\check_signatures.ps1 -Path <file or folder> -Log <file>
#
# ASCII only: PowerShell 5.1 reads a BOM-less script as ANSI.
param(
  [Parameter(Mandatory = $true)] [string[]]$Path,
  [Parameter(Mandatory = $true)] [string]$Log
)
$ErrorActionPreference = 'Stop'

$files = @()
foreach ($p in $Path) {
  if (-not (Test-Path $p)) { Write-Error "check_signatures: nothing at $p"; exit 1 }
  if ((Get-Item $p).PSIsContainer) {
    $files += @(Get-ChildItem -Path $p -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Sort-Object FullName | ForEach-Object { $_.FullName })
  } else {
    $files += (Resolve-Path $p).Path
  }
}
if ($files.Count -eq 0) { Write-Error 'check_signatures: no files to check'; exit 1 }

# Appended to, never emptied: the signing and the check share one log.
if (-not (Test-Path $Log)) { New-Item -ItemType File -Force -Path $Log | Out-Null }
$bad = 0
foreach ($f in $files) {
  $s = Get-AuthenticodeSignature -FilePath $f
  $stamped = $null -ne $s.TimeStamperCertificate
  Add-Content -Path $Log -Value ("[{0}] {1}; signer {2}; issuer {3}; timestamp {4}" -f $f, $s.Status,
    $(if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { 'none' }),
    $(if ($s.SignerCertificate) { $s.SignerCertificate.Issuer } else { 'none' }),
    $(if ($stamped) { $s.TimeStamperCertificate.Subject } else { 'none' }))
  $name = Split-Path $f -Leaf
  if ($s.Status -eq 'Valid' -and $stamped) {
    '{0}: valid, timestamped' -f $name
  } else {
    $bad++
    '{0}: NOT ACCEPTED ({1}{2})' -f $name, $s.Status, $(if ($stamped) { '' } else { ', no timestamp' })
  }
}
if ($bad) { Write-Error "check_signatures: $bad of $($files.Count) not accepted"; exit 1 }
'{0} signature(s) valid and timestamped' -f $files.Count
