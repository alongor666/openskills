# probe-env.ps1 - READ-ONLY environment probe BEFORE opening a readonly DB share (Windows).
# Zero side effects: only reads system state. Run this FIRST, adapt parameters to what it
# finds, and ask the user only what a probe cannot answer (channel choice, freshness,
# account model, sensitivity/approval).
#
# Usage: pwsh -File probe-env.ps1
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "== OS =="
$os = Get-CimInstance Win32_OperatingSystem
if ($os) { Write-Host ("[INFO] " + $os.Caption) } else { Write-Host "[WARN] OS caption unavailable" }

Write-Host "== Administrator check =="
net session *> $null
if ($LASTEXITCODE -eq 0) { Write-Host "[OK]   running as administrator" }
else { Write-Host "[WARN] NOT administrator - '-Apply' steps will fail; plan the no-admin fallback (IT ticket / existing share / channel B)" }

Write-Host "== Common DB services =="
$svc = Get-Service | Where-Object { $_.Name -match 'MSSQL|SQLServer|MySQL|Postgres|Mongo|Oracle' }
if ($svc) { $svc | ForEach-Object { Write-Host ("[INFO] service: {0} ({1})" -f $_.Name, $_.Status) } }
else { Write-Host "[INFO] no common server-type DB service - check file-based DBs (.db/.duckdb/.accdb/.xlsx)" }

Write-Host "== Listening DB ports =="
foreach ($p in 1433, 3306, 5432) {
  $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
  if ($c) { Write-Host "[INFO] port $p listening (likely server-type DB)" }
}

Write-Host "== Network profile (Public profile blocks SMB) =="
Get-NetConnectionProfile | ForEach-Object {
  Write-Host ("[INFO] {0}: {1}" -f $_.InterfaceAlias, $_.NetworkCategory)
  if ($_.NetworkCategory -eq 'Public') { Write-Host "[WARN] Public profile detected - SMB inbound is blocked; switching category affects machine policy, ASK the user/IT first" }
}

Write-Host "== Fixed drives free space (pick the largest for DbStage/DbShare) =="
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  if ($_.Free -gt 0) { Write-Host ("[INFO] {0}: free {1} GB" -f $_.Name, [math]::Round($_.Free / 1GB, 1)) }
}

Write-Host "== Existing SMB shares (name collision check for DbShare) =="
$shares = Get-SmbShare
if ($shares) { $shares | ForEach-Object { Write-Host ("[INFO] share: {0} -> {1}" -f $_.Name, $_.Path) } }
else { Write-Host "[INFO] no custom shares" }

Write-Host "== Export/scheduler tools in PATH =="
foreach ($t in 'sqlite3', 'mysqldump', 'pg_dump', 'sqlcmd', 'robocopy', 'schtasks', 'pwsh') {
  $c = Get-Command $t -ErrorAction SilentlyContinue
  if ($c) { Write-Host "[OK]   $t" } else { Write-Host "[WARN] $t not in PATH - pick another export method or install it" }
}

Write-Host "RESULT: probe complete (read-only, nothing was changed)"
