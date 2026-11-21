$ErrorActionPreference='Continue'
Start-Transcript -Path "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\driver-install.log" -Force | Out-Null
"=== pnputil add-driver ==="
pnputil /add-driver "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\driver\sprdvcom.inf" /install 2>&1
"=== pnputil 枚举已装展锐驱动 ==="
pnputil /enum-drivers 2>&1 | Select-String -Pattern 'sprdvcom|sprdadb' -Context 3,3
"=== 设备状态 ==="
Get-PnpDevice | Where-Object { $_.InstanceId -match '1782' } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List
"=== COM 端口 ==="
Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue | Select-Object Status,FriendlyName | Format-Table -Auto
Stop-Transcript | Out-Null
