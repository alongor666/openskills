# verify-access.ps1 - Server-side health check for the READ-ONLY DB share (Windows).
#
# Usage:
#   pwsh -File verify-access.ps1 -ShareName DbShare
#
# Exit code: 0 = OK (warnings allowed); 1 = at least one FAIL.
param(
  [string]$ShareName = "DbShare"
)
$fail = 0

# 1) SMB share exists and its dir is non-empty
$share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if ($share) {
  Write-Host "[OK]   SMB share '$ShareName' -> $($share.Path)"
  $files = @(Get-ChildItem -Path $share.Path -File -ErrorAction SilentlyContinue)
  if ($files.Count -gt 0) { Write-Host "[OK]   Share dir holds $($files.Count) file(s)." }
  else { Write-Host "[WARN] Share dir is EMPTY - run snapshot-share.ps1 -Apply first." }
} else {
  Write-Host "[FAIL] SMB share '$ShareName' not found - run snapshot-share.ps1 -Apply."
  $fail = 1
}

# 2) SMB service listening on 445
$l = Get-NetTCPConnection -LocalPort 445 -State Listen -ErrorAction SilentlyContinue
if ($l) { Write-Host "[OK]   SMB listening on port 445." }
else { Write-Host "[FAIL] Port 445 NOT listening - Server service (LanmanServer) may be stopped."; $fail = 1 }

# 3) Addresses to hand to colleagues
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254*' } |
  ForEach-Object { Write-Host ("[INFO] Colleague path: \\{0}\{1}  ({2})" -f $_.IPAddress, $ShareName, $_.InterfaceAlias) }

Write-Host "[INFO] Colleague-side check: Test-NetConnection <server-ip> -Port 445 ; then dir \\<server-ip>\$ShareName"
Write-Host "[INFO] Reminders: readonly share only; mask sensitive fields if required; remove the share when done."

if ($fail -ne 0) { Write-Host "RESULT: FAIL"; exit 1 }
Write-Host "RESULT: OK"
exit 0
