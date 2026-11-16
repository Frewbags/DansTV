# Windows Q80T root-route experiment using a verified upstream release.
# - Prepare: download and verify hash, extract locally; no TV contact
# - Doctor: host tooling checks; no root attempt
# - Probe: run upstream archive-root probe, which DOES attempt temporary root
# Pinned upstream: https://github.com/chris-ritsen/samsung-tv-root/releases/tag/v0.0.13
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Prepare','Doctor','Probe')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$local = Join-Path $root '.local'
$preflightFile = Join-Path $local 'tiz0wn-preflight.json'
$configFile = Join-Path $local 'signing.json'
$deviceFile = Join-Path $local 'device.json'
$toolRoot = Join-Path $local 'samsung-tv-root-v0.0.13'
$base = 'https://github.com/chris-ritsen/samsung-tv-root/releases/download/v0.0.13/'
$zipName = 'samsung-tv-root-0.0.13-windows-x86_64.zip'
$archive = Join-Path $toolRoot $zipName
$shaFile = "$archive.sha256"
$unpacked = Join-Path $toolRoot 'unpacked'

function UpstreamExe {
    $candidate = Get-ChildItem -LiteralPath $unpacked -Filter 'samsung-tv-root.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $candidate) { throw 'The official ZIP did not contain samsung-tv-root.exe.' }
    return $candidate.FullName
}

function Prepare {
    if (-not (Test-Path -LiteralPath $toolRoot)) {
        New-Item -Path $toolRoot -ItemType Directory | Out-Null
    }
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        Invoke-WebRequest -Uri ($base + $zipName) -OutFile $archive
    }
    Invoke-WebRequest -Uri ($base + $zipName + '.sha256') -OutFile $shaFile
    $raw = Get-Content -LiteralPath $shaFile -Raw
    $hash = [regex]::Match($raw, '(?i)\b[0-9a-f]{64}\b')
    if (-not $hash.Success) { throw 'Official checksum file contains no SHA-256 digest.' }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actual -ne $hash.Value.ToUpperInvariant()) {
        Remove-Item -LiteralPath $archive -Force
        throw 'Downloaded upstream ZIP checksum mismatch. Archive discarded.'
    }
    if (-not (Test-Path -LiteralPath $unpacked)) {
        New-Item -Path $unpacked -ItemType Directory | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    }
    $exe = UpstreamExe
    Write-Output "Upstream samsung-tv-root v0.0.13 SHA-256 verified. Tool: $exe"
    Write-Output 'Only files under ignored .local were created; no TV contact.'
    return $exe
}

if ($Action -eq 'Prepare') {
    $null = Prepare
    return
}

if (-not (Test-Path -LiteralPath $preflightFile -PathType Leaf)) {
    throw 'Run .\scripts\tiz0wn\preflight.ps1 -Firmware T-NKMUABC-2743.0 first.'
}
$p = Get-Content -LiteralPath $preflightFile -Raw | ConvertFrom-Json
if ($p.firmware_confirmed -ne $true -or
    $p.firmware_from_current_tv_menu -ne 'T-NKMUABC-2743.0' -or
    $p.model_from_tv_menu -ne 'QA65Q80TAWXXY' -or
    $p.platform_version -ne '5.5' -or $p.cpu_arch -ne 'armv7') {
    throw 'Target model/firmware/capability preflight does not match the known Q80T.'
}
if (-not (Test-Path $configFile) -or -not (Test-Path $deviceFile)) {
    throw 'Missing .local signing/device setup.'
}
$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
$tv = Get-Content -LiteralPath $deviceFile -Raw | ConvertFrom-Json
$sdb = Join-Path ([string]$config.sdk_path) 'tools\sdb.exe'
if (-not (Test-Path -LiteralPath $sdb -PathType Leaf)) { throw 'Configured Samsung SDB not found.' }
$address = $null
if (-not [Net.IPAddress]::TryParse([string]$tv.host, [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'Configured TV address is not IPv4.'
}
if (-not (Test-Path -LiteralPath $unpacked -PathType Container)) { $null = Prepare }
$exe = UpstreamExe

if ($Action -eq 'Doctor') {
    Write-Output 'Checking upstream host prerequisites (no root attempt)...'
    & $exe --sdb $sdb doctor
    if ($LASTEXITCODE -ne 0) { throw "Upstream host doctor failed with code $LASTEXITCODE." }
    return
}

Write-Output 'WARNING: Probe runs a live third-party SDB exploit, temporary root acquisition and cleanup.'
Write-Output 'It does not install DansTV Home routing, debloat system services or patch firmware persistently.'
Write-Output "Target: QA65Q80TAWXXY, T-NKMUABC-2743.0, $($address.ToString())"
& $exe --sdb $sdb archive-root probe ($address.ToString())
$rc = $LASTEXITCODE
if ($rc -ne 0) { throw "Archive-root probe failed or found incompatible prerequisites (exit $rc). No persistent Home/debloat modifications were requested." }
Write-Output 'Upstream probe exited successfully; inspect its authenticated UID 0 and cleanup report before declaring root.'
