# GAMEMT E5 Ultra (UMS9230) 解锁 BL 与 Root 全记录

> **⚠️ 本项目全程由 AI 操作完成。**
> 从驱动排查、BootROM 解锁、`init_boot` 打补丁到性能调度脚本，所有命令均由 AI 在真实设备上规划并执行，人类只负责物理操作（按键进 BootROM、插拔线缆）与授权。文中数据、日志、失败记录都是这台机器的实测结果，不是从教程里转述。请把它当作一份 AI 实操记录来读，而不是人工精调后的权威手册——照做之前请自行核对每一处风险。

一台国产开源掌机 **GAMEMT / 漫特科技 E5 Ultra（型号 E5U，6GB+128GB，紫光展锐虎贲 T620 / UMS9230，Android 14）** 从"厂商锁死 Bootloader"到"完整 root + 可调性能调度"的完整过程记录。

所有步骤都在这台真机上跑通并留下了可复现的数据判据，`artifacts/` 里是当时产生的原始日志与取证文件。


## 最终结果

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| Bootloader | 已解锁 | `ro.boot.flash.locked=0`、`ro.boot.verifiedbootstate=orange`、`ro.boot.vbmeta.device_state=unlocked` |
| Root | Kitsune Mask 30.7 接管 | `magisk -v` → `46f5f839-kitsune:MAGISK:R`，`su` → `uid=0 context=u:r:magisk:s0` |
| 双槽 `init_boot` | 均已刷入补丁镜像 | `_a` / `_b` 回读 MD5 一致（`926f0863…`） |
| 性能调度 | 可切换，默认回原厂 | `/data/adb/perfctl.sh` 提供 stock / mid / perf / turbo 四档 |

## 设备与环境

```
机型        GAMEMT E5 Ultra (E5U)          SoC     Unisoc UMS9230 / 虎贲 T620
配置        6GB + 128GB                     CPU     2×Cortex-A75 2.21GHz + 6×Cortex-A55 1.82GHz
系统        Android 14 (SDK 34)              GPU     Mali-G57 MP1 (384–850MHz)
内核        5.15.123-android13-8-00033-g39606e3309fc-ab10974680
构建号      XNM_TF05_V40_E5U_00_A_FL_ZX_42_6X128_720X1280_V1.0_20250926_1024
分区        A/B（`ro.build.ab_update=true`），当前 `_a`
```

关键前提：**`adb shell` 本身已经是 root**（`ro.secure=0`，`uid=0 context=u:r:su:s0`），能自由 `dd` 分区，但应用层拿不到 `su`。这大幅降低了救砖难度，也让"先手工备份全部关键分区"成为可能。

## 路线总览

```
厂商安全层锁死
   └─ 转向 BootROM 漏洞（CVE-2022-38694）
        ├─ 装对驱动（这一步是整条路线的真正卡点）
        ├─ 擦除两槽 SPL → 强制停在 BootROM
        ├─ 写入 cboot → 执行 spl-unlock 载荷 → 解锁标志落盘
        ├─ 还原 SPL / uboot / misc → 正常开机，flash.locked 变 0
        └─ 打 init_boot 补丁 → 刷双槽 → root
```

## 文档

- [docs/01-bootloader-unlock.md](docs/01-bootloader-unlock.md) — BootROM 解锁全过程，含驱动踩坑与判据
- [docs/02-magisk-root.md](docs/02-magisk-root.md) — 不依赖手机 GUI 的 headless 打补丁流程、换面具、回滚
- [docs/03-perf-tuning.md](docs/03-perf-tuning.md) — UMS9230 的调频结构与四档脚本说明
- [docs/04-failed-paths.md](docs/04-failed-paths.md) — 已验证走不通的路，避免后来者重复劳动

## 脚本与过程文件

```
scripts/    可直接复用的脚本（调频切换、开机自动应用、headless 打补丁）
tools/      本次排查过程中写的 PowerShell 小工具（驱动安装、端口监视、SPL 比对等）
artifacts/  实测日志、分区表、解锁标志样本
```

- [scripts/perfctl.sh](scripts/perfctl.sh) — 调频档位切换（需要 root）
- [scripts/e5u_perf.sh](scripts/e5u_perf.sh) — Magisk `service.d` 开机自动恢复档位
- [scripts/patch-init-boot.ps1](scripts/patch-init-boot.ps1) — 从面具 APK 里自动提取组件、在机内打 `init_boot` 补丁
- [tools/](tools/) — `install-sprd-driver*.ps1`（驱动安装）、`port-probe.ps1` / `usb-monitor.ps1`（端口监视）、`diff-spl.ps1`（补丁差异比对）、`show-m.bin.ps1`（解锁标志解析）
- [artifacts/](artifacts/) — 每一步 `spd_dump` 的原始日志、70 分区表、`miscdata` 解锁标志样本；厂商固件与第三方二进制**一律未包含**，说明见 [artifacts/README.md](artifacts/README.md)


## 免责声明

**这会拆掉设备的所有安全边界**：BL 解锁后 `verifiedbootstate` 变 `orange`，Play Integrity 直落到底，部分银行、支付、游戏反作弊类应用会拒绝运行；设备被远程/物理接触后攻击面显著变大。

解锁过程涉及 BootROM 下载模式与分区擦写，**操作失误会导致设备完全不能开机**。作者只在上述这一台机器、这一个构建号上验证通过，其他机型/固件请勿照搬命令。

本项目只记录技术过程，**不提供任何厂商固件、驱动安装包或第三方 APK 的分发**，请自行从官方渠道获取。

## 致谢

- [TomKing062/CVE-2022-38694_unlock_bootloader](https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader) — 解锁工具链与 `spd_dump`
- HuskyDG 及后续维护者 — Kitsune Mask
- SPD 官方驱动 `SPD_Driver_R4.20.4201` 的提供方
