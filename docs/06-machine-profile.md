# 06 · 硬件档案（本机实测）

> 这份档案记录的是**硬件**：SoC、CPU 簇、GPU、内存、存储、屏幕、触摸、手柄、传感器、无线、电源、散热。
> 用法：在你自己的机器上跑一遍 `scripts/collect-profile.ps1`，逐项和本文对照，判断哪些参数能照搬（判据见第 14 节）。

采集时间 2026-11-28，全部通过 `adb shell` 只读读取，未修改任何设置。

## 速查卡

| 部件 | 本机规格 |
| --- | --- |
| SoC | Unisoc **UMS9230**（`ro.board.platform=ums9230`，`ro.hardware=ums9230_6h10`） |
| CPU | 6×Cortex-A55 @1.82GHz + 2×Cortex-A75 @2.21GHz（实测 `/proc/cpuinfo`） |
| GPU | ARM **Mali-G57**，384–850 MHz，`simple_ondemand` |
| 内存 | 6GB 标称，`MemTotal` 5973020 kB ≈ 5.70 GiB，另有 3.53 GiB ZRAM |
| 存储 | **SK hynix H9HQ15AECMBDAR** UFS，userdata 128GB 级（`112G` 可用） |
| 屏幕 | **1280×720 @60Hz**（单模式），密度 268，标称亮度 500 nits，无 HDR |
| 触摸 | **Hynitron** 触控 IC（`hyn_ts`，I2C-3 地址 `0x5a`） |
| 手柄 | **CH32V203** 单片机（沁恒 RISC-V），走 SPI，非标准 HID |
| 传感器 | **Silan SC7I22** 六轴（加速度+陀螺），最高 400Hz；**无光感、无磁力计** |
| 无线 | 展锐 WCN 一体式（`87000000.cpwcn-btwf`），2.4G/5G 双频 + 蓝牙 |
| 音频 | 展锐 **SC2730** 音频编解码，48kHz/16bit，带耳机检测 |
| 电源 | 5146 mAh，5V 充电 |
| 振动 | `sc27xx:vibrator`（PMIC 内置） |

## 1 · 整机标识

| 项 | 值 |
| --- | --- |
| 型号 | `E5U` |
| 品牌 / 厂商 | `E5U` / `E5U`（没有独立品牌标识，直接用品类名） |
| 内部代号 | `ums9230_6h10` |
| 平台 | `ums9230` |
| 硬件标识 | `ums9230_6h10` |
| SN | `E5UOP10000F08` |
| 系统 | Android 14 / SDK 34 |
| 构建号 | `XNM_TF05_V40_E5U_00_A_FL_ZX_42_6X128_720X1280_V1.0_20250926_1024` |
| 内核 | `5.15.123-android13-8-00033-g39606e3309fc-ab10974680`（编译于 2023-10-19） |
| ABI | `arm64-v8a` |

构建号里 `6X128` 就是 6GB+128GB 的意思，`720X1280` 是屏幕分辨率——厂商把配置直接编进了构建号，所以同型号不同配置（如 8+256）构建号会不同。

## 2 · SoC 与外围芯片

一颗 **UMS9230** 加三颗外围芯片，从 sysfs 节点能反推出来：

| 模块 | 节点 / 驱动 | 说明 |
| --- | --- | --- |
| 应用处理器 | `ro.board.platform=ums9230` | 8 核，见第 3 节 |
| GPU | `23100000.gpu` | Mali-G57，见第 4 节 |
| 无线子系统 | `87000000.cpwcn-btwf` → `sprd-wlan` | WiFi+蓝牙一体，展锐自研 WCN |
| 电源管理 | `64200000.spi:pmic@0`（`sc27xx`） | 充电、振动、RTC、部分中断 |
| 音频编解码 | `sprdphone-sc2730` | SC2730 codec，耳机插孔检测也在它上面 |
| 显示 | `dpu` devfreq + `sprd_backlight` | 展锐显示子系统，背光独立节点 |

散热相关的 `thermal_zone` 名字里能看到 `ank0`–`ank5`、`prometheus6/7`、`cputop0/1`——这些是展锐内部的温度采集点代号，不是传感器型号，见第 13 节。

## 3 · CPU 簇（这是调频的关键）

**不是对称的 8 核，是两个不同架构的簇**，这一点直接决定调频脚本要写两套：

| 核 | ARM part | 架构 | 最大 | 最小 | 归属 |
| --- | --- | --- | --- | --- | --- |
| cpu0–cpu5 | `0xd05`（variant `0x2`） | Cortex-A55 | 1820 MHz | 614 MHz | `policy0` |
| cpu6–cpu7 | `0xd0a`（variant `0x3`） | Cortex-A75 | 2210 MHz | 768 MHz | `policy6` |

