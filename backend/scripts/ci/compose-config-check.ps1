[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [string]$Label
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "$Label expected '$Expected', got '$Actual'."
    }
}

$managedEnvironment = @(
    'PALLASTRADE_PORT',
    'PALLASTRADE_MEILISEARCH_PORT',
    'PORT',
    'RAILS_HOST',
    'SECRET_KEY_BASE'
)
$originalEnvironment = @{}

foreach ($name in $managedEnvironment) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('PALLASTRADE_PORT', '43123', 'Process')
    [Environment]::SetEnvironmentVariable('PALLASTRADE_MEILISEARCH_PORT', '47700', 'Process')
    [Environment]::SetEnvironmentVariable('PORT', '49999', 'Process')
    [Environment]::SetEnvironmentVariable('RAILS_HOST', $null, 'Process')
    [Environment]::SetEnvironmentVariable('SECRET_KEY_BASE', 'compose-config-contract', 'Process')

    $composeFile = Join-Path $Root 'docker-compose.yml'
    $stderrFile = [IO.Path]::GetTempFileName()

    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $configOutput = & docker compose --project-directory $Root -f $composeFile config --no-env-resolution --format json 2> $stderrFile
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($exitCode -ne 0) {
            $details = (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue).Trim()
            throw "docker compose config failed with exit code $exitCode. $details"
        }
    }
    finally {
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    $config = ($configOutput -join "`n") | ConvertFrom-Json
    $webPort = @($config.services.web.ports) |
        Where-Object { [int]$_.target -eq 3000 } |
        Select-Object -First 1
    $meilisearchPort = @($config.services.meilisearch.ports) |
        Where-Object { [int]$_.target -eq 7700 } |
        Select-Object -First 1

    if ($null -eq $webPort) {
        throw 'Web port mapping targeting container port 3000 is missing.'
    }
    if ($null -eq $meilisearchPort) {
        throw 'Meilisearch port mapping targeting container port 7700 is missing.'
    }

    Assert-Equal $webPort.published '43123' 'Published web port'
    Assert-Equal $meilisearchPort.published '47700' 'Published Meilisearch port'
    Assert-Equal $config.services.web.environment.PORT '3000' 'Web container PORT'
    Assert-Equal $config.services.worker.environment.PORT '3000' 'Worker container PORT'
    Assert-Equal $config.services.web.environment.RAILS_HOST 'localhost:43123' 'Generated RAILS_HOST'

    Write-Host 'Compose environment contract passed: web=43123:3000, meilisearch=47700:7700, container PORT=3000.'
}
finally {
    foreach ($name in $managedEnvironment) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
}
