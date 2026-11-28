# GAMEMT E5 Ultra (UMS9230) 解锁 BL 与 Root 全记录

> **⚠️ 本项目全程由 AI 操作完成**
>
> **执行者：豆包（Doubao，字节跳动旗下 AI 助手）。** 从驱动排查、BootROM 解锁、`init_boot` 打补丁到性能调度脚本，所有命令均由豆包 AI 在真实设备上规划并逐步执行；人类只负责物理操作（关机、**同时按住音量加+音量减**再插线进入 BootROM、插拔线缆）与授权。
>
> 文中数据、日志、失败记录都是这台机器的实测结果，不是从教程里转述。请把它当作一份 **AI 实操记录** 来读，而不是人工精调后的权威手册——照做之前请自行核对每一处风险。
>
> 下一个接手的是 AI？直接读 **[AI-GUIDE.md](AI-GUIDE.md)**，里面有可直接复制的提示词与执行纪律。

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

**硬件规格**（6×A55@1.82G + 2×A75@2.21G、Mali-G57 384–850MHz、5.70GiB 可用内存、1280×720@60Hz 单模式、CH32V203 手柄、SK hynix UFS、5146mAh）全部实测值见 **[docs/06-machine-profile.md](docs/06-machine-profile.md)**，那里还有"别人的机器能不能照搬"的三档判据。想给自己的机器采集同样一份，跑 `scripts/collect-profile.ps1`（只读）。

> **开工第一件事：打开开发者选项和 USB 调试。** 设置 → 关于手机 → 连点**版本号** 7 次 → 进"开发者选项" → 打开 **USB 调试** → 插线时在手机上勾"一律允许使用这台计算机进行调试"。`adb devices` 显示 **`device`** 才算通，`unauthorized` / `offline` / 空列表都不算。这一步不做，后面的备份、读分区、`reboot` 全部无从开始。

> **进入 BootROM 的唯一方式**（本机实测）：先**关机**，然后**音量加和音量减两个键同时按住、都别松**，保持按住的状态插上 USB 线，**继续按住约 10 秒**，电脑上就会冒出展锐端口（10 秒左右即可，不必按到二三十秒；若还没出现就继续按住等它）。只按其中一个、或者先插线再按键，都进不去。

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

**推荐阅读顺序**（交给 AI 时请勿跳步）：

| 顺序 | 文件 | 内容 |
| --- | --- | --- |
| 0 | [AI-GUIDE.md](AI-GUIDE.md) | **给下一个 AI 的交接文档**：可直接复制的提示词、执行纪律、常见误判对照 |
| 1 | [docs/00-preparation.md](docs/00-preparation.md) | **开工前准备**：开发者选项与 USB 调试、机型核对、软件清单、分区备份、物理条件、风险确认 |
| 1.5 | [docs/06-machine-profile.md](docs/06-machine-profile.md) | **硬件档案**：SoC / CPU 簇 / GPU / 存储 / 屏幕 / 触摸 / 手柄 / 传感器 / 无线 / 电源 / 散热，以及"你的机器能不能照搬"的三档判据 |
| 2 | [docs/05-full-flow.md](docs/05-full-flow.md) | **端到端 10 个阶段**，每个阶段都有预期输出与失败处理 |
| 3 | [docs/01-bootloader-unlock.md](docs/01-bootloader-unlock.md) | BootROM 解锁细节：驱动判据、擦 SPL 顺序、解锁标志判据 |
| 4 | [docs/02-magisk-root.md](docs/02-magisk-root.md) | headless 打 `init_boot` 补丁、双槽写入、换面具、回滚 |
| 5 | [docs/03-perf-tuning.md](docs/03-perf-tuning.md) | UMS9230 调频结构与四档脚本说明 |
| 6 | [docs/04-failed-paths.md](docs/04-failed-paths.md) | **已验证走不通的路**，避免重复劳动 |
| 7 | [artifacts/](artifacts/) | 每一步的原始日志与取证文件 |

## 脚本与过程文件

```
scripts/    可直接复用的脚本（调频切换、开机自动应用、headless 打补丁）
tools/      本次排查过程中写的 PowerShell 小工具（驱动安装、端口监视、SPL 比对等）
artifacts/  实测日志、分区表、解锁标志样本
```

