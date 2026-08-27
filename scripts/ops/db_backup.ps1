# PallasTrade 数据库备份脚本（本地 Windows dev）
#   - 用法: .\scripts\ops\db_backup.ps1 [-Env dev] [-Container pallastrade-postgres-1] [-Db pallastrade_development]
#   - 依赖: Docker Desktop 运行中（backend/docker-compose.dev.yml，项目名 pallastrade，postgres trust auth）
param(
    [string]$Env = "dev",
    [string]$Container = "pallastrade-postgres-1",
    [string]$Db = "pallastrade_development",
    [int]$Keep = 7
)
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BackupDir = Join-Path $RepoRoot "backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$Ts = Get-Date -Format "yyyyMMdd-HHmmss"
$Out = Join-Path $BackupDir "$Env-$Db-$Ts.sql.gz"

Write-Host "=== Backup $Env/$Db (container $Container) -> $Out ==="
# Windows has no gzip on PATH — do the dump+gzip inside the postgres container
# (postgres:18-alpine ships gzip), then docker cp the bytes out (binary-safe).
$Tmp = "/tmp/pallastrade-backup-$([guid]::NewGuid().ToString('N')).sql.gz"
docker exec $Container sh -c "pg_dump -U postgres -d $Db --no-owner --no-acl | gzip > $Tmp"
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed (exit $LASTEXITCODE). Is Docker running and container '$Container' up?" }
docker cp "$Container`:$Tmp" $Out
if ($LASTEXITCODE -ne 0) { throw "docker cp failed" }
docker exec $Container rm -f $Tmp

Write-Host "Done: $Out ($((Get-Item $Out).Length) bytes)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Keep last N
$Old = Get-ChildItem $BackupDir -Filter "$Env-$Db-*.sql.gz" | Sort-Object Name -Descending | Select-Object -Skip $Keep
if ($Old) { $Old | Remove-Item -Force; Write-Host "Cleaned $($Old.Count) old backup(s) (keep $Keep)" }
