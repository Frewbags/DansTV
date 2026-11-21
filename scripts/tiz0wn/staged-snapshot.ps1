# One-session Q80T read-only survey using SDB-staged source and short TV input.
# Requires owner action on the TV. Never changes Home, firmware or boot state.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Doctor','Prepare','Collect','Restore')][string]$Action)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lab = Join-Path $root '.local\tiz0wn-lab'
$envFile = Join-Path $lab 'lab.env'
$backup = Join-Path $lab 'lab.env.before-staged'
$sessionFile = Join-Path $lab 'staged-session.json'
$compose = Join-Path $PSScriptRoot 'lab\compose.yml'
$stager = Join-Path $PSScriptRoot 'staged-snapshot.py'
$bridge = Join-Path $PSScriptRoot 'root-bridge.ps1'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run from Administrator PowerShell.'
}
$owner = Get-Content -LiteralPath (Join-Path $lab 'ownership.json') -Raw | ConvertFrom-Json
if ($owner.user -ne 'danstvprobe' -or $owner.share -ne 'DansTVProbe') {
    throw 'Unexpected lab account/share; no changes made.'
}
foreach ($address in @($owner.pc, $owner.tv)) {
    $ip = [Net.IPAddress]::Parse($address)
    if ($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        -not $ip.IsIPv4MappedToIPv6 -eq $false) {
        # IPv4 validation is sufficient; never assume an Internet/public target.
        throw 'Unexpected IP family; owner lab needs IPv4 addresses.'
    }
}
function Password([string]$file) {
    $hits = @(Get-Content -LiteralPath $file | Where-Object { $_.StartsWith('TVPROBE_PASSWORD=') })
    if ($hits.Count -ne 1) { throw 'Expected exactly one private password field.' }
    return $hits[0].Substring('TVPROBE_PASSWORD='.Length)
}
function Assert-Engine {
    & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop engine is not ready.' }
    & docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose is unavailable.' }
}
function Invoke-Compose([string[]]$arguments) {
    $previous = [Environment]::GetEnvironmentVariable('LAB_HOST_IP','Process')
    try {
        $env:LAB_HOST_IP = [string]$owner.pc
        & docker compose -f $compose @arguments
        if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed; credential backup retained.' }
    } finally {
        if ($null -eq $previous) { Remove-Item Env:LAB_HOST_IP -ErrorAction SilentlyContinue }
        else { $env:LAB_HOST_IP = $previous }
    }
}
function Tcp-Ready {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync([string]$owner.pc, 3389)
        if (-not $task.Wait(700)) { return $false }
        if ($task.IsFaulted) { return $false }
        return $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
}
function Wait-Xrdp {
    $startedCreated = $false
    for ($i = 0; $i -lt 25; $i++) {
        $status = (& docker inspect -f '{{.State.Status}}' danstv-remote-pc-lab 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'XRDP container was not created.' }
        if ($status -eq 'created' -and -not $startedCreated -and $i -ge 2) {
            & docker start danstv-remote-pc-lab | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'XRDP container could not start.' }
            $startedCreated = $true
        }
        if ($status -eq 'running' -and (Tcp-Ready)) { return }
        Start-Sleep -Milliseconds 750
    }
    throw 'XRDP container/port 3389 never reached READY; recovery required.'
}
function Rotate([string]$password) {
    Assert-Engine
    Invoke-Compose -arguments @('config','--quiet')
    $null = Password $envFile
    $lines = @(Get-Content -LiteralPath $envFile | ForEach-Object {
        if ($_.StartsWith('TVPROBE_PASSWORD=')) { 'TVPROBE_PASSWORD=' + $password }
        else { $_ }
    })
    Set-LocalUser -Name 'danstvprobe' -Password (ConvertTo-SecureString $password -AsPlainText -Force)
    $lines | Set-Content -LiteralPath $envFile -Encoding ASCII
    Invoke-Compose -arguments @('up','-d','--force-recreate','--no-build')
    Wait-Xrdp
}
if ($Action -eq 'Restore') {
    # Restoration never requires the TV, SDB, model preflight or a working report.
    $hasBackup = Test-Path -LiteralPath $backup
    $hasSession = Test-Path -LiteralPath $sessionFile
    if ($hasSession -and -not $hasBackup) {
        throw 'Staged session exists but credential backup is absent. Preserve session and inspect credentials.'
    }
    if ($hasBackup) {
        Rotate (Password $backup)
        Remove-Item -LiteralPath $backup -Force
    }
    if ($hasSession) { Remove-Item -LiteralPath $sessionFile -Force }
    if ($hasBackup) { Write-Output 'RESTORED: original Windows/XPDR credentials and ready XRDP listener.' }
    else { Write-Output 'No staged credential backup; no lab credentials changed.' }
    return
}
if (Test-Path -LiteralPath $backup -PathType Leaf -and $Action -eq 'Doctor') {
    throw 'An earlier staged session is active; use Restore or Collect before Doctor.'
}
if ($Action -eq 'Collect') {
    if (-not (Test-Path -LiteralPath $backup) -or -not (Test-Path -LiteralPath $sessionFile)) {
        throw 'No staged session to collect; no credential changes made.'
    }
    $result = 1
    try {
        & py -3 $stager collect
        $result = $LASTEXITCODE
    } finally {
        # Always restore even if report is unavailable, truncated or non-root.
        & $PSCommandPath -Action Restore
    }
    if ($result -ne 0) { throw 'No validated snapshot received; lab credentials have been restored.' }
    return
}
if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $sessionFile)) {
    throw 'Staged trial already active; Collect or Restore first.'
}
# Reuse the exact Q80T model, firmware, ownership and Docker/SMB safeguards.
& $bridge -Action Doctor
if ($Action -eq 'Doctor') {
    Write-Output 'STAGED-DOCTOR: host prerequisites OK; no SDB/TV connection attempted.'
    return
}
# Stage and verify the fixed survey before changing any credentials.
& py -3 $stager stage --tv ([string]$owner.tv)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sessionFile)) {
    throw 'Staging did not pass read-back verification; lab credentials unchanged.'
}
$session = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
$allowed = ('/tmp/dtvq' + $session.token)
$alternate = ('/home/owner/share/tmp/sdk_tools/dtvq' + $session.token)
if ($session.script_path -cne $allowed -and $session.script_path -cne $alternate) {
    throw 'Unrecognised staged source path. Credentials unchanged.'
}
$probe = '$(. ' + $session.script_path + ')'
if ($probe.Length -gt 80) { throw 'Staged input too long; credentials unchanged.' }
Copy-Item -LiteralPath $envFile -Destination $backup -ErrorAction Stop
try {
    Rotate $probe
} catch {
    $failure = $_.Exception.Message
    try {
        & $PSCommandPath -Action Restore
    } catch {
        Write-Warning 'Restoration failed; private backup remains. Resolve before retrying.'
        throw
    }
    throw ('Staged preparation failed, recovered lab credentials: ' + $failure)
}
Write-Output 'PREPARED: survey upload SHA-256 verified, XRDP running, TCP/3389 accepting.'
Write-Output 'TV Remote PC username: danstvprobe'
Write-Output 'TV Remote PC PASSWORD (enter literally using SmartThings):'
Write-Output $probe
Write-Output 'Reconnect Remote PC and open Shared Folder ONCE.'
Write-Output 'Then run: .\scripts\tiz0wn\staged-snapshot.ps1 -Action Collect'
Write-Output 'If you stop: .\scripts\tiz0wn\staged-snapshot.ps1 -Action Restore'
