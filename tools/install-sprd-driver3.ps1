$ErrorActionPreference='Continue'
$o = & "C:\WINDOWS\System32\pnputil.exe" /add-driver "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\driver\sprdvcom.inf" /install 2>&1 | Out-String
"EXIT=$LASTEXITCODE"
$o
& "C:\WINDOWS\System32\pnputil.exe" /enum-drivers 2>&1 | Out-String -Width 200 | Select-String -Pattern 'sprdvcom' -Context 4,2 | ForEach-Object { $_.ToString() }
"=== 设备 ==="
Get-PnpDevice | Where-Object { $_.InstanceId -match '1782' } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List | Out-String
Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue | Select-Object Status,FriendlyName | Format-Table -Auto | Out-String
$o | Set-Content -Path "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\driver-install3.log" -Encoding UTF8
