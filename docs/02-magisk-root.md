# 02 · Root：headless 打补丁与面具切换

Android 12+ 的 `init_boot` 是 boot header v4、`kernel_size=0` 的纯 ramdisk 分区，Magisk 官方 wiki 也明确这一代 **boot 不再需要签名**，`patch with magisk and write back` 即可。

但注意：**绝不能重签 vbmeta**（除非有 unisoc 公钥或走 38691/38692 分支）。

## 为什么不用手机 GUI

面具 app 的"安装 → 选择并修补文件"需要在掌机小屏上点六七下。更稳的方式是直接调用 APK 自带的官方脚本 `boot_patch.sh`，在设备上以 root 执行——完全可脚本化、可复现。

## 步骤

### 1. 备份

```powershell
adb shell "dd if=/dev/block/by-name/init_boot_a of=/sdcard/init_boot_a.img"
adb pull /sdcard/init_boot_a.img backup\init_boot_a.img
```

本机原厂 `init_boot` 为 8MB，MD5 `9B448C597C32A6D49BE9908B9F199155`（`_a` 与 `_b` 完全相同）。

### 2. 从面具 APK 里提取补丁组件

用 `scripts/patch-init-boot.ps1` 一条命令完成，等价于手工解包并重命名：

| APK 内路径 | 落盘名 | 作用 |
| --- | --- | --- |
| `assets/boot_patch.sh` | `boot_patch.sh` | 补丁主脚本 |
| `assets/util_functions.sh` | `util_functions.sh` | 工具函数 |
| `assets/stub.apk` | `stub.apk` | 用于嵌入 ramdisk 的 stub（新版本需要） |
| `lib/arm64-v8a/libmagiskboot.so` | `magiskboot` | 镜像解包/重打包 |
| `lib/arm64-v8a/libmagiskinit.so` | `magiskinit` | 替换 /init 的二进制 |
| `lib/arm64-v8a/libmagisk.so` | `magisk` | 主体 |
| `lib/arm64-v8a/libinit-ld.so` | `init-ld` | /init 的 LD_PRELOAD 库 |

> 早期 Magisk（如 31.1）不需要 `stub.apk`，新版（如 Kitsune 30.7）需要。缺文件时脚本会在 `magiskboot compress=xz stub.apk` 处报错。

### 3. 机内打补丁

```powershell
adb push .\patch\* /data/local/tmp/magisk/
adb push backup\init_boot_a.img /data/local/tmp/magisk/init_boot.img
adb shell "chmod -R 755 /data/local/tmp/magisk; cd /data/local/tmp/magisk && \
  export BOOTMODE=true KEEPVERITY=true KEEPFORCEENCRYPT=true && \
  sh boot_patch.sh init_boot.img"
```

关键环境变量：

- `BOOTMODE=true` — 让脚本走"已开机"路径，会自行查询 `PREINITDEVICE`（本机解析出 `cache`）
- `KEEPVERITY=true` / `KEEPFORCEENCRYPT=true` — 保留原机的 verity 与强制加密标记，避免动到 fstab

**务必喂原厂镜像**。给已打过补丁的镜像，脚本虽然能识别（`cpio test` 返回 1）并先 `restore`，但多次来回容易叠加出错。手上有原厂镜像就永远用原厂。

正常输出尾部：

```
Patch with flag KEEPVERITY=[true] KEEPFORCEENCRYPT=[true]
Backup [init] -> [.backup/init.xz]
Repack to boot image: [new-boot.img]
RAMDISK_SZ [1948031]
```

### 4. 校验再刷

```powershell
adb shell "cd /data/local/tmp/magisk && ./magiskboot unpack -h new-boot.img && ./magiskboot cpio ramdisk.cpio 'ls'"
```

ramdisk 里必须能看到：`init`（约 200KB，就是 magiskinit）、`overlay.d`、`.backup`。

确认无误再写双槽：

```powershell
adb shell "cd /data/local/tmp/magisk && \
  dd if=new-boot.img of=/dev/block/by-name/init_boot_a bs=4096 && \
  dd if=new-boot.img of=/dev/block/by-name/init_boot_b bs=4096 && sync"
adb reboot
```

**两个槽都写**，否则 OTA 或切槽后 root 消失。

### 5. 验证

