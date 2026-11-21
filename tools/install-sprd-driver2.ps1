$ErrorActionPreference='Continue'
$out = & "C:\WINDOWS\System32\pnputil.exe" /add-driver "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\driver\sprdvcom.inf" /install 2>&1 | Out-String
"EXIT=$LASTEXITCODE"
$out
"=== enum ==="
& "C:\WINDOWS\System32\pnputil.exe" /enum-drivers 2>&1 | Out-String -Width 200 | Set-Content -Path "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\driver-install2.log.enum.txt" -Encoding UTF8
$out | Set-Content -Path "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\driver-install2.log" -Encoding UTF8
