[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Source', 'Full')]
    [string]$Scope = 'Source',
    [string]$Allowlist = (Join-Path $PSScriptRoot 'brand-allowlist.json')
)

$ErrorActionPreference = 'Stop'
$normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
$excludedSegments = @(
    '.git', '.vscode', '.agents', '.tmp', 'node_modules', '.next', 'dist', 'vendor', 'tmp', 'log',
    'storage', 'coverage', 'playwright-report', 'test-results'
)
$binaryExtensions = @(
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.woff', '.woff2',
    '.ttf', '.eot', '.pdf', '.zip', '.gz', '.gem', '.map'
)
$audits = @(
    @{ Id = 'bad_case';       Token = 'PALLASTRADE_[a-z]'; Regex = 'PALLASTRADE_[a-z]' },
    @{ Id = 'title_case';     Token = 'Pallastrade';       Regex = '\bPallastrade\b' },
    @{ Id = 'double_prefix';  Token = 'pallastrade_pallastrade_'; Regex = 'pallastrade_pallastrade_' },
    @{ Id = 'mixed_prefix';   Token = 'spree';             Regex = 'spree_pallastrade_' },
    @{ Id = 'spree_constant'; Token = 'Spree';             Regex = 'Spree::' },
    @{ Id = 'spree_word';     Token = 'Spree';             Regex = '\bSpree\b' },
    @{ Id = 'spree_prefix';   Token = 'spree';             Regex = 'spree_' },
    @{ Id = 'spree_env';      Token = 'SPREE';             Regex = 'SPREE_' },
    @{ Id = 'spree_bare';     Token = 'spree';             Regex = '\bspree\b' },
    @{ Id = 'spree_upper';    Token = 'SPREE';             Regex = '\bSPREE\b' },
    @{ Id = 'npm_scope';      Token = '@spree/';           Regex = '@spree/' },
    @{ Id = 'legacy_header';  Token = 'X-Spree';           Regex = 'X-Spree' },
    @{ Id = 'spree_path';     Token = 'spree';             Regex = '/spree' }
)

function Get-RelativePath {
    param([string]$Path)
    $absolutePath = [System.IO.Path]::GetFullPath($Path)
    return $absolutePath.Substring($normalizedRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
}

function Convert-WildcardToRegex {
    param([string]$Wildcard)
    $normalized = $Wildcard.Replace('\', '/')
    $optionalLeadingDirectories = $normalized.StartsWith('**/')
    if ($optionalLeadingDirectories) { $normalized = $normalized.Substring(3) }
    $escaped = [regex]::Escape($normalized)
    $escaped = $escaped.Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]')
    $prefix = if ($optionalLeadingDirectories) { '(?:.*/)?' } else { '' }
    return '^' + $prefix + $escaped + '$'
}

$allowRules = @()
if (Test-Path -LiteralPath $Allowlist) {
    $config = Get-Content -LiteralPath $Allowlist -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($rule in $config.rules) {
        $allowRules += [pscustomobject]@{
            PathRegex = Convert-WildcardToRegex $rule.path
            Patterns = @($rule.patterns)
            Category = $rule.category
            Reason = $rule.reason
        }
    }
}

function Get-AllowRule {
    param([string]$RelativePath, [string]$Token)
    foreach ($rule in $allowRules) {
        if ($RelativePath -match $rule.PathRegex -and
            (($rule.Patterns -contains '*') -or ($rule.Patterns -contains $Token))) {
            return $rule
        }
    }
    return $null
}

function Test-ScannableFile {
    param([System.IO.FileInfo]$File)
    $relative = Get-RelativePath $File.FullName
    $segments = $relative -split '/'
    if ($segments | Where-Object { $excludedSegments -contains $_ }) { return $false }
    if ($binaryExtensions -contains $File.Extension.ToLowerInvariant()) { return $false }
    if ($relative -match '(^|/)scripts/ci/brand-audit[^/]*$' -or
        $relative -match '(^|/)scripts/ci/brand-allowlist\.json$' -or
        $relative -match '(^|/)scripts/ci/brand-remediate\.ps1$') { return $false }
    return $true
}

$scanRoots = @()
if ($Scope -eq 'Source') {
    foreach ($candidate in @('backend', 'storefront', 'platform', 'ai')) {
        $path = Join-Path $Root $candidate
        if (Test-Path -LiteralPath $path) { $scanRoots += $path }
    }
}
if ($scanRoots.Count -eq 0) { $scanRoots = @($Root) }

$files = foreach ($scanRoot in $scanRoots) {
    Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { Test-ScannableFile $_ }
}
$files = @($files | Sort-Object FullName -Unique)

$violationTotal = 0
$allowedTotal = 0
Write-Host "=== PallasTrade Brand Audit ($Scope) ===" -ForegroundColor Cyan
Write-Host "Root: $normalizedRoot"
Write-Host "Files: $($files.Count)"

$bomViolations = 0
$bomSamples = @()
foreach ($file in $files) {
    $stream = [System.IO.File]::OpenRead($file.FullName)
    try {
        if ($stream.Length -ge 3 -and
            $stream.ReadByte() -eq 0xEF -and
            $stream.ReadByte() -eq 0xBB -and
            $stream.ReadByte() -eq 0xBF) {
            $bomViolations++
            if ($bomSamples.Count -lt 6) { $bomSamples += (Get-RelativePath $file.FullName) }
        }
    } finally {
        $stream.Dispose()
    }
}
$violationTotal += $bomViolations
$bomColor = if ($bomViolations -eq 0) { 'Green' } else { 'Red' }
Write-Host ("{0,-18} violations={1,-6} allowed=0" -f 'utf8_bom', $bomViolations) -ForegroundColor $bomColor
$bomSamples | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

foreach ($audit in $audits) {
    $violations = 0
    $allowed = 0
    $samples = @()
    foreach ($file in $files) {
        $relative = Get-RelativePath $file.FullName
        $hits = Select-String -LiteralPath $file.FullName -Pattern $audit.Regex -AllMatches -CaseSensitive -ErrorAction SilentlyContinue
        foreach ($hit in @($hits)) {
            foreach ($match in @($hit.Matches)) {
                $rule = Get-AllowRule $relative $audit.Token
                if ($null -ne $rule) {
                    $allowed++
                } else {
                    $violations++
                    if ($samples.Count -lt 6) { $samples += "${relative}:$($hit.LineNumber)" }
                }
            }
        }
    }
    $violationTotal += $violations
    $allowedTotal += $allowed
    $color = if ($violations -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("{0,-18} violations={1,-6} allowed={2}" -f $audit.Id, $violations, $allowed) -ForegroundColor $color
    $samples | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

Write-Host "Allowed matches: $allowedTotal" -ForegroundColor DarkYellow
Write-Host "Violations: $violationTotal" -ForegroundColor $(if ($violationTotal -eq 0) { 'Green' } else { 'Red' })
exit $(if ($violationTotal -eq 0) { 0 } else { 1 })