可用档位（`scaling_available_frequencies`，实测）：

```
policy0 (A55)：614 768 884 1040 1228 1378 1536 1612 1716 1820  (MHz)
policy6 (A75)：768 1040 1228 1404 1536 1690 1820 1898 1950 2210（MHz）
```

调速器：**两簇都是 `uscfreq`**（展锐自研），不是常见的 `schedutil`。所以照抄别家 `schedutil` 的调参脚本会直接失效。

调度钳位：

```
sched_util_clamp_min = 1024
sched_util_clamp_max = 1024
```

两个都钉死在 1024（等于 util 永远满值），这是原厂"性能优先"的痕迹——也是这台机器待机都偏热、耗电偏快的硬件层原因。`docs/03` 的 stock 档保留原厂值，perf/turbo 档改的就是这三处（两个 policy + clamp）。

## 4 · GPU

| 项 | 值 |
| --- | --- |
| 型号 | `ARM, Mali-G57`，`OpenGL ES 3.2 v1.r41p0-01eac0…` |
| devfreq 节点 | `/sys/class/devfreq/23100000.gpu` |
| 频率范围 | 384 – 850 MHz |
| 调速器 | `simple_ondemand` |

同目录下还有 `dpu`、`vsp-dvfs`、`mmsys-dvfs`、`isp-dvfs`、`jpg-dvfs`、`dcam-*-dvfs`、`cpp-dvfs`、`fd-dvfs`、`mtx-dvfs`、`scene-frequency`——都是展锐的多媒体、相机、显示子系统，跟游戏性能无直接关系，调频时**不要**去动它们。

## 5 · 内存

| 项 | 值 | 换算 |
| --- | --- | --- |
| MemTotal | `5973020 kB` | 5.70 GiB（标称 6GB，系统保留约 300MB） |
| SwapTotal | `3703268 kB` | 3.53 GiB，来自 ZRAM |
| zram0 disksize | `3792150528 B` | 同上 |

出厂就开了 3.5GB ZRAM，所以后台多开不容易被杀，但代价是 CPU 要花时间压缩/解压——这也解释了为什么这台机器"看着不卡但偶尔顿一下"。

## 6 · 存储

| 项 | 值 |
| --- | --- |
| 闪存颗粒 | **SK hynix `H9HQ15AECMBDAR`**，rev `A043` |
| 类型 | UFS（`/dev/block/sda`，另有 `sdb`、`sdc` 两个独立小设备） |
| userdata | `/dev/block/sda70`，`112G` 可用，已用 `10G` |
| ZRAM 设备 | `zram0`（不占闪存） |

`sdb` / `sdc` 不是 UFS 的分区，而是**两槽 SPL 各自独立的块设备**（`/dev/block/by-name/spl_a → sdb`、`spl_b → sdc`）。这是本机的硬件布局特点，也是为什么擦 SPL 必须两槽都擦，见 [00-preparation.md 第 4.1 节](00-preparation.md)。

## 7 · 屏幕

| 项 | 值 | 备注 |
| --- | --- | --- |
| 物理分辨率 | `1280 × 720` | `wm size` |
| 物理密度 | `268 dpi` | `wm density` |
| 实际 DPI | `292.9 × 294.967` | `dumpsys display` 报的 x/y dpi |
| `ro.sf.lcd_density` | `320` | UI 按 320 缩放，比物理密度大，所以界面偏大 |
| 刷新率 | `60 Hz`，**只有这一个模式** | `supportedModes` 里 id=1，无 90/120 可选 |
| 标称亮度 | 最大 500 nits / 平均 500 nits / 最小 0 | 系统上报值，非实测 |
| HDR | 不支持（`mSupportedHdrTypes=[]`） | |
| 背光 | `sprd_backlight`，`max_brightness=255` | 另有 `sprd_backlight_fan`（风扇/副背光） |

屏幕是单模式 60Hz，**没有高刷可解锁**——任何"解锁 90Hz"的说法在这台机器上都不成立，这是硬件限制，不是系统限制。

## 8 · 触摸

| 项 | 值 |
| --- | --- |
| 驱动名 | `hyn_ts`（Hynitron 海栎创） |
| 总线 | I2C-3，地址 `0x5a`（`20100000.i2c/i2c-3/3-005a`） |
| 事件节点 | `/dev/input/event3` |
| 属性 | `PROP=2`（INPUT_PROP_DIRECT，直触屏），`ABS=665800000000000` |
| 支持的键 | `KEY=420`（BTN_TOUCH + BTN_TOOL_FINGER） |

单点/多点能力由 ABS 位图决定，`665800000000000` 对应 `ABS_MT_SLOT`、`ABS_MT_POSITION_X/Y` 等标准多点触摸位。

