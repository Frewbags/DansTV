# Offline Compose interpolation regression. Never reads the real .local lab credentials.
# Uses the checked-in Compose YAML in an isolated disposable fixture.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$sourceCompose = Join-Path $PSScriptRoot 'lab\compose.yml'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('danstv-compose-' + [guid]::NewGuid().ToString('N'))
$fixtureCompose = Join-Path $fixtureRoot 'scripts\tiz0wn\lab\compose.yml'
$fixtureEnv = Join-Path $fixtureRoot '.local\tiz0wn-lab\lab.env'
$previousHostIP = [Environment]::GetEnvironmentVariable('LAB_HOST_IP', 'Process')

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI/Compose is required for the synthetic interpolation test.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureCompose) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureEnv) -Force | Out-Null
    Copy-Item -LiteralPath $sourceCompose -Destination $fixtureCompose
    # Deliberately conflicting values: the scoped process host must win,
    # while the service environment must retain a literal shell expression.
    @(
        'LAB_HOST_IP=192.0.2.33'
        'TVPROBE_USER=danstvprobe'
        'TVPROBE_PASSWORD=literal${IFS}$(never_run)'
    ) | Set-Content -LiteralPath $fixtureEnv -Encoding ASCII
    $env:LAB_HOST_IP = '192.0.2.44'
    $output = @(& docker compose -f $fixtureCompose config --format json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Compose config failed (output suppressed).' }
    # JSON must be clean: an interpolation warning on stderr is a test failure.
    try { $model = ($output -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { throw 'Compose emitted invalid JSON or interpolation warnings (output suppressed).' }
    $service = $model.services.'danstv-rdp'
    if ($service.environment.TVPROBE_PASSWORD -cne 'literal${IFS}$(never_run)') {
        throw 'Raw service password was interpolated or changed.'
    }
    if ($service.ports.Count -ne 1 -or $service.ports[0].host_ip -ne '192.0.2.44') {
        throw 'Compose did not use the temporary process LAB_HOST_IP for port binding.'
    }
    Write-Output 'Synthetic Compose interpolation passed: scoped host and literal raw service password.'
} finally {
    if ($null -eq $previousHostIP) {
        Remove-Item Env:LAB_HOST_IP -ErrorAction SilentlyContinue
    } else {
        $env:LAB_HOST_IP = $previousHostIP
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
