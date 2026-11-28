# 01 · Bootloader 解锁（CVE-2022-38694 / 展锐 BootROM）

厂商在 TEE 里做了软件层的 OEM 解锁开关，且 fastboot 侧被裁剪，最终走的是展锐 BootROM 的下载模式漏洞。

## 1. 先确认厂商路线是死的

这些都在真机上试过，全部失败（细节见 `04-failed-paths.md`）：

- 开发者选项里"OEM 解锁"开关打开后**立即自动弹回**，写入方是 TEE 里的 `vendor.sprd.hardware.oemlock-service` + `oemlock_ca.so`
- `fastboot flashing unlock` → `unknown cmd.`
- `fastboot oem unlock` → `Unlock bootloader fail.`
- `fastboot flashing unlock_bootloader` → 需要厂商 `rsa4096_vbmeta` 私钥签名的 `certificate.bin`，主机 fastboot 37.0.1 直接拦掉该非标准命令
- `fastboot oem edl` / `oem reboot-edl` / `oem download` → 全部 `unknown cmd.`，**无法从 fastboot 跳下载模式**
- `adb shell reboot edl` → 只是普通重启

结论：只能物理按键进 BootROM。

## 2. 驱动：整条路线的真正卡点

这是最容易卡住、也最容易被误判为"工具不支持此机型"的地方。

**不要用**网上流传的 2015 版通用 VCOM 驱动（如 `SPRD_NPI_USBDriver_1.4` 里的 `sprdvcom.inf`，Provider 为 "DriverCoding Corporation"）。装它之后设备能正常枚举成 `SPRD U2S Diag (COMx)`，`Get-PnpDevice` 也显示 Status OK，但 `spd_dump` 一律在首包就报：

```
Successfully connected to port: 5
usb_send failed (0 / 1)
```

**要用**展锐官方 `SPD_Driver_R4.20.4201`（DriverVer `10/14/2020,4.20.42.134`，含 `sprdvcom.inf` 79KB + `sprdadb.inf` + `rdavcom.inf` + `sprdvmdm.inf`）。区别在于它 INF 里的 `SprdVendorRequest=1`，即由驱动自己实现展锐厂商请求——这才是 `spd_dump` 的通道库需要的东西。装完立刻通，第一次就能读到 `splloader`(262144B) 和 `uboot_a`(3145728B)。

配套设置：用驱动包自带的 `config.reg` 写入 `UsbFlags\IgnoreHWSerNum17824D00` 等项，避免 COM 口号随插拔漂移。

**另一个高频坑**：`spd_dump` 每条命令执行完会停在 `Press any key` 或 `FDL2 >` 提示并继续占用 COM 口，下一条命令会报 `Access denied`。每步之间必须：

```powershell
Get-Process spd_dump -ErrorAction SilentlyContinue | Stop-Process -Force
```

## 3. 进入 BootROM

**先关机，然后两个音量键必须同时按住，端口才会出来。** 只按其中一个、或者先插线再按键，都进不去。

```
关机（长按电源 15–20 秒强制断电，确认屏幕全黑、无震动）
→ 同时按住「音量加」+「音量减」，两个键都别松
→ 保持按住的状态插上 USB 线
→ 继续按住约 10 秒，端口就出来了（10 秒左右即可，不必按到二三十秒；没出现就继续按住等）
```

设备枚举为 `USB\VID_1782&PID_4D00`，驱动正确时装好即为 `SPRD U2S Diag (COMx)`。

按住时长不需要很久：实测**约 10 秒**端口就出现，按到 20–30 秒属于多余的等待。

这是本机**唯一**可靠的进入方式：`adb shell reboot edl` 只会普通重启进 Android，`adb reboot bootloader` 进的是 fastboot 也不是下载模式，而 fastboot 侧 `oem edl` 之类命令全部 `unknown cmd.`。

注意部分机器**上电会自己继续启动**，端口只存在几十秒就消失；也遇到过电池被放干、电脑 USB 0.5A 充不进去、整机毫无反应的情况，先充一段时间再来。

## 4. 解锁流程（顺序不能错）

在装有工具的目录下逐条执行，每条之间清掉 `spd_dump` 进程。