## 9 · 手柄 / 按键（掌机最关键的一块）

**不是一个 USB/蓝牙手柄，而是一颗 MCU 直连 SPI**：

| 项 | 值 |
| --- | --- |
| 设备名 | `CH32V203_Joystick` |
| MCU | 沁恒 **CH32V203**（RISC-V） |
| 总线 | SPI0，`20120000.spi/spi0.0` |
| 事件节点 | `/dev/input/event1` |
| 能力位 | `KEY=f00000000 0 0 0 7fdb000300000000 0 800 168000000000 0`，`ABS=30627` |

`ABS=0x30627` 拆开是：`ABS_X`(0)、`ABS_Y`(1)、`ABS_Z`(2)、`ABS_RX`(5)、`ABS_GAS`(9)、`ABS_BRAKE`(10)、`ABS_HAT0X`(16)、`ABS_HAT0Y`(17)——正好对应左摇杆（X/Y）、右摇杆（Z/RX）、十字键/方向帽（HAT0X/HAT0Y）和两个模拟扳机（GAS/BRAKE）。**这是标准的手柄 input 映射**，好消息：可以用 `keylayout` 或按键映射 App 改键。

另外还有 `gpio-keys`（`event0`，电源/音量等物理键，`KEY=1c000000000000`）和 `sc27xx:vibrator`（`event2`，振动马达，支持 FF 力反馈）。

**限制**：MCU 固件是烧在 CH32V203 里的，Android 层改不了它的采样率、死区、摇杆曲线。想改只能改上层映射（`/system/usr/keylayout/` 或映射类 App），**不要**指望软件调"摇杆灵敏度"能改到硬件层。

## 10 · 传感器

| 传感器 | 厂商 | 类型 | 采样范围 |
| --- | --- | --- | --- |
| `acc_sc7i22` | silan（士兰微） | 加速度计 | 3.12 – 400 Hz |
| `gyro_sc7i22` | silan | 陀螺仪 | 3.12 – 400 Hz |
| `acc/gyro_sc7i22 Uncalibrated` | silan | 未校准原始值 | 同上 |
| `Game Rotation Vector` | Sprd | 游戏旋转矢量（软件合成） | 3.12 – 100 Hz |
| `Step Detector` / `Step Counter` | Sprd | 计步（软件） | — |
| `Device Orientation` / `Stationary` / `Motion Detect` | Sprd | 姿态/静止/运动检测（软件） | — |

**硬件只有一颗六轴 SC7I22**，其余都是展锐算法合成的虚拟传感器。

**明确没有的**：环境光传感器、磁力计（指南针）、气压计。所以自动亮度在这台机器上不可用，任何"指南针"类应用也拿不到数据——这是硬件缺失，别在系统层反复折腾。

## 11 · 无线

| 项 | 值 |
| --- | --- |
| WiFi 驱动 | `sprd-wlan`，挂在 `87000000.cpwcn-btwf` |
| 频段 | 2.4G + 5G 双频（实测连在 `2417 MHz`，历史记录中有 `5180 MHz` 信道） |
| 协议 | 当前连接协商为 `Wi-Fi standard: 4`（2.4G 下的 802.11n） |
| 蓝牙 | 一体式 WCN 提供，MAC `40:45:da:60:0f:ff` |
| USB | `musb-hdrc.1.auto`（展锐 MUSB 控制器），当前 `sys.usb.config=adb` |

WiFi MAC 是随机化的（`46:c3:4e:…`，本地管理位为 1），排查网络问题时别拿它当设备唯一标识，用 SN。

## 12 · 音频与振动

| 项 | 值 |
| --- | --- |
| Codec | `sprdphone-sc2730`（展锐 SC2730） |
| 输出 | 48 kHz / 16 bit PCM（`AudioOut_D` 混音线程） |
| 耳机 | 有检测（`Headset Jack`，`event4`，`SW=14` 含耳机插入位） |
| 线控 | 有（`Headset Keyboard`，`event5`） |
| 振动 | `sc27xx:vibrator`，`event2`，支持 FF 力度控制 |

## 13 · 电源与散热

**电源**

| 项 | 值 |
| --- | --- |
| 设计容量 | `5146000 µAh` ≈ 5146 mAh |
| 充电电压上限 | 5 V |
| 充电电流上限 | 500 mA（`Max charging current: 500000 µA`） |
| 健康状态 | `health: 2`（Good） |

充电电流只有 500mA，这就是"低电量时插电脑几乎充不进电、还会掉电"的硬件原因，也是刷机前要求电量 50% 以上的根据。

**散热测温点**（18 个 `thermal_zone`，实测命名）：

