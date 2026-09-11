# setup-firewall.ps1 - Inbound firewall rule for DIRECT db access on a company LAN (Windows).
# For the PRIMARY snapshot-share path you usually do NOT need this (SMB 445 is covered by
# File and Printer Sharing rules). Use it only for the direct-connect path:
#   SQL Server 1433 / MySQL 3306 / PostgreSQL 5432 - scope to the OFFICE subnet only.
#
# Usage:
#   pwsh -File setup-firewall.ps1 -Port 1433 -ScopeSubnet 192.168.0.0/16          (dry-run)
#   pwsh -File setup-firewall.ps1 -Port 1433 -ScopeSubnet 192.168.0.0/16 -Apply   (admin)
#
# Rollback:
#   Remove-NetFirewallRule -DisplayName IntranetDbReadonly-<port>
param(
  [int]$Port = 1433,
  [string]$ScopeSubnet = "",
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if (-not $ScopeSubnet) {
  Write-Host "ERROR: -ScopeSubnet is required (office subnet, e.g. 192.168.0.0/16)."
  exit 1
}
$RuleName = "IntranetDbReadonly-$Port"

Write-Host "=== PLAN ==="
Write-Host "Rule name : $RuleName"
Write-Host "Action    : Inbound TCP/$Port -Action Allow"
Write-Host "Scope     : RemoteAddress $ScopeSubnet"
Write-Host "=== ROLLBACK ==="
Write-Host "Remove-NetFirewallRule -DisplayName $RuleName"

if (-not $Apply) {
  Write-Host "DRY-RUN only. Re-run with -Apply to create the rule."
  exit 0
}

$rule = @{ DisplayName = $RuleName; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'TCP'; LocalPort = $Port; RemoteAddress = $ScopeSubnet }
New-NetFirewallRule @rule | Out-Null
Write-Host "DONE. Verify: Get-NetFirewallRule -DisplayName $RuleName"