```
adb shell "/debug_ramdisk/magisk -v"      → 31.1:MAGISK:R  或  46f5f839-kitsune:MAGISK:R
adb shell "/debug_ramdisk/su -c id"        → uid=0(root) context=u:r:magisk:s0
adb shell "ps -A | grep magisk"            → root <pid> ... magiskd
```

`/debug_ramdisk` 下正常应有 `magisk`、`magiskinit`、以及 `su` / `resetprop` / `supolicy` 三个软链。

注意：`su` **不在 adb shell 的默认 PATH 里**，直接敲 `su` 会 `inaccessible or not found`，要用全路径 `/debug_ramdisk/su`。

## 图形界面路径（推荐给下一个人，两种情形别搞混）

上面第 2–4 步是"没有 root 时"的做法（headless）。如果接手的人更愿意在手机上点，就按下面走，**关键区别是"有没有现成的 root"**：

### 情形 A · 还没有 root（首次拿 root）

装 APK **不需要 root**，先在系统里装好，再让 App 自己产出补丁镜像：

1. `adb install -r Kitsune_30.7_140326.apk`（本仓库 Release 附件，SHA256 见 [tools/magisk-307-NOTES.md](../tools/magisk-307-NOTES.md)）
2. 把**原厂** `init_boot.img` 推到 `/sdcard/Download/`
3. 打开面具 → 主页「安装」→ 选 **「选择并修补一个文件」** → 选 `init_boot.img`
4. 输出在 `/sdcard/Download/magisk_patched-30700_xxxxx.img`，`adb pull` 回电脑
5. 刷双槽（这一步必须 fastboot 或 dd，App 写不了自己的分区）：

```powershell
adb reboot bootloader
fastboot flash init_boot magisk_patched-30700_xxxxx.img --slot all
fastboot reboot
```

6. 重启后打开面具，主页显示版本号即成功；`adb shell "/debug_ramdisk/su -c id"` 应返回 `uid=0 … context=u:r:magisk:s0`

### 情形 B · 已经有 root（换面具或升级）

如果设备上已经有 Magisk（本项目当初是 31.1）在跑，装 Kitsune 后**不用再碰 fastboot**：

1. 先用旧面具 App 确认 root 正常
2. 装 Kitsune APK（包名 `io.github.x0eg0.magisk`，与 `com.topjohnwu.magisk` 不同，可共存安装）
3. 打开 Kitsune → 「安装」→ 选 **「直接安装（推荐）」** → App 自己重打补丁并写入 `init_boot`
4. 重启 → `magisk -v` 变成 `46f5f839-kitsune:MAGISK:R` 即接管成功
5. **确认接管成功后再卸载旧面具**，顺序反了会两个 daemon 抢同一个 `magiskd`

⚠️ 两种情形都别做的事：给已经打过补丁的镜像再打一次补丁；同时装两个面具并都执行"直接安装"。

## 从 Magisk 换到 Kitsune Mask

Kitsune 是 Magisk 的分支，包名不同（本机用的第三方接续版本为 `io.github.x0eg0.magisk`），两者**不能同时装**，否则两套 app 抢同一个 `magiskd`。

切换步骤：

1. 用新面具 APK 里的组件重跑一遍第 3 步（`boot_patch.sh` 会识别旧补丁并 restore 后再打）
2. 校验、写双槽、重启
3. `magisk -v` 变成新版本串即接管成功
4. 卸载旧面具 app

本机三个可回滚镜像：

| 文件 | 来源 | MD5 |
| --- | --- | --- |
| `init_boot_a.img` | 原厂 | `9B448C59…155` |
| `init_boot_magisk.img` | Magisk 31.1 补丁 | `D81ACBF0…A55` |
| `init_boot_kitsune307.img` | Kitsune 30.7 补丁 | `926F0863…61D` |

## 回滚

BL 已解锁，fastboot 直接可写，这是最快的救援通道（已在真机确认设备能枚举出 `E5UOP10000F08 fastboot`）：

```powershell
adb reboot bootloader
fastboot flash init_boot backup\init_boot_a.img    # 回原厂
fastboot reboot
```

若系统还能进，也可以 `dd`：

```powershell
adb shell "dd if=/sdcard/init_boot_a.img of=/dev/block/by-name/init_boot_a bs=4096 && sync"
```
