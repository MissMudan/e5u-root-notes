$ErrorActionPreference = 'Continue'
$log = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\cdc-watch.log"
$o = @()

$o += "等待下载模式设备接入（最多 180 秒）..."
$deadline = (Get-Date).AddSeconds(180)
$inst = $null
while ((Get-Date) -lt $deadline) {
    $inst = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1782&PID_4D00' } |
        Select-Object -First 1).InstanceId
    if ($inst) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $inst) {
    $o += "超时：未检测到设备"
    $o -join "`n" | Set-Content -Path $log -Encoding UTF8
    exit 1
}
$o += "实例: $inst"

$key = "HKLM\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters"
$o += (& "$env:SystemRoot\System32\reg.exe" add "$key" /v CdcControlLineState /t REG_DWORD /d 3 /f 2>&1 | Out-String)
Start-Sleep -Milliseconds 300
$o += (& "$env:SystemRoot\System32\pnputil.exe" /restart-device "$inst" 2>&1 | Out-String)

Start-Sleep -Seconds 2
$p = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.PNPDeviceID -match 'VID_1782&PID_4D00' } |
    Select-Object Name, PNPDeviceID
$o += "=== 端口 ==="
$o += ($p | Format-List | Out-String)

$o -join "`n" | Set-Content -Path $log -Encoding UTF8