**步骤 A — 备份关键分区**

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec r splloader r uboot reset
```

产出 `splloader.bin`(262144B) 与 `uboot.bin`(3145728B)。这两个是后面还原的命根子，**务必确认文件大小正常再往下走**。

> 如果 adb 有 root，`uboot` 也可以直接 `dd /dev/block/by-name/uboot_a` 拿到（本机落点 `sda8`，MD5 `59FE195E…CDF654`，与 BootROM 读出的完全一致），详见 [00-preparation.md 第 4.2 节](00-preparation.md)。两种途径产物等价，`uboot.bin` / `uboot_orig.bin` / `uboot_a.img` 是同一份文件的三种叫法。

**步骤 B — 擦除两槽 SPL + 写入 cboot**

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec r splloader r uboot e splloader e splloader_bak w uboot fdl2-cboot.bin reset
```

**这一步是全流程的分界点**，也是最容易搞错的地方：必须先 `e splloader`、`e splloader_bak` 擦掉两槽 SPL，设备才无法启动、稳定停在 BootROM。

第一次操作时若漏掉擦除，机器会正常开机，SPL 校验失败自动回落到 `uboot_b` 的原版镜像，`flash.locked` 依然为 1 —— 很容易误判成"流程无效"或"装机成了砖"。

**步骤 C — 执行解锁载荷**

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl spl-unlock.bin 0x65000800
```

正常输出到 `EXEC FDL1` 后会出现 `CHECK_BAUD FAIL` 与 `device removed`，**这是预期行为，不是失败**。

**步骤 D — 检查解锁标志**

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec read_part miscdata 8192 64 m.bin
```

这条**不要带 `reset`**，否则还没读出文件设备就复位了。执行完会停在 `FDL2 >`，先 `Stop-Process` 再读文件。

判定标准（64 字节，取 `miscdata` 偏移 8192）：

- 全 0 → 未解锁
- `32 字节哈希 + 16 字节 + 16 字节`（后两段通常相同），零字节 0/64 → **已解锁**

本机实测：

```
BF02A9C1B61B057D 2060F4A3C4478AE3 81C20C575CDE1A57 ABDDA21E52B6E9F6
04181A271ECA0A53 24117FD7427D516A   ← 此段重复两遍
```

ASCII 视图是乱码哈希，属正常。

**步骤 E — 还原分区并复位**

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec w splloader splloader.bin w uboot uboot.bin w misc misc-wipe.bin reset
```

（`uboot.bin` 就是步骤 A 备份的那份，早期笔记里写作 `uboot_orig.bin`，同一个文件。成功判据是 `Write Part Done: uboot_a, target: 0x300000`。）

写 66152B 的裁剪版 SPL 到 256KB 区域时，工具会按目标分区大小补齐（日志显示 `file size: 0x40000`），`Write Part Done: splloader, target: 0x40000, written: 0x40000` 即为成功。SPL 镜像真实长度在 DHTB 头里，尾部补零不影响启动。

`reset` 之后设备不一定会自动上电，**手动长按电源 3–5 秒开机**。

## 5. 验证

```
ro.boot.flash.locked      = 0
ro.boot.verifiedbootstate = orange
ro.boot.vbmeta.device_state = unlocked
```

三条同时成立才算真解锁。`miscdata` 里那 64 字节在重启后依然保留，标志是固化的。

## 6. 关于 `spl-unlock.bin` 是怎么来的

`gen_spl-unlock` 的行为（源码见身体分支 `info/gen_spl-unlock.c`）：

1. 把 SPL 裁剪到真实镜像长度（从 DHTB 头部 `0x30` 处长度字段推导，本机 `0x10268` = 66152B）
2. 扫描 `0x34000060` / `0x940000xx` / `0x5280` 特征并 NOP 掉签名校验调用
3. 输出打补丁的 `spl-unlock.bin`

而同名的 `<filename>` 输出被裁剪但**不打补丁**——也就是原脚本里改名成 `u-boot-spl-16k-sign.bin` 的那份，用于最后写回分区。

本机实测差异只有一处：偏移 `0xB25C` 处 8 字节由

```
D2 00 00 94 60 00 00 34     (BL + CBZ，校验调用)
```

变为

```
1F 20 03 D5 1F 20 03 D5     (双 NOP)
```

说明补丁正确适配了本机固件。
