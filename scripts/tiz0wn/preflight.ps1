# Read-only Q80T / tiz0wn discovery. Does not root, launch, install or modify the TV.
[CmdletBinding()]
param(
    [string]$Firmware = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$signFile = Join-Path $root '.local\signing.json'
$tvFile = Join-Path $root '.local\device.json'
if (-not (Test-Path $signFile) -or -not (Test-Path $tvFile)) {
    throw 'Expected .local/signing.json and .local/device.json from the Q80T setup.'
}
$sign = Get-Content $signFile -Raw | ConvertFrom-Json
$tv = Get-Content $tvFile -Raw | ConvertFrom-Json
if (-not $sign.sdk_path -or -not $sign.app_id -or -not $tv.host) {
    throw 'Missing SDK path, app identity or TV host.'
}
if ($sign.app_id -notmatch '^[A-Za-z0-9]{10}\.[A-Za-z0-9_-]{1,52}$') {
    throw 'The signing configuration does not have an SDK-generated application ID.'
}
$ip = $null
if (-not [Net.IPAddress]::TryParse([string]$tv.host, [ref]$ip) -or
    $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'The device configuration needs a valid IPv4 address.'
}
$sdk = [string]$sign.sdk_path
if (-not [IO.Path]::IsPathRooted($sdk)) { $sdk = Join-Path $root $sdk }
$sdb = Join-Path $sdk 'tools\sdb.exe'
if (-not (Test-Path -LiteralPath $sdb -PathType Leaf)) { throw "SDB not found at $sdb" }
$serial = "$($ip.ToString()):26101"
$lines = & $sdb -s $serial capability 2>&1
if ($LASTEXITCODE -ne 0) { throw 'SDB capability query failed. Check Device Manager.' }
$caps = @{}
foreach ($line in $lines) {
    if ($line -match '^([A-Za-z0-9_]+):\s*(.*)$') { $caps[$Matches[1]] = $Matches[2].Trim() }
}
if ($caps.platform_version -ne '5.5' -or $caps.cpu_arch -ne 'armv7') {
    throw "Unexpected platform: $($caps.platform_version) / $($caps.cpu_arch). No tiz0wn changes attempted."
}
# This is the *owner-observed* About This TV value, not a capability field.
# Never infer exact firmware or a compatible rootfs patch from the Tizen version.
$expectedModel = 'QA65Q80TAWXXY'
$expectedFirmware = 'T-NKMUABC-2743.0'
if ($Firmware -and $Firmware -ne $expectedFirmware) {
    throw "Firmware mismatch: expected $expectedFirmware on $expectedModel; observed $Firmware. No modification attempted."
}
$record = [ordered]@{
    app_id = [string]$sign.app_id
    platform_version = $caps.platform_version
    cpu_arch = $caps.cpu_arch
    intershell_support = $caps.intershell_support
    model_from_tv_menu = $expectedModel
    expected_firmware_from_tv_menu = $expectedFirmware
    firmware_from_current_tv_menu = if ($Firmware) { $Firmware } else { $null }
    firmware_confirmed = [bool]($Firmware -eq $expectedFirmware)
    home_db_verified = $false
    root_channel_verified = $false
    original_home_backup_verified_off_tv = $false
}
$dest = Join-Path $root '.local\tiz0wn-preflight.json'
($record | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $dest -Encoding UTF8
Write-Output "Q80T target: Tizen $($caps.platform_version), $($caps.cpu_arch); interactive SDB shell $($caps.intershell_support)"
Write-Output "DansTV identity: $($sign.app_id)"
Write-Output "Owner-observed model/firmware: $expectedModel / $expectedFirmware"
Write-Output "Firmware confirmation in this run: $(if ($Firmware) { 'MATCH' } else { 'NOT PROVIDED (append -Firmware T-NKMUABC-2743.0)' })"
Write-Output 'Local preflight saved to .local\tiz0wn-preflight.json'
Write-Output 'No root, Home, boot, services or applications were changed.'
