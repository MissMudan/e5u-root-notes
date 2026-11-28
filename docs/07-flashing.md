# 07 · 刷写操作手册（fastboot / dd / 刷 GSI）

> 前面 01、02、05 讲的是"这条路线怎么走通"，这一篇讲的是**具体怎么刷、刷错怎么退**。
> 只写这台机器实测过的命令与判据；没验证过的一律标注。

## 1 · 前提

| 项 | 要求 |
| --- | --- |
| BL 状态 | 已解锁：`ro.boot.flash.locked=0`、`verifiedbootstate=orange`、`vbmeta.device_state=unlocked` |
| fastboot 版本 | 本项目用 **37.0.1**（platform-tools 自带）。老版本对 `--slot all`、fastbootd 支持不全 |
| 驱动 | `adb` 用 ADB 驱动、`fastboot` 用同一套 USB 通道；**不需要** SPD VCOM 驱动（那是 BootROM 模式用的） |
| 设备可见 | `fastboot devices` 应输出 `E5UOP10000F08  fastboot` |
| 电量 | 50% 以上（本机充电电流上限只有 500mA，边刷边充不现实） |

进 fastboot：`adb reboot bootloader`。关机后按住音量减再插线一般也能进，但本机实测可靠的是 `adb reboot bootloader`。

## 2 · 三条刷写通道，别用错

| 通道 | 能写什么 | 前提 | 本项目用在哪 |
| --- | --- | --- | --- |
| **adb `dd`** | 任何 `/dev/block/by-name/*` 分区 | adb 有 root（本机 `ro.secure=0` 天然满足） | 备份分区、写 `init_boot` 双槽、读 SPL/uboot |
| **fastboot** | boot/init_boot/vbmeta/dtbo/vendor_boot、fastbootd 下的逻辑分区 | BL 已解锁 | 刷补丁镜像、回滚、刷 GSI |
| **BootROM（spd_dump）** | `splloader`、`uboot`、`misc`、`miscdata` 等底层区 | 关机 + 音量加&减 + 官方 SPD 驱动 | 解锁流程（01 篇），日常刷机**不用** |

**日常换 root、回滚、刷 GSI 都走 fastboot 或 adb dd，不需要再进 BootROM。**

## 3 · A/B 规则（这台机器最容易踩的地方）

设备是 A/B（`ro.build.ab_update=true`），当前槽 `_a`。

- **刷 `init_boot` / `boot` 必须两槽都刷**，否则切槽或 OTA 后 root 消失。
- 两种等价写法：

```powershell
fastboot flash init_boot new-boot.img --slot all
# 或
fastboot --slot=all flash init_boot new-boot.img
```

- 只刷当前槽（不推荐，仅临时试验）：`fastboot flash init_boot new-boot.img`（默认写当前槽 `_a`）。
- 查当前槽：`fastboot getvar current-slot` → `current-slot: a`。
- 切换槽：`fastboot set_active b`（**谨慎**，切到没有补丁的槽会失去 root，切到没有系统的槽可能不开机）。

## 4 · 常用命令速查

```powershell
# 状态
fastboot devices
fastboot getvar current-slot
fastboot getvar all                     # 本机部分变量返回 unknown，正常

# 刷单个分区
fastboot flash init_boot backup\init_boot_kitsune307.img --slot all
fastboot flash boot     backup\boot_a.img --slot all
fastboot flash vbmeta   backup\vbmeta_a.img --slot all

# 擦除（慎用，擦前必须有备份）
fastboot erase init_boot

# 重启
fastboot reboot
fastboot reboot bootloader
fastboot reboot fastboot                # 进 fastbootd（刷 GSI 必需）
```

**本机没有的**：`fastboot flashall`（快照包）、`fastboot update`（官方 OTA 包）。厂商没给整包，所以**不存在"一键刷回原厂"**这条路，回滚只能靠自己的备份。

## 5 · 展锐 fastboot 的怪脾气（实测）

| 现象 | 含义 | 处理 |
| --- | --- | --- |
| `fastboot flashing unlock` → `unknown cmd.` | 厂商删掉了标准解锁命令 | 这是正常的，走 01 篇的 BootROM 路线 |
| `fastboot oem unlock` → `Unlock bootloader fail.` | 同上，命令存在但被安全层拒绝 | 同上 |
| `fastboot flashing get_unlock_ability` → `Not implement.` | 没实现 | 同上 |
| `fastboot reboot` 打印 `unknown status code` 后设备仍重启 | 返回码不合规但动作执行了 | 忽略，看设备是否真的重启 |
| `fastboot getvar all` 大量 `unknown` | 精简版 bootloader | 只用 `current-slot`、`max-download-size` 这几个可信的 |
| 刷完立刻断电/拔线 | 可能写一半 | 一定等 `Finished.` 或 `OKAY` 再操作 |

## 6 · 三类典型任务

### 6.1 换 root 镜像（最常用）

