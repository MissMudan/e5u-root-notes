<#
采集本机硬件档案（SoC / CPU 簇 / GPU / 存储 / 屏幕 / 触摸 / 手柄 / 传感器 / 无线 / 电源 / 散热）。
用于和 docs/06-machine-profile.md 逐项对照。

用法：
  pwsh -File .\collect-profile.ps1
  pwsh -File .\collect-profile.ps1 -AdbPath "C:\Android\platform-tools\adb.exe" -Out .\my-hw.md

只读操作：不写分区、不改设置、不 root。要求 adb 已授权（adb devices 显示 device）。
#>

param(
  [string]$AdbPath = "adb",
  [string]$Out = ".\hw-profile-$(Get-Date -Format yyyyMMdd-HHmm).md"
)

$ErrorActionPreference = 'Continue'
$script:L = New-Object System.Collections.Generic.List[string]

function A([string]$cmd) {
  $r = & $AdbPath shell $cmd 2>$null
  if ($null -eq $r) { return "" }
  return (($r -join "`n").Trim())
}
function P([string]$k, [string]$v) { $script:L.Add("| $k | $v |") }
function H2([string]$t) { $script:L.Add(""); $script:L.Add("## $t"); $script:L.Add(""); $script:L.Add("| 项 | 值 |"); $script:L.Add("| --- | --- |") }
function CODE([string]$t) { $script:L.Add(""); $script:L.Add('```'); $script:L.Add($t); $script:L.Add('```') }

$devList = (& $AdbPath devices) -join "`n"
if ($devList -notmatch "device") {
  Write-Host "没有已授权的设备。请打开 USB 调试并在手机上点“一律允许”。" -ForegroundColor Red
  Write-Host $devList; exit 1
}

$serial = A "getprop ro.boot.serialno"

$script:L.Add("# 硬件档案 · $serial")
$script:L.Add("")
$script:L.Add("采集时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ／ 采集主机 OS $([Environment]::OSVersion.VersionString)")
$script:L.Add("")
$script:L.Add("> 全部为设备实测值，命令见文末「采集方法」。")

# 1 整机
H2 "1 · 整机标识"
P "型号 model"            (A "getprop ro.product.model")
P "品牌 / 厂商"           ((A "getprop ro.product.brand") + " / " + (A "getprop ro.product.manufacturer"))
P "内部代号 device"       (A "getprop ro.product.device")
P "平台 platform"         (A "getprop ro.board.platform")
P "硬件标识 hardware"     ((A "getprop ro.hardware") + " / " + (A "getprop ro.boot.hardware"))
P "SN"                    $serial
P "RAM 标称 / 实测"       ("见第 5 节；MemTotal 换算后约 " + [math]::Round([int]((A "cat /proc/meminfo | grep MemTotal") -replace '\D','') / 1048576, 2) + " GiB")
P "系统 / SDK"            ((A "getprop ro.build.version.release") + " / " + (A "getprop ro.build.version.sdk"))
P "构建号"                ((A "getprop ro.build.display.id") -replace '\s*release-keys','')
P "内核"                  (A "uname -a")
P "ABI"                   (A "getprop ro.product.cpu.abi")

# 2 CPU
$script:L.Add("")
$script:L.Add("## 2 · CPU 簇（/proc/cpuinfo + cpufreq 实测）")
$script:L.Add("")
$script:L.Add("| 核 | ARM part | variant | 最大 MHz | 最小 MHz |")
$script:L.Add("| --- | --- | --- | --- | --- |")
for ($i = 0; $i -lt 8; $i++) {
  $raw = A "cat /proc/cpuinfo | grep -A 7 '^processor.*: $i$'"
  $part = if ($raw -match 'CPU part\s*:\s*(\S+)') { $matches[1] } else { "?" }
  $var  = if ($raw -match 'CPU variant\s*:\s*(\S+)') { $matches[1] } else { "?" }
  $mx = A "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq"
  $mn = A "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq"
  $mxM = if ($mx) { [math]::Round([int]$mx / 1000) } else { "" }
  $mnM = if ($mn) { [math]::Round([int]$mn / 1000) } else { "" }
  $script:L.Add("| cpu$i | $part | $var | $mxM | $mnM |")
}
$script:L.Add("")
$script:L.Add("cpufreq 策略：")
CODE (A "for p in /sys/devices/system/cpu/cpufreq/policy*; do echo ==== `$p; echo -n 'cpus: '; cat `$p/related_cpus; echo -n 'min:  '; cat `$p/cpuinfo_min_freq; echo -n 'max:  '; cat `$p/cpuinfo_max_freq; echo -n 'gov:  '; cat `$p/scaling_governor; done")
$script:L.Add("")
$script:L.Add("调度限制：")
CODE (A "echo clamp_min=`$(cat /proc/sys/kernel/sched_util_clamp_min); echo clamp_max=`$(cat /proc/sys/kernel/sched_util_clamp_max)")
$script:L.Add("")
$script:L.Add("可用频率档位：")
CODE (A "for p in /sys/devices/system/cpu/cpufreq/policy*; do echo -n `"`$p: `"; cat `$p/scaling_available_frequencies 2>/dev/null; done")

