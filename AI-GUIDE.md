# 给 AI 的交接文档（可直接复制给下一个 AI）

> **身份声明**
> 本仓库全部内容由 **豆包（Doubao，字节跳动旗下 AI 助手）** 在一台真实设备上规划并执行完成，人类只负责物理按键、插拔线缆与授权。所有命令、日志、失败记录均为实测。
> 下一个接手的是 AI 时，请直接读这份文档；是人类的，建议先读 [README.md](README.md)。

## 一、把这段直接喂给下一个 AI

```text
你现在接手一个已经在真机上验证过的 Android 解锁/root 项目，仓库是
https://github.com/MissMudan/e5u-root-notes

设备：GAMEMT E5 Ultra（E5U），Unisoc UMS9230 / 虎贲 T620，Android 14，A/B 分区。
目标：完成 Bootloader 解锁 + root（Kitsune Mask / Magisk）。

请按以下顺序阅读，不要跳：
  1. README.md                  —— 现状、结论、已交付内容
  2. docs/00-preparation.md     —— 开工前的硬性条件（缺一项都不许动手）
  3. docs/05-full-flow.md       —— 端到端 10 个阶段，每步都有预期输出与失败处理
  4. docs/01-bootloader-unlock.md —— BootROM 解锁细节（驱动、擦 SPL、解锁标志判据）
  5. docs/02-magisk-root.md     —— headless 打 init_boot 补丁、双槽、回滚
  6. docs/04-failed-paths.md    —— 已经验证走不通的路，不要重复尝试
  7. artifacts/                 —— 每一步的原始 spd_dump 日志，用来对照"正常输出长什么样"

硬性纪律：
- 每一步执行后，先比对预期输出再执行下一步；不符就停下诊断，不许"再试一次看看"。
- 每两条 spd_dump 命令之间必须 Stop-Process spd_dump，否则 COM 口被占用报 Access denied。
- 擦除 splloader / splloader_bak 之前，必须确认已拿到 262144B 的 splloader.bin 和 3145728B 的 uboot.bin。
- spl-unlock.bin 必须用当前这台机器的 SPL 现场生成，禁止使用仓库外的现成文件。
- 写 init_boot 必须写 _a 和 _b 两个槽。
- 设备的可写分区只在得到明确授权后才动；任何"清空数据"类操作先说明后果。

关键判据（记牢，避免误判）：
- spd_dump 首包就 usb_send failed (0/1) → 驱动不对（必须 SPD_Driver_R4.20.4201，INF 含 SprdVendorRequest=1），或不处于 BootROM
- 执行 spl-unlock.bin 后 CHECK_BAUD FAIL + device removed → 正常，不是失败
- 解锁成功判据：miscdata 偏移 8192 的 64 字节 = 32B + 16B + 16B，零字节 0/64
- 完全解锁判据：ro.boot.flash.locked=0 且 verifiedbootstate=orange 且 vbmeta.device_state=unlocked
- 进 BootROM：先关机，同时按住音量加+减不松，再插线，保持 20-30 秒

禁止事项：
- 禁止重签 vbmeta
- 禁止在 BL 锁定状态硬刷补丁过的 boot/init_boot（uboot 会校验，直接不开机）
- 禁止把厂商固件（SPL/uboot/fdl/init_boot 镜像）上传或转分发
- 不要在未备份 SPL 的情况下擦除两槽 SPL

遇到仓库里没有记录的新情况，先明确说明"这一步超出已验证范围"，再给方案，不要伪装成已验证。
```

## 二、为什么需要这份文档

通用 AI 读一个 GitHub 仓库时，最容易在这几个地方翻车：

| 常见失败 | 后果 | 本仓库的应对 |
| --- | --- | --- |
| 直接用 `fastboot flashing unlock` | 报 `unknown cmd.`，然后判定"此机型不支持" | `04-failed-paths.md` 明确列出所有 fastboot 死路 |
| 装第三方 VCOM 驱动 | 端口正常但 `usb_send failed`，误判工具不兼容 | `00-preparation.md` 给出 `SprdVendorRequest=1` 这个唯一判据 |
| 不擦 SPL 就写 cboot | 机器正常开机、`flash.locked` 仍为 1，误判流程无效 | `05-full-flow.md` 阶段 4 明确标注"必须先擦两槽" |
| 用别人的 `spl-unlock.bin` | 补丁位置不匹配，可能不开机 | 所有文档反复强调必须现场生成 |
| 忘记 `Stop-Process spd_dump` | 后续全部 `Access denied` | 每处命令块之间都写了这条 |
| 把 `CHECK_BAUD FAIL` 当成失败 | 反复重试载荷，浪费半小时 | 阶段 5 明确标注为预期输出 |
| 只写 `init_boot_a` | 切槽或 OTA 后 root 消失 | 阶段 8 标注必须双槽 |
| 用 Windows 写的 .sh 直接跑 | `bad interpreter` | 阶段 9 给出 `sed -i 's/\r$//'` |

## 三、证据在哪（AI 自我验证用）

想确认"某一步真的成功过"，去看 `artifacts/logs/`：

| 想验证的结论 | 去看 |
| --- | --- |
| 驱动装对后能读到 SPL | `brom-run4.log`（`Total number of partitions: 70`、`Storage is ufs`） |
| 两槽 SPL 被擦 | `patch-step1-cboot.log`（`Erase Part Done: splloader` / `splloader_bak`） |
| 载荷执行后的"异常"是正常的 | `patch-stepB1.log`、`patch-stepB2.log` |
| 解锁标志写入成功 | `patch-stepC.log`、`artifacts/miscdata-unlocked.txt` |
| 还原失败与成功的区别 | `patch-stepD.log`（失败）对比 `patch-stepD4.log`（`Write Part Done` 三条齐全） |
| 分区表里确实没有 splloader | `artifacts/partitions/partition_ums9230_e5u.xml` |

## 四、尚未验证的部分（不要当作已知）

诚实标注，避免下一个 AI 拿猜测当事实：

- **只在一台设备、一个构建号上验证过**，没有第二台交叉验证
- Kitsune Mask 30.7 用的是第三方接续维护构建（`io.github.x0eg0.magisk`），不是作者原仓库
- LSPosed / HMA 相关步骤**已下载但未安装**，仓库里没有这部分内容
- `splloader_bak` 是否需要一并还原**未验证**（原脚本只还原 `splloader`，本机实测能正常开机）
- 不同构建号下 SPL 补丁位置（本机 `0xB25C`）是否一致，**未验证**

## 五、授权与安全边界

- 本仓库只记录技术过程，**不包含**任何厂商固件、驱动安装包、第三方 APK
- 需要这些请自行从官方渠道或原作者仓库获取，链接见 README 致谢
- 下一个 AI 在真实设备上执行前，必须获得设备所有者对"清空数据 + 解锁 BL + 放弃保修"的明确同意