```powershell
adb reboot bootloader
fastboot flash init_boot backup\init_boot_kitsune307.img --slot all
fastboot reboot
```

验证：

```powershell
adb shell "/debug_ramdisk/magisk -v"      # 期望 46f5f839-kitsune:MAGISK:R
adb shell "/debug_ramdisk/su -c id"       # 期望 uid=0 … context=u:r:magisk:s0
```

### 6.2 回滚到原厂

```powershell
adb reboot bootloader
fastboot flash init_boot backup\init_boot_a.img --slot all
fastboot reboot
```

本机可回滚镜像与 MD5：

| 文件 | 来源 | MD5 |
| --- | --- | --- |
| `init_boot_a.img` | 原厂 | `9B448C59…99155` |
| `init_boot_magisk.img` | Magisk 31.1 补丁 | `D81ACBF0…A55` |
| `init_boot_kitsune307.img` | Kitsune 30.7 补丁 | `926F0863…61D` |

回原厂 `init_boot` 后 root 消失，但 BL 仍是解锁状态，Play Integrity 依然过不了——**回滚 root ≠ 恢复安全状态**。

### 6.3 刷 GSI（可选，风险最高）

前提：Treble 合规（本机 `ro.treble.enabled=true`）、A/B、动态分区。

```powershell
adb reboot bootloader
fastboot reboot fastboot                  # 必须进 fastbootd，普通 bootloader 不能刷逻辑分区
fastboot delete-logical-partition product_a   # 空间不够时才做，删前确认备份
fastboot flash system gsi-arm64-ab.img
fastboot -w
fastboot reboot
```

**这台机器的硬约束**：`super` 只有 **5,872,025,600 字节（5.47GiB）**，A/B 两套各占一半，`/vendor` 已占 681M、`/product` 占 0.9G。GSI 常见 2–3GB，很可能塞不进当前槽——要么先删 `product_a`，要么只刷单槽。

风险：相机、WiFi、蓝牙、RIL 依赖展锐闭源 HAL，GSI 下大概率失效；触控与手柄（vendor 内核提供 input 设备）通常还能用。详见 README 对第三方 ROM 的说明。

**刷 GSI 前必须做的备份**（没有原厂包，这是唯一退路）：

```powershell
adb shell "dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4M"
adb pull /sdcard/super.img backup\super.img      # 约 5.5GB，确认空间够
```

回滚：`fastboot flash super backup\super.img`（部分机型需 `fastboot flash super` 在 fastbootd 下执行）。

## 7 · 危险操作清单

1. **不要重签 vbmeta**（除非有 unisoc 私钥或走 38691/38692 分支），会直接不开机。
2. **不要在 BL 锁定状态刷打过补丁的 `boot` / `init_boot`**：uboot 会校验，表现为"刷完不开机"。
3. **不要只刷一个槽**就以为完事（OTA、切槽都会把 root 弄丢）。
4. **不要在没备份 `super` 的情况下刷 GSI**。
5. **不要擦 `miscdata`**：解锁标志就在里面（偏移 8192 的 64 字节），擦掉等于回到未解锁。
6. **不要用 `fastboot flashall` / `fastboot update`**：本机没有对应整包，命令也不支持。
7. **刷完不要立刻拔线**，等 `Finished.`。

## 8 · 失败怎么退（按现象查）

| 现象 | 可能原因 | 退路 |
| --- | --- | --- |
| `fastboot devices` 为空 | 没进 fastboot、线是纯充电线、驱动没装 | 重进 bootloader；换线换口；装 ADB 驱动 |
| `fastboot flash` 卡住不动 | 镜像太大或分区只读 | 检查镜像大小、确认 BL 已解锁 |
| 刷完开机卡 logo | 镜像与固件不匹配 / vbmeta 校验 | 进 fastboot 刷回原厂对应分区 |
| 完全不开机、只能见 BootROM 端口 | system/boot 损坏 | 进 BootROM 用 `spd_dump` 还原 SPL/uboot/misc（见 01 篇阶段 7） |
| 开机进 recovery 报 `Cannot load Android system` | 数据与系统不匹配 | `fastboot -w`（会清数据），再不行刷回备份 |
| root 不见了但系统正常 | 刷了单槽或 OTA 覆盖 | 重新刷 `init_boot` 双槽 |

**最坏情况的救砖顺序**：能进 fastboot → 用备份镜像逐个分区刷回；连 fastboot 都进不去但能见 BootROM 端口 → 走 01 篇的 `spd_dump` 还原流程（这也是当初为什么必须先备份 SPL 和 uboot）。

## 9 · 和本文档其他章节的关系

```
00-preparation   开工条件与备份（含 SPL/uboot 的 adb 直读）
01-bootloader-unlock   BootROM 解锁（唯一会动 SPL 的地方）
02-magisk-root    打 init_boot 补丁（headless 与 GUI 两条路）
05-full-flow      端到端 10 阶段
07-flashing       本文：日常刷写、A/B 规则、回滚、刷 GSI
04-failed-paths   已验证走不通的路
```
