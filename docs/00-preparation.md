# 00 · Root 前的准备清单

按顺序逐项确认，**任何一项不满足都不要开始动分区**。

## 零、刷机前先打开开发者选项与 USB 调试（第一件事）

**这一步必须在插线干活之前完成，否则后面全部做不了。** 本项目所有备份、读分区、`reboot`、`dd` 都依赖 adb；adb 不通，就没有任何起点——驱动装好了也读不到分区，因为 `spd_dump` 只能做 BootROM 那一段，日常操作全靠 adb。

操作顺序：

1. 设置 → 关于手机（本机叫"关于掌机"）→ 连续点击**版本号** 7 次，直到提示"您已处于开发者模式"
2. 返回 设置 → 系统 → **开发者选项**
3. 打开 **USB 调试**（USB debugging）
   - 顺手把 **OEM 解锁** 开关也点一下，本机会立刻自动弹回——这不是你操作错了，见第二节，这个现象本身就是"厂商锁死"的第一个证据
4. 插线，手机上弹出"允许 USB 调试吗？"→ 勾选**一律允许使用这台计算机进行调试** → 确定
5. 电脑上验证通道已通：

```powershell
adb devices
# 期望：E5UOP10000F08    device      ← 必须是 device
adb shell getprop ro.build.version.release   # 期望 14
adb shell id                                 # 期望 uid=0(root) context=u:r:su:s0
```

`adb devices` 显示 **`device`** 才算过。出现下面几种情况先解决，别往下走：

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 列表为空 | USB 调试实际没打开，或用的纯充电线 | 确认开关为开、换一根数据线、换主机后置 USB 口 |
| `unauthorized` | 手机上的授权弹窗没点"允许" | 拔插一次，或 `adb kill-server` 后再 `adb devices` 让它重新弹窗 |
| `offline` | adb 服务端卡住 | `adb kill-server` → `adb start-server` |
| 能连但 `adb shell` 报 `closed` | 连接模式是"仅充电" | 下拉通知栏，把 USB 用途改成"传输文件 / MTP" |

两个容易踩的点：

- **本机 `ro.secure=0`，`adb shell` 本来就是 `uid=0`，不需要 `adb root`**。别看到"没有 su"就以为 adb 没 root 权限，这是两件不同的事（见 `04-failed-paths.md`）。
- **解锁完成、恢复出厂、跨版本 OTA、或换一台电脑之后，USB 调试的授权会失效**，需要重新打开开关并重新在手机上点"允许"。所以别急着在流程中途把开发者选项关掉。

## 一、机型与固件核对

先跑一条只读命令把硬件档案采下来，后面所有判断都基于它：

```powershell
pwsh -File .\scripts\collect-profile.ps1 -AdbPath <adb路径> -Out .\my-hw.md
```

采完拿 `my-hw.md` 和 [06-machine-profile.md](06-machine-profile.md) 对照。**若 `ro.board.platform`、`ro.hardware`、构建号三项有任何一项与本文不同，先按 06 的第 14 节判断能不能继续**，不要直接套用本文的分区与偏移。

然后逐项核对：

```powershell
adb shell getprop ro.product.model          # 期望 E5U
adb shell getprop ro.build.display.id       # 记录完整构建号，本项目为 XNM_TF05_V40_E5U_..._20250926_1024
adb shell getprop ro.build.version.release  # 期望 14
adb shell getprop ro.build.ab_update        # true → A/B 设备，要写双槽
adb shell getprop ro.boot.slot_suffix       # 当前槽，本项目为 _a
adb shell "cat /proc/version"               # 内核版本
```

构建号必须记下来写进你的日志。所有偏移（`miscdata` 的 8192、SPL 补丁位置）都绑定在具体固件上，换了构建号就要重新确认。

## 二、先确认厂商路线确实死了

```powershell
adb shell settings get global development_settings_enabled
# 打开 OEM 解锁开关后观察：是否自动弹回
fastboot flashing unlock          # 期望 unknown cmd.
fastboot oem unlock               # 期望 Unlock bootloader fail.
fastboot oem get_unlock_ability   # 期望 Not implement.
```

