$ErrorActionPreference = 'Continue'
$log = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\official-driver.log"
$dir = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\spd-driver-official\SPD_Driver_R4.20.4201\Win10\Drivers"
$pn = "$env:SystemRoot\System32\pnputil.exe"
$o = @()

$o += "=== 导入 config.reg ==="
$o += (& "$env:SystemRoot\System32\reg.exe" import "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\spd-driver-official\SPD_Driver_R4.20.4201\Win10\config.reg" 2>&1 | Out-String)

foreach ($inf in @('sprdvcom.inf', 'sprdadb.inf', 'rdavcom.inf', 'sprdvmdm.inf')) {
    $o += "=== 安装 $inf ==="
    $o += (& $pn /add-driver "$dir\$inf" /install 2>&1 | Out-String)
}

$o += "=== 已安装的 sprd 驱动包 ==="
$enum = & $pn /enum-drivers 2>&1 | Out-String
$o += (($enum -split "`r?`n" | Select-String -Pattern 'sprdvcom|sprdadb|rdavcom|sprdvmdm' -Context 3,3) | ForEach-Object { $_.ToString() }) -join "`n"

$o -join "`n" | Set-Content -Path $log -Encoding UTF8
