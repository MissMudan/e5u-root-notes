$ErrorActionPreference = 'Continue'
$log = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\cdc-fix.log"
Start-Transcript -Path $log -Force | Out-Null

$inst = (Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_1782&PID_4D00' } | Select-Object -First 1).InstanceId
Write-Host "实例: $inst"

$key = "HKLM\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters"
$exists = Test-Path "Registry::$key"
Write-Host "参数键存在: $exists"

foreach ($v in @(1, 3)) {
    & "$env:SystemRoot\System32\reg.exe" add "$key" /v CdcControlLineState /t REG_DWORD /d $v /f 2>&1
}
& "$env:SystemRoot\System32\reg.exe" query "$key" 2>&1

Write-Host "=== 重启设备节点 ==="
& "$env:SystemRoot\System32\pnputil.exe" /restart-device "$inst" 2>&1
Start-Sleep -Seconds 3
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_1782' } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List | Out-String | Write-Host

Stop-Transcript | Out-Null
