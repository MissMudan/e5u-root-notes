$pn="C:\WINDOWS\System32\pnputil.exe"
$o=@()
$o += (& $pn /add-driver "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\driver-clean\sprdvcom.inf" /install 2>&1 | Out-String)
$o += "=== 在线设备 ==="
$o += (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_1782' } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List | Out-String)
$o += "=== 串口 ==="
$o += (Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -match 'VID_1782&PID_4D00' } | Select-Object Name,PNPDeviceID | Format-List | Out-String)
$o -join "
" | Set-Content -Path "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\reinstall-clean.log" -Encoding UTF8