- [scripts/perfctl.sh](scripts/perfctl.sh) — 调频档位切换（需要 root）
- [scripts/e5u_perf.sh](scripts/e5u_perf.sh) — Magisk `service.d` 开机自动恢复档位
- [scripts/patch-init-boot.ps1](scripts/patch-init-boot.ps1) — 从面具 APK 里自动提取组件、在机内打 `init_boot` 补丁
- [scripts/collect-profile.ps1](scripts/collect-profile.ps1) — **硬件档案采集**：只读跑一条命令，把 SoC/CPU/GPU/存储/屏幕/手柄/传感器/散热全导成 Markdown，用来和自己的机器逐项对照
- [tools/magisk-307-NOTES.md](tools/magisk-307-NOTES.md) — 面具安装包的 SHA256、包名、来源与非官方签名说明（APK 本体在 Release 附件）
- [tools/](tools/) — `install-sprd-driver*.ps1`（驱动安装）、`port-probe.ps1` / `usb-monitor.ps1`（端口监视）、`diff-spl.ps1`（补丁差异比对）、`show-m.bin.ps1`（解锁标志解析）
- [artifacts/](artifacts/) — 每一步 `spd_dump` 的原始日志、70 分区表、`miscdata` 解锁标志样本；厂商固件与第三方二进制**一律未包含**，说明见 [artifacts/README.md](artifacts/README.md)


## 完整性说明（给读取者）

**已包含——足以让另一个 AI 或人从头复现的判断性信息：**

- 全流程 10 个阶段的命令、预期输出、失败分支与判据
- 每一步的原始 `spd_dump` 日志（含失败样本与成功样本的对比）
- 70 个分区的完整定义表
- 解锁标志 64 字节的原始十六进制与判定标准
- 所有可复用脚本与排查工具（含驱动安装、端口监视、SPL 比对、补丁生成）
- 已验证走不通的路，以及"为什么这些异常是正常的"

**未包含——都是不可转分发的二进制：**

厂商固件（SPL / uboot / fdl1 / fdl2 / cboot）、`init_boot` 等分区镜像、`spd_dump.exe` 等第三方工具、驱动安装包。原因与获取方式见 [artifacts/README.md](artifacts/README.md)。

**唯一例外**：本项目实测用的面具安装包 `Kitsune_30.7_140326.apk` 以 **Release 附件**形式提供（不进入 git 历史，`.gitignore` 仍排除 `*.apk`）。SHA256 `18A0F7B9…6A9F`、来源与非官方签名的说明写在 [tools/magisk-307-NOTES.md](tools/magisk-307-NOTES.md)，下载页见 [Releases](https://github.com/MissMudan/e5u-root-notes/releases/tag/v30.7-kitsune)。

也就是说：**这套文档是完整的"怎么想、怎么判、怎么做"，缺的只是"物料"。** 谁要复现，按 `docs/00-preparation.md` 的清单把物料备齐即可，物料本身都能从原作者仓库或官方渠道拿到。

**尚未验证、请勿当作已知：** 本仓库只在一台设备、一个构建号上验证；Kitsune 30.7 为第三方接续构建；LSPosed / HMA 相关内容未实施；不同构建号的 SPL 补丁偏移是否一致未验证。详见 [AI-GUIDE.md](AI-GUIDE.md) 第四节。

## 免责声明

**这会拆掉设备的所有安全边界**：BL 解锁后 `verifiedbootstate` 变 `orange`，Play Integrity 直落到底，部分银行、支付、游戏反作弊类应用会拒绝运行；设备被远程/物理接触后攻击面显著变大。

解锁过程涉及 BootROM 下载模式与分区擦写，**操作失误会导致设备完全不能开机**。作者只在上述这一台机器、这一个构建号上验证通过，其他机型/固件请勿照搬命令。

本项目只记录技术过程，**不提供任何厂商固件或驱动安装包的分发**，请自行从官方渠道获取。唯一随仓库发布的第三方二进制是本项目实测使用的面具安装包（Release 附件，见上方说明），**非官方签名，请自行核对 SHA256 后再安装**。

## 致谢

- [TomKing062/CVE-2022-38694_unlock_bootloader](https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader) — 解锁工具链与 `spd_dump`
- HuskyDG 及后续维护者 — Kitsune Mask
- SPD 官方驱动 `SPD_Driver_R4.20.4201` 的提供方