如果其中任何一条**成功了**，说明这台机器的安全层没这么硬，直接走厂商正规解锁即可，**不要**走 BootROM 漏洞路线——正规解锁更安全。

## 三、软件准备

| 需要的东西 | 说明 |
| --- | --- |
| platform-tools | `adb` / `fastboot`。本项目用 fastboot 37.0.1 |
| **官方 SPD 驱动** | `SPD_Driver_R4.20.4201`，含 `sprdvcom.inf`(79KB)、`sprdadb.inf`、`rdavcom.inf`、`sprdvmdm.inf`，DriverVer `10/14/2020,4.20.42.134` |
| `spd_dump` | 来自 `TomKing062/spreadtrum_flash`，只走 Channel9/COM，无 libusb 回退 |
| `fdl1-dl.bin` / `fdl2-dl.bin` | 随解锁工具包提供，用于引导下载模式 |
| `fdl2-cboot.bin` | 同上，用于在 SPL 被擦后接管启动 |
| `gen_spl-unlock` | 生成 `spl-unlock.bin`，**必须针对本机 SPL** |
| 对应机型解锁包 | 本项目为 `ums9230_universal_unlock_UFS.zip`（UFS 存储版本） |
| PowerShell 7 | 本项目所有脚本按 pwsh 写 |

**不要**用 2015 版通用 VCOM 驱动（Provider 为 "DriverCoding Corporation" 的 `sprdvcom.inf`）。它能枚举出 `SPRD U2S Diag (COMx)` 且设备管理器显示正常，但 `spd_dump` 会稳定报 `usb_send failed (0 / 1)`。判断标准就看 INF 里有没有 `SprdVendorRequest=1`。

## 四、数据与备份（关键）

**这一步做不好，后面全白搭。** 前提是本机 `adb shell` 已经是 root（`ro.secure=0` 的机器直接满足；若不是，先确认能否 `adb root`）。

先用 `adb shell id` 确认是 `uid=0`，然后逐个拉分区：

```powershell
adb shell "mkdir -p /sdcard/bk"
foreach ($p in @('boot_a','init_boot_a','vbmeta_a','dtbo_a','vendor_boot_a','uboot_a','misc','miscdata','metadata','prodnv')) {
  adb shell "dd if=/dev/block/by-name/$p of=/sdcard/bk/$p.img"
  adb pull "/sdcard/bk/$p.img" "backup\$p.img"
}
```

必须记录每个文件的 MD5 与大小。本项目参考值：

| 分区 | 大小 | MD5 |
| --- | --- | --- |
| `boot_a` | 67108864 | `DF64D765…92690` |
| `init_boot_a` | 8388608 | `9B448C59…99155` |
| `vbmeta_a` | 1048576 | `18D61FBD…30FE` |
| `dtbo_a` | — | `86582EDE…F8689` |
| `uboot_a` | 3145728 | `59FE195E…CDF654` |
| `vendor_boot_a` | 104857600 | `7A1084B2…F5BA6` |

`boot`/`init_boot`/`vbmeta` 的 `_b` 槽与本机 `_a` 内容相同，也一并拉一份。

**另外两样比任何备份都重要**——原始 SPL 与 uboot：

```
splloader.bin   262144 字节
uboot.bin       3145728 字节
```

这两个文件是"设备唯一不可再生的还原源"。SPL 一旦擦掉又没有备份，就只能靠厂商救砖固件恢复。

### 4.1 先进的一步：SPL 其实能在 adb 下直接备份（本机已验证）

原流程是"进 BootROM 才拿到 SPL"。补采档案时实测发现**不用**——SPl 的 A/B 两槽在本机各是一块独立块设备，`adb` 有 root 就能直读，比进 BootROM 安全得多：

