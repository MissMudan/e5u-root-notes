# 从面具 APK 提取补丁组件，并在设备上给 init_boot 打补丁
#
# 用法:
#   .\patch-init-boot.ps1 -Apk "C:\path\Magisk.apk" -InitBoot "backup\init_boot_a.img"
#
# 前提: BL 已解锁、adb 可用、设备已 root（adb shell 可写 /data/local/tmp）
# 产物: .\out\new-boot.img —— 校验后自行 dd 进 init_boot_a / init_boot_b

param(
    [Parameter(Mandatory=$true)][string]$Apk,
    [Parameter(Mandatory=$true)][string]$InitBoot,
    [string]$OutDir = ".\out"
)

$ErrorActionPreference = 'Stop'
$adb = "adb"

if (-not (Test-Path $Apk))      { throw "APK 不存在: $Apk" }
if (-not (Test-Path $InitBoot)) { throw "init_boot 镜像不存在: $InitBoot" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$work = Join-Path $OutDir "patch"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# APK 内路径 -> 落盘名
$map = @{
    'assets/boot_patch.sh'          = 'boot_patch.sh'
    'assets/util_functions.sh'      = 'util_functions.sh'
    'assets/stub.apk'               = 'stub.apk'
    'lib/arm64-v8a/libmagiskboot.so' = 'magiskboot'
    'lib/arm64-v8a/libmagiskinit.so' = 'magiskinit'
    'lib/arm64-v8a/libmagisk.so'     = 'magisk'
    'lib/arm64-v8a/libinit-ld.so'    = 'init-ld'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
try {
    foreach ($k in $map.Keys) {
        $e = $zip.GetEntry($k)
        if (-not $e) { throw "APK 内缺少 $k —— 这个版本的 APK 不适用（老版本无 stub.apk，或结构已变）" }
        $dest = Join-Path $work $map[$k]
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        Write-Host ("extracted {0} -> {1} ({2} bytes)" -f $k, $map[$k], $e.Length)
    }
} finally { $zip.Dispose() }

# 推送到设备
& $adb shell "rm -rf /data/local/tmp/magisk; mkdir -p /data/local/tmp/magisk" | Out-Null
foreach ($f in @('boot_patch.sh','util_functions.sh','stub.apk','magiskboot','magiskinit','magisk','init-ld')) {
    & $adb push (Join-Path $work $f) "/data/local/tmp/magisk/$f" | Out-Null
}
& $adb push $InitBoot /data/local/tmp/magisk/init_boot.img | Out-Null

# 机内打补丁
$cmd = "chmod -R 755 /data/local/tmp/magisk; cd /data/local/tmp/magisk && " +
       "md5sum init_boot.img && " +
       "export BOOTMODE=true KEEPVERITY=true KEEPFORCEENCRYPT=true && " +
       "sh boot_patch.sh init_boot.img"
$log = & $adb shell $cmd 2>&1
$log | ForEach-Object { $_ }

if (-not ($log -match 'Repack to boot image: \[new-boot\.img\]')) {
    throw "补丁未成功，请检查上面日志"
}

# 校验 ramdisk 内容
$ls = & $adb shell "cd /data/local/tmp/magisk && ./magiskboot unpack -h new-boot.img >/dev/null 2>&1; ./magiskboot cpio ramdisk.cpio 'ls'" 2>&1
if (-not ($ls -match 'init')) { throw "校验失败: ramdisk 内没有 init" }
Write-Host "`nramdisk 内容:" -ForegroundColor Cyan
$ls | ForEach-Object { $_ }

# 取回
$final = Join-Path $OutDir "new-boot.img"
& $adb pull /data/local/tmp/magisk/new-boot.img $final | Out-Null
Write-Host "`n产物: $final" -ForegroundColor Green
Write-Host "确认无误后写入双槽:" -ForegroundColor Yellow
Write-Host '  adb shell "dd if=new-boot.img of=/dev/block/by-name/init_boot_a bs=4096 && sync"'
Write-Host '  adb shell "dd if=new-boot.img of=/dev/block/by-name/init_boot_b bs=4096 && sync"'
