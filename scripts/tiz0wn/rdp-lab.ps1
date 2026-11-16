# Disposable Q80T Remote PC lab: Docker xrdp on 3389 + native Windows SMB on 445.
# Run from an ELEVATED Windows PowerShell. No exploit or TV-side command is executed.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Setup', 'Status', 'Cleanup')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lab = Join-Path $root '.local\tiz0wn-lab'
$envFile = Join-Path $lab 'lab.env'
$marker = Join-Path $lab 'ownership.json'
$folder = Join-Path $lab 'share'
$compose = Join-Path $PSScriptRoot 'lab\compose.yml'
$name = 'danstvprobe'
$shareName = 'DansTVProbe'
$fwSMB = 'DansTVProbe-Temporary-SMB'
$fwRDP = 'DansTVProbe-Temporary-RDP'

function Need-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run PowerShell as Administrator for the temporary local SMB user/share and firewall rules.'
    }
}
function Current-Share {
    Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
}
function Current-User {
    Get-LocalUser -Name $name -ErrorAction SilentlyContinue
}
function Compose([string]$action) {
    if (-not (Test-Path $envFile)) { throw 'Missing lab.env; cannot safely select Docker environment.' }
    & docker compose --env-file $envFile -f $compose @($action)
    if ($LASTEXITCODE -ne 0) { throw "Docker compose $action failed." }
}
function Check-Existing {
    if ((Current-User) -or (Current-Share) -or (Test-Path $marker) -or (Test-Path $envFile)) {
        throw 'A lab user/share or local credentials already exists. Inspect before Setup; never overwrite another account or existing credentials.'
    }
    if (Get-NetFirewallRule -Name $fwSMB -ErrorAction SilentlyContinue) { throw 'Temporary SMB firewall rule already exists.' }
    if (Get-NetFirewallRule -Name $fwRDP -ErrorAction SilentlyContinue) { throw 'Temporary RDP firewall rule already exists.' }
}
function Host-IP([string]$tvIP) {
    $client = New-Object System.Net.Sockets.UdpClient([Net.Sockets.AddressFamily]::InterNetwork)
    try {
        # Connect chooses the local interface to reach the TV; no UDP packet is sent.
        $client.Connect($tvIP, 26101)
        return ([System.Net.IPEndPoint]$client.Client.LocalEndPoint).Address.ToString()
    } finally { $client.Close() }
}
function Read-Target {
    $path = Join-Path $root '.local\device.json'
    if (-not (Test-Path $path -PathType Leaf)) { throw 'Missing Q80T .local/device.json.' }
    $config = Get-Content $path -Raw | ConvertFrom-Json
    $ip = $null
    if (-not [Net.IPAddress]::TryParse([string]$config.host, [ref]$ip) -or
        $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'The Q80T IPv4 address in .local/device.json is invalid.'
    }
    return $ip.ToString()
}
Need-Admin
$tvIP = Read-Target
switch ($Action) {
    'Setup' {
        Check-Existing
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker CLI not found.' }
        if (-not (Get-SmbServerConfiguration).EnableSMB2Protocol) {
            throw 'SMB2 is not enabled in Windows. Do not weaken SMB security to accommodate this lab.'
        }
        if (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue) {
            throw 'RDP port 3389 is occupied. The lab will not replace an existing service.'
        }
        $pcIP = Host-IP $tvIP
        $localPC = $null
        if (-not [Net.IPAddress]::TryParse($pcIP, [ref]$localPC) -or
            $localPC.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $localPC.IsIPv6LinkLocal) { throw "Unexpected PC source address: $pcIP" }
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 18
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        $password = 'TvA9' + ([BitConverter]::ToString($bytes) -replace '-', '')
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        # Ownership file deliberately precedes account/share creation so Cleanup
        # can remove only the exact lab resources after a partial setup failure.
        [ordered]@{user=$name; share=$shareName; tv=$tvIP; pc=$pcIP; created_utc=(Get-Date).ToUniversalTime().ToString('o')} |
            ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
        @("LAB_HOST_IP=$pcIP","TVPROBE_USER=$name","TVPROBE_PASSWORD=$password") |
            Set-Content -LiteralPath $envFile -Encoding ASCII
        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        New-LocalUser -Name $name -Password $secure -AccountNeverExpires -PasswordNeverExpires -Description 'Temporary DansTV Remote PC SMB lab user' | Out-Null
        $who = "$env:COMPUTERNAME\$name"
        & icacls.exe $folder /inheritance:r /grant:r "${who}:(OI)(CI)M" 'BUILTIN\Administrators:(OI)(CI)F' 'NT AUTHORITY\SYSTEM:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Setting temporary folder ACL failed.' }
        'DansTV temporary shared-folder test' | Set-Content -LiteralPath (Join-Path $folder 'readme.txt')
        New-SmbShare -Name $shareName -Path $folder -ChangeAccess $who | Out-Null
        New-NetFirewallRule -Name $fwSMB -DisplayName 'DansTV temporary SMB lab' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445 -RemoteAddress $tvIP -Profile Any | Out-Null
        New-NetFirewallRule -Name $fwRDP -DisplayName 'DansTV temporary RDP lab' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress $tvIP -Profile Any | Out-Null
        Write-Output "PC LAN IPv4: $pcIP; Q80T: $tvIP"
        Write-Output 'Building and starting disposable XRDP desktop (no TV connection)...'
        & docker compose --env-file $envFile -f $compose up -d --build
        if ($LASTEXITCODE -ne 0) { throw 'RDP container startup failed. Run -Action Cleanup to reverse the Windows changes.' }
        Write-Output "TV Remote PC server: $pcIP (port 3389)"
        Write-Output "SMB share: \\$pcIP\$shareName (Windows port 445)"
        Write-Output "RDP and SMB username: $name"
        Write-Output "Read the temporary password locally: (Get-Content '$envFile' | Select-String TVPROBE_PASSWORD)"
        Write-Output 'Keep credentials out of chat. No TV root test has been triggered.'
    }
    'Status' {
        Write-Output "Windows SMB2: $((Get-SmbServerConfiguration).EnableSMB2Protocol)"
        Write-Output "Lab user present: $([bool](Current-User))"
        Write-Output "Lab share present: $([bool](Current-Share))"
        Write-Output "Windows PID(s) bound to SMB 445: $((Get-NetTCPConnection -State Listen -LocalPort 445 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique) -join ',')"
        if (Test-Path $envFile) {
            & docker compose --env-file $envFile -f $compose ps
            Write-Output "RDP on PC: $(Test-NetConnection -ComputerName (Host-IP $tvIP) -Port 3389 -InformationLevel Quiet)"
            Write-Output "SMB on PC: $(Test-NetConnection -ComputerName (Host-IP $tvIP) -Port 445 -InformationLevel Quiet)"
        } else { Write-Output 'No lab credentials on disk.' }
    }
    'Cleanup' {
        if (-not (Test-Path $marker -PathType Leaf)) {
            throw 'No ownership marker. Refusing to remove preexisting users/shares.'
        }
        $owned = Get-Content $marker -Raw | ConvertFrom-Json
        if ($owned.user -ne $name -or $owned.share -ne $shareName -or $owned.tv -ne $tvIP) {
            throw 'Lab ownership marker mismatch. Refusing cleanup.'
        }
        if (Test-Path $envFile) {
            & docker compose --env-file $envFile -f $compose down --remove-orphans
            if ($LASTEXITCODE -ne 0) { throw 'Stop the lab container before deleting credentials.' }
        }
        Get-NetFirewallRule -Name $fwSMB -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
        Get-NetFirewallRule -Name $fwRDP -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
        if (Current-Share) { Remove-SmbShare -Name $shareName -Force }
        if (Current-User) { Remove-LocalUser -Name $name }
        if (Test-Path $envFile) { Remove-Item -LiteralPath $envFile -Force }
        if (Test-Path $marker) { Remove-Item -LiteralPath $marker -Force }
        Write-Output 'Temporary Windows user, SMB share, lab firewall rules and credentials removed. Docker lab stopped.'
        Write-Output "Local test folder retained at $folder for manual inspection/deletion."
    }
}