| zone | 名称 | 说明 |
| --- | --- | --- |
| 0 | `soc-thmzone` | SoC 整体 |
| 1 / 6 | `cputop0-tzone0` / `cputop1-thmzone` | 两个 CPU 簇顶部 |
| 7 | `gpu-thmzone` | GPU |
| 14 | `board-thmzone` | 主板 |
| 15 | `pa-thmzone` | 功放（实测待机就到了 72.9 °C，是这机器最热的点） |
| 16 | `chg-thmzone` | 充电 |
| 17 | `battery` | 电池（19.6 °C） |
| 2 / 3 / 4 / 8 / 9 / 10 | `ank0-tzone1` / `ank1..ank5` | 展锐内部采集点 |
| 5 / 11 | `prometheus7` / `prometheus6` | 同上 |
| 12 / 13 | `osctsen` / `outtsen` | 晶振/外部温度（无 temp 值） |

**`pa-thmzone` 待机就 70 °C+ 是这台机器的固有特性**，压测时它会最先触发降频，别把它当成故障。

## 14 · 能不能照搬：三档判据

跑 `scripts/collect-profile.ps1` 后按下面三档对照。

### A. 必须一致（不一致就别套用本项目命令）

| 项 | 本机值 | 不一致的后果 |
| --- | --- | --- |
| `ro.board.platform` | `ums9230` | 换平台（如 UMS9620），BootROM 载荷与偏移全废 |
| `ro.hardware` | `ums9230_6h10` | 平台对但子型号不同，分区布局可能不同 |
| 构建号 | `XNM_TF05_V40_…_20250926_1024` | SPL 补丁偏移 `0xB25C` 强绑定构建号 |
| SPL 大小 / MD5 | 262144 / `75EF4A02…` | 不同就必须用自己的 SPL 现场生成载荷 |

### B. 可以不同（只影响体验，不影响解锁）

| 项 | 说明 |
| --- | --- |
| SN | 每台不同，无实际用途 |
| 内存容量（6GB vs 8GB） | 影响 ZRAM 与后台留存，不影响解锁 |
| 电池/屏幕批次 | 只影响续航与观感 |
| WiFi MAC / 蓝牙 MAC | 随机化，每台不同 |

### C. 必须重新确认（数字不能抄）

| 项 | 本机值 | 换机后怎么做 |
| --- | --- | --- |
| CPU 簇结构与频率档 | `policy0` A55 614–1820 / `policy6` A75 768–2210 | 读 `scaling_available_frequencies` 重新取档位 |
| 调速器 | `uscfreq` | 别的平台可能是 `schedutil`，脚本要改判断 |
| GPU 节点与范围 | `23100000.gpu`，384–850 | `ls /sys/class/devfreq/*gpu*` 重新定位 |
| 分区名映射 | `spl_a→sdb`、`spl_b→sdc` | `ls -l /dev/block/by-name/spl_a/b` 确认，别默认 sdb/sdc |
| 测温点编号 | 18 个 zone，见第 13 节 | 按 `type` 名字重新对，不要按编号 |

## 15 · 这台机器的硬件"非标准"清单（踩坑预警）

1. **屏幕只有 60Hz 单模式** —— 没有高刷可解锁，别信"改 build.prop 上 90Hz"。
2. **手柄是 CH32V203 MCU 走 SPI** —— 不是标准 HID 手柄，改键只能改上层映射，MCU 固件改不了。
3. **无光感、无磁力计** —— 自动亮度与指南针在这台机器上不可用，是硬件缺失。
4. **两簇都是 `uscfreq`** —— 抄 `schedutil` 脚本会失效。
5. **`sched_util_clamp` 上下限都钉死 1024** —— 原厂就是这么写的，所以待机也满频跑，改它才是"降功耗"的正解。
6. **充电电流上限 500mA** —— 低电量插电脑充电极慢，刷机务必先充到 50% 以上。
7. **`pa-thmzone` 待机 70 °C+** —— 固有特性，压测最先降频的点。
8. **`ro.sf.lcd_density=320` 与物理 268 不一致** —— 改 DPI 要两个都考虑，否则 UI 会错位。
9. **`spl_a`/`spl_b` 是两个独立块设备（`sdb`/`sdc`）** —— 只擦一个，机器会从另一槽正常开机，看起来"解锁失败"。
10. **分区名 `hypervsior_a/b` 是厂商拼写错误** —— 照原样存在，别改成 `hypervisor` 去查。

## 16 · 硬件档案与其他文档的关系

```
00-preparation.md   开工条件（含 SPL 的 adb 直读备份，第 4.1 节）
05-full-flow.md     端到端 10 阶段
06-machine-profile  本文：硬件规格 + 能不能照搬的判据
03-perf-tuning.md   基于本文第 3、4、13 节的调频脚本
04-failed-paths.md  已验证走不通的路
```