```bash
adb shell "dd if=/dev/block/sdb of=/sdcard/bk/spl_a.bin bs=1024 count=256"
adb shell "dd if=/dev/block/sdc of=/sdcard/bk/spl_b.bin bs=1024 count=256"
adb pull "/sdcard/bk/spl_a.bin" "backup\spl_a.bin"
adb pull "/sdcard/bk/spl_b.bin" "backup\spl_b.bin"
adb shell "md5sum /sdcard/bk/spl_a.bin /sdcard/bk/spl_b.bin"
```

本机实测三份完全一致，可作校验基准：

| 来源 | 大小 | MD5 |
| --- | --- | --- |
| `/dev/block/sdb`（A 槽 `spl_a`） | 262144 | `75EF4A02E1B92CC9712B1488AAC992E0` |
| `/dev/block/sdc`（B 槽 `spl_b`） | 262144 | `75EF4A02E1B92CC9712B1488AAC992E0` |
| 原经 BootROM 读出的 `splloader.bin` | 262144 | `75EF4A02E1B92CC9712B1488AAC992E0` |

先确认文件头是 `44 48 54 42`（`DHTB`，展锐下载头），再核对 MD5。`uboot_a` 同理可直接 `md5sum /dev/block/by-name/uboot_a`（本机 `59FE195EB9B3C743D30DED1397CDF654`）。

**顺序建议**：先按 4.1 用 adb 拿到 SPL+uboot 并校验，再进 BootROM 走阶段 1 读出同一份做二次确认。两边的 MD5 相同，说明通道和备份都可信，可以放心往下擦。

**限制**：这条路径要求 adb 有 root（本机 `ro.secure=0` 天然满足；若 `ro.secure=1` 需先 `adb root` 成功），否则仍以 BootROM 读取为准。设备上 `spl_a`/`spl_b` 的落点因机型而异，动手前先 `ls -l /dev/block/by-name/spl_a /dev/block/by-name/spl_b` 确认，**不要**默认就是 `sdb`/`sdc`。详见 [06-machine-profile.md](06-machine-profile.md) 第七节。

## 五、物理条件

- **电量**：50% 以上。低电量时 USB 0.5A 充不进去，会出现"整机无反应"的假象
- **线缆**：直插主机后置 USB 口，不要用 HUB、不要用延长线、不要用前置面板
- **按键**：关机后**同时按住音量加 + 音量减**，保持按住再插线，继续按住**约 10 秒**端口就出来（不必按到二三十秒）。只按一个或先插线都进不去
- **端口观察**：`Get-PnpDevice -PresentOnly | Where InstanceId -match 'VID_1782'`，PID 应为 `4D00`

## 六、心理准备与风险确认

需要明确同意的几点：

1. **所有用户数据会被清掉**（`misc` 擦除 + 解锁流程本身）
2. **BL 解锁后 Play Integrity 直落**，部分银行、支付、游戏反作弊应用会拒绝运行，且 `verifiedbootstate` 永远是 `orange`
3. **有变砖可能**。可控的失败模式是"只能停在 BootROM"，只要还能进下载模式就能救；不可控的是"没备份就擦了两槽且手头无救砖固件"
4. 解锁后**不要直接升 OTA**，会覆盖 root 补丁

## 七、开工前的最后自检

```
[ ] 开发者选项已开启（版本号连点 7 次）
[ ] USB 调试已打开，电脑已授权，adb devices 显示 device  ← 不通就别往下
[ ] 硬件档案已采集并与 docs/06 对照，平台/硬件标识/构建号确认一致
[ ] 构建号已记录
[ ] 厂商解锁路线已确认走不通
[ ] 官方 SPD 驱动已装（INF 有 SprdVendorRequest=1）
[ ] spd_dump 能读到 splloader/uboot 且大小正确  ← 这一步不通，后面一步都别做
[ ] 关键分区已备份且 MD5 校验通过
[ ] 能稳定进入 BootROM（端口出现）
[ ] 电量 > 50%，线缆直插后置口
[ ] 已接受数据清空与变砖风险
```