# 3 GPU
$gpu = A "ls -d /sys/class/devfreq/*gpu* 2>/dev/null | head -1"
H2 "3 · GPU"
P "GLES 标识"   (A "dumpsys SurfaceFlinger | grep -m1 'GLES:'")
P "devfreq 节点" ($(if ($gpu) { $gpu } else { "(未找到)" }))
if ($gpu) { P "GPU 最小/最大/调速" ((A "cat $gpu/min_freq") + " / " + (A "cat $gpu/max_freq") + " / " + (A "cat $gpu/governor")) }
P "全部 devfreq" (A "ls /sys/class/devfreq | tr '\n' ' '")

# 4 存储
H2 "4 · 存储"
P "userdata 设备"     (A "ls -l /dev/block/by-name/userdata")
P "容量"              (A "df -h /data | tail -1")
P "UFS/SD 厂商型号"   ((A "cat /sys/block/sda/device/vendor 2>/dev/null") + " " + (A "cat /sys/block/sda/device/model 2>/dev/null") + " rev=" + (A "cat /sys/block/sda/device/rev 2>/dev/null"))
P "block 设备数"      (A "ls /sys/class/block | grep -E '^sd[a-z]$' | tr '\n' ' '")
P "ZRAM 大小"         (A "cat /sys/block/zram0/disksize 2>/dev/null")

# 5 内存
H2 "5 · 内存"
P "MemTotal"  (A "cat /proc/meminfo | grep MemTotal")
P "SwapTotal" (A "cat /proc/meminfo | grep SwapTotal")
P "MemAvailable" (A "cat /proc/meminfo | grep MemAvailable")

# 6 屏幕
H2 "6 · 屏幕"
$disp = A "dumpsys display | grep -m1 'DisplayDeviceInfo'"
P "物理分辨率 / 密度" ((A "wm size") + " ｜ " + (A "wm density"))
P "ro.sf.lcd_density" (A "getprop ro.sf.lcd_density")
$fps = ([regex]::Matches($disp, 'fps=([0-9.]+)') | ForEach-Object { $_.Groups[1].Value }) -join " / "
$modes = ([regex]::Matches($disp, 'id=(\d+), width=(\d+), height=(\d+), fps=([0-9.]+)') | ForEach-Object { "$($_.Groups[2].Value)x$($_.Groups[3].Value)@$($_.Groups[4].Value)" }) -join ", "
P "支持模式"          ($(if ($modes) { $modes } else { "见下方原文" }))
P "刷新率"            ($(if ($fps) { $fps + " Hz" } else { "见下方原文" }))
P "亮度上限"          (A "cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -1")
P "背光节点"          (A "ls /sys/class/backlight 2>/dev/null | tr '\n' ' '")
if ($disp) { CODE $disp }

# 7 输入
$script:L.Add("")
$script:L.Add("## 7 · 输入设备（按键 / 摇杆 / 触摸 / 耳机）")
$script:L.Add("")
$script:L.Add("| Name | 物理路径 | 事件节点 |")
$script:L.Add("| --- | --- | --- |")
$inp = A "cat /proc/bus/input/devices"
$curName = ""; $curPhys = ""; $curHand = ""
foreach ($line in ($inp -split "`n")) {
  if ($line -match '^N: Name="(.+)"') { $curName = $matches[1] }
  elseif ($line -match '^P: Phys=(.*)') { $curPhys = $matches[1] }
  elseif ($line -match '^H: Handlers=(.*)') {
    $curHand = ($matches[1] -split '\s+' | Where-Object { $_ -match '^event' }) -join ","
    $script:L.Add("| $curName | $curPhys | $curHand |")
  }
}
$script:L.Add("")
$script:L.Add("原始 input 描述：")
CODE $inp

# 8 传感器
H2 "8 · 传感器"
CODE (A "dumpsys sensorservice | grep -A 40 'Sensor List' | head -40")

# 9 无线
H2 "9 · 无线"
P "WiFi 驱动/节点"  (A "getprop persist.sys.wifi.reset.devpath")
P "当前 WiFi"       (A "dumpsys wifi | grep -m1 'mWifiInfo'")
P "WiFi 频段证据"   ("扫描/历史中含 5180MHz 等 5GHz 信道时说明支持双频；见右侧原文")
P "蓝牙 MAC"        (A "cat /data/vendor/bluetooth/btmac.txt 2>/dev/null")
P "USB 控制器"      (A "ls /sys/class/udc 2>/dev/null")

# 10 电源与散热
H2 "10 · 电源"
P "设计容量 µAh"      (A "cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null")
P "当前状态"          ((A "dumpsys battery | grep -E 'level|voltage|temperature|health'") -replace "`n", " ｜ ")
P "充电上限电压"      (A "dumpsys battery | grep -m1 'Max charging'")

$script:L.Add("")
$script:L.Add("## 11 · 散热测温点")
CODE (A "for z in /sys/class/thermal/thermal_zone*; do echo -n `"`$z `"; cat `$z/type; echo -n '  temp='; cat `$z/temp; done")

$script:L.Add("")
$script:L.Add("## 12 · 采集方法")
$script:L.Add("")
$script:L.Add('```powershell')
$script:L.Add("pwsh -File .\collect-profile.ps1 -AdbPath <adb路径> -Out .\my-hw.md")
$script:L.Add('```')
$script:L.Add("")
$script:L.Add("对照 [docs/06-machine-profile.md](../docs/06-machine-profile.md) 第 9 节三档判据，判断哪些参数能照搬。")

[IO.File]::WriteAllText($Out, ($script:L -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "已写入：$Out" -ForegroundColor Green
