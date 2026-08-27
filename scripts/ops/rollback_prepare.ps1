# PallasTrade 回滚演练准备脚本（本地 Windows dev）
#   - 在实施任何带数据库迁移的升级前运行，记录可回滚依据：
#       1) backend/db/schema.rb 快照
#       2) 当前最新迁移版本（schema_migrations）
#       3) 触发数据库备份（调用 db_backup.ps1）
#   - 用法: .\scripts\ops\rollback_prepare.ps1 [-Env dev] [-Container pallastrade-postgres-1] [-Db pallastrade_development]
param(
    [string]$Env = "dev",
    [string]$Container = "pallastrade-postgres-1",
    [string]$Db = "pallastrade_development"
)
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SnapDir = Join-Path $RepoRoot "backups\schema"
$Log = Join-Path $SnapDir "migration-version.log"
New-Item -ItemType Directory -Force -Path $SnapDir | Out-Null

$Ts = Get-Date -Format "yyyyMMdd-HHmmss"
Write-Host "=== Rollback prepare ($Env) ==="

# 1) schema.rb snapshot
$Schema = Join-Path $RepoRoot "backend\db\schema.rb"
if (-not (Test-Path $Schema)) { throw "schema.rb not found: $Schema" }
Copy-Item $Schema (Join-Path $SnapDir "schema.rb.$Ts")
Write-Host "schema.rb snapshot: $SnapDir\schema.rb.$Ts"

# 2) current max migration version
$Version = (& docker exec $Container psql -U postgres -d $Db -t -A -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1" 2>$null) -replace '\s', ''
if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Warning "Cannot read migration version (container/db unreachable?). Manual: docker exec $Container psql -U postgres -d $Db -c 'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1'"
} else {
    Write-Host "Current max migration version: $Version"
    Add-Content $Log "$Ts $Env $Db $Version"
    Write-Host "  (appended to $Log)"
}

# 3) trigger db backup
Write-Host "--- Trigger db backup ---"
& (Join-Path $PSScriptRoot "db_backup.ps1") -Env $Env -Container $Container -Db $Db

Write-Host ""
Write-Host "=== Done. Rollback hints ==="
Write-Host "  Migration rollback: cd backend; bundle exec rails db:rollback STEP=N  (migrations must be reversible)"
Write-Host "  Code rollback:      git checkout <prev> then rebuild image (see deploy/README.md)"
