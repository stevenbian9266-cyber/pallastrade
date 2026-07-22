param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

& (Join-Path $PSScriptRoot 'brand-audit-core.ps1') -Root $Root -Scope Full
$invocationSucceeded = $?
$coreExitCode = $LASTEXITCODE
if (-not $invocationSucceeded) { exit 1 }
exit $coreExitCode
