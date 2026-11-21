$ErrorActionPreference = 'Continue'
$log = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\usb-monitor.log"
"$((Get-Date).ToString('HH:mm:ss')) 开始监视 300 秒（所有 USB 设备变动）" | Set-Content -Path $log -Encoding UTF8

$seen = @{}
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $seen[$_.InstanceId] = $true }

$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline) {
    $now = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
    foreach ($d in $now) {
        if (-not $seen.ContainsKey($d.InstanceId)) {
            $seen[$d.InstanceId] = $true
            $line = "{0}  新增: {1} | {2} | {3}" -f (Get-Date).ToString('HH:mm:ss'), $d.Status, $d.Class, $d.InstanceId
            Add-Content -Path $log -Value $line -Encoding UTF8
        }
    }
    Start-Sleep -Milliseconds 400
}
"$((Get-Date).ToString('HH:mm:ss')) 监视结束" | Add-Content -Path $log -Encoding UTF8
