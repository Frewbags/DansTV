# Windows-only owner installation flow. No native Home/startup or firmware writes.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Sign', 'Info', 'Install', 'Launch')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $root '.local\signing.json'
$devicePath = Join-Path $root '.local\device.json'
$widgetTool = Join-Path $root 'scripts\owner-widget.py'
$unsigned = Join-Path $root 'dist\DansTV-unsigned.wgt'
$signed = Join-Path $root 'dist\DansTV.wgt'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Create .local/signing.json with your own Samsung signing profile and SDK-generated app identity.'
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (-not $config.sdk_path -or -not $config.profile -or -not $config.package_id -or -not $config.app_id) {
    throw '.local/signing.json must include sdk_path, profile, package_id and app_id.'
}

$sdkPath = [string]$config.sdk_path
if (-not [IO.Path]::IsPathRooted($sdkPath)) {
    $sdkPath = Join-Path $root $sdkPath
}
$sdk = (Resolve-Path -LiteralPath $sdkPath -ErrorAction Stop).Path
$tizen = Join-Path $sdk 'tools\ide\bin\tizen.bat'
$sdb = Join-Path $sdk 'tools\sdb.exe'

function Invoke-Python([string[]]$Arguments) {
    & python $widgetTool @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Owner widget validation failed.' }
}

function Invoke-Sdb([string[]]$Arguments) {
    $output = (& $sdb @Arguments 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'SDB command failed; inspect the TV developer connection.' }
    return $output
}

# Check owner identity on every action, before touching the TV.
# --verify is used for signed packages; a dry preparation is safe and offline.
if ($Action -eq 'Sign') {
    if (-not (Test-Path -LiteralPath $tizen -PathType Leaf)) {
        throw 'Tizen Studio CLI missing under tools\ide\bin. See docs/q80t-setup.md.'
    }
    Invoke-Python @()
    $folder = Join-Path $root ('dist\signed-q80t-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null

    # A new output folder prevents a stale signed package from masking an SDK failure.
    # Do not print SDK signing output: it may contain certificate/profile secrets.
    & $tizen package -t wgt -s ([string]$config.profile) -o $folder -- $unsigned 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Signing failed; check Certificate Manager and saved profile access.' }
    $staged = Join-Path $folder 'DansTV-unsigned.wgt'
    if (-not (Test-Path -LiteralPath $staged -PathType Leaf)) {
        throw 'Tizen CLI did not create the expected signed widget.'
    }
    Invoke-Python @('--verify', $staged)
    Copy-Item -LiteralPath $staged -Destination $signed -Force
    Write-Output 'Signed owner widget prepared: dist\DansTV.wgt'
    Write-Output 'Nothing was installed or changed on the TV.'
    return
}

# No connection is made without an explicitly selected Info, Install or Launch action.
if (-not (Test-Path -LiteralPath $sdb -PathType Leaf)) {
    throw 'Samsung SDB is missing under Tizen Studio tools.'
}
if (-not (Test-Path -LiteralPath $devicePath -PathType Leaf)) {
    throw 'Create .local/device.json containing the TV IPv4 address (host).'
}
$device = Get-Content -LiteralPath $devicePath -Raw | ConvertFrom-Json
$parsed = $null
if (-not [Net.IPAddress]::TryParse([string]$device.host, [ref]$parsed) -or
    $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'The TV host must be a valid local IPv4 address.'
}

if ($Action -eq 'Install') {
    if (-not (Test-Path -LiteralPath $signed -PathType Leaf)) {
        throw 'Sign your widget first: .\scripts\q80t-windows.ps1 Sign'
    }
    Invoke-Python @('--verify', $signed)
} else {
    # Validate custom identity without writing files or contacting the TV.
    Invoke-Python @('--check')
}

$serial = "$($parsed.ToString()):26101"
$connected = Invoke-Sdb @('connect', $serial)
if ($connected -notmatch 'connected to|already connected') {
    throw 'SDB connection was not confirmed. Check TV Developer Mode and the Host PC IP.'
}

switch ($Action) {
    'Info' {
        $capabilities = Invoke-Sdb @('-s', $serial, 'capability')
        Write-Output $capabilities
        Write-Output 'Read-only capability query complete. No TV settings changed.'
    }
    'Launch' {
        $result = Invoke-Sdb @('-s', $serial, 'shell', '0', 'execute', [string]$config.app_id)
        if ($result -notmatch 'successfully launched') {
            throw 'The TV did not confirm launch; verify on the screen.'
        }
        Write-Output 'DansTV launch command confirmed. Verify its appearance on the TV.'
    }
    'Install' {
        $hash = (Get-FileHash -LiteralPath $signed -Algorithm SHA256).Hash.Substring(0, 12)
        $remote = '/home/owner/share/tmp/sdk_tools/DansTV-' + $hash + '-' + [DateTime]::UtcNow.Ticks + '.wgt'
        $pushed = Invoke-Sdb @('-s', $serial, 'push', $signed, $remote)
        if ($pushed -notmatch '1 file\(s\) pushed' -or $pushed -match 'failed') {
            throw 'Widget upload was not confirmed.'
        }
        $installed = Invoke-Sdb @('-s', $serial, 'shell', '0', 'vd_appinstall', [string]$config.app_id, $remote)
        if ($installed -notmatch 'install completed' -or $installed -match 'install failed') {
            throw 'Installation was not confirmed; do not assume it succeeded.'
        }
        $apps = Invoke-Sdb @('-s', $serial, 'shell', '0', 'applist')
        if (-not $apps.Contains([string]$config.app_id)) {
            throw 'DansTV was not found in the installed applications.'
        }
        Write-Output 'DansTV installation confirmed. Samsung Home/startup settings unchanged.'
    }
}
