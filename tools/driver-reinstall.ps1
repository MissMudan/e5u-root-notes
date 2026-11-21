$ErrorActionPreference = 'Continue'
$log = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\tools\driver-reinstall.log"
$d = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\driver"
$pn = "$env:SystemRoot\System32\pnputil.exe"

$out = @()

$old = & $pn /enum-drivers 2>&1 | Out-String
$pubs = [regex]::Matches($old, 'oem\d+\.inf') | ForEach-Object { $_.Value } | Select-Object -Unique
$out += "已有第三方 inf: " + ($pubs -join ', ')

foreach ($p in $pubs) {
    $name = & $pn /enum-drivers 2>&1 | Out-String
    $block = [regex]::Match($name, "(?s)发布名称:\s*$([regex]::Escape($p)).*?原始名称:\s*(\S+)")
    if ($block.Success -and $block.Groups[1].Value -match 'sprdvcom') {
        $out += "删除 $p"
        $out += (& $pn /delete-driver $p /uninstall /force 2>&1 | Out-String)
    }
}

$out += "=== 重新安装 ==="
$out += (& $pn /add-driver "$d\sprdvcom.inf" /install 2>&1 | Out-String)

$out += "=== 当前实例参数 ==="
$inst = (Get-PnpDevice | Where-Object { $_.InstanceId -match 'VID_1782&PID_4D00' } | Select-Object -First 1).InstanceId
$out += "实例: $inst"
$out += (& "$env:SystemRoot\System32\reg.exe" query "HKLM\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters" 2>&1 | Out-String)

$out += "=== 设备状态 ==="
$out += (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_1782' } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List | Out-String)

$out -join "`n" | Set-Content -Path $log -Encoding UTF8
