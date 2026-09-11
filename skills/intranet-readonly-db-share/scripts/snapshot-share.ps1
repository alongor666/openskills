# snapshot-share.ps1 - Mirror exported DB snapshots into a READ-ONLY SMB share (Windows).
# Model: keep original DBs and code private; export snapshots into a STAGING dir;
# this script mirrors staging into the SHARED dir and creates the SMB share READ-ONLY.
#
# Usage (dry-run prints the plan; add -Apply to execute, admin needed for the share):
#   pwsh -File snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader
#   pwsh -File snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader -Apply
#
# -GrantAccount: domain user/group (e.g. DOMAIN\dept-group) on domain PCs; on non-domain
# PCs create a local account first:
#   New-LocalUser -Name dbreader -Password (Read-Host -AsSecureString 'pwd') -AccountNeverExpires
#
# Rollback: Remove-SmbShare -Name DbShare -Force
param(
  [Parameter(Mandatory=$true)][string]$StageDir,
  [Parameter(Mandatory=$true)][string]$ShareDir,
  [string]$ShareName = "DbShare",
  [string]$GrantAccount = "",
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'

Write-Host "=== PLAN ==="
Write-Host "Mirror : robocopy $StageDir -> $ShareDir (/MIR)"
if ($GrantAccount) {
  Write-Host "Share  : SMB '$ShareName' READ-ONLY for '$GrantAccount' (NTFS RX + SMB ReadAccess)"
} else {
  Write-Host "Share  : mirror only (no share/ACL change - no -GrantAccount given)"
}
Write-Host "=== ROLLBACK ==="
Write-Host "Remove-SmbShare -Name $ShareName -Force"

if (-not (Test-Path $StageDir)) { Write-Host "ERROR: StageDir not found: $StageDir"; exit 1 }
if (-not $Apply) { Write-Host "DRY-RUN only. Re-run with -Apply to mirror and create the share."; exit 0 }

if (-not (Test-Path $ShareDir)) { New-Item -ItemType Directory -Path $ShareDir | Out-Null }

# 1) Mirror staging -> shared (robocopy exit codes 0-7 mean success)
robocopy $StageDir $ShareDir /MIR /R:2 /W:5 /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host "ERROR: robocopy failed, exit code $LASTEXITCODE"; exit 1 }
Write-Host "[OK] Mirror done (robocopy code $LASTEXITCODE)."

# 2) Create SMB share as READ-ONLY (idempotent)
$existing = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if (-not $existing) {
  if ($GrantAccount) {
    New-SmbShare -Name $ShareName -Path $ShareDir -ReadAccess $GrantAccount | Out-Null
  } else {
    New-SmbShare -Name $ShareName -Path $ShareDir | Out-Null
  }
  Write-Host "[OK] SMB share '$ShareName' created."
} elseif ($GrantAccount) {
  Grant-SmbShareAccess -Name $ShareName -AccountName $GrantAccount -AccessRights Read -Force | Out-Null
  Write-Host "[OK] Share exists; granted READ to '$GrantAccount'."
}

Write-Host "DONE. Colleagues can now open: \\<server-ip>\$ShareName"
