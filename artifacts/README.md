# artifacts · 过程文件说明

这里是本次真机操作过程中**实际产生**的文件，用来给后来者做对照样本。

## logs/ — spd_dump 原始日志

| 文件 | 对应步骤 | 看点 |
| --- | --- | --- |
| `brom-run1.log` … `brom-run4.log` | 早期试探与分区表抓取 | `run4` 是第一次成功读出 `splloader` / `uboot_a` 的那次，可见 `Total number of partitions: 70`、`Storage is ufs` |
| `patch-stepA.log` | 备份 SPL + uboot | `read Part Done: splloader, size: 0x40000` |
| `patch-step1-cboot.log` | 擦两槽 SPL + 写 cboot | `Erase Part Done: splloader / splloader_bak`，随后写 `uboot_a` |
| `patch-stepB1.log` / `patch-stepB2.log` | 执行 `spl-unlock.bin` | 到 `EXEC FDL1` 后 `CHECK_BAUD FAIL` + `device removed`，**这是预期行为** |
| `patch-stepC.log` | 读 miscdata 64 字节 | 成功读出的那次 |
| `patch-stepD.log` / `D2` / `D3` | 还原失败的三次 | `Successfully connected to port` 紧跟 `usb_send failed (0 / 1)`，即设备停在 FDL2 提示态而非 BootROM |
| `patch-stepD4.log` | 还原成功那次 | `Write Part Done: splloader / uboot_a / misc` 三条齐全 |
| `patch-restore-uboot*.log` | 早期误操作后的 uboot 回写 | 对应"漏擦 SPL 导致槽位回退"的那次误判 |

## partitions/

`partition_ums9230_e5u.xml` — 工具从设备读出的 70 个分区定义。注意里面**找不到 `splloader`**，SPL 走独立 LUN（`spl_a`→`/dev/block/sdb`、`spl_b`→`/dev/block/sdc`），`splloader` / `splloader_bak` 是 `spd_dump` 的特殊名。

## miscdata-unlocked.txt

解锁成功后 `miscdata` 偏移 8192 起 64 字节的十六进制样本，用于对照判定。

## 未包含的文件（有意排除）

| 文件 | 原因 |
| --- | --- |
| `splloader.bin` / `uboot_orig.bin` / `uboot.bin` | 厂商固件组件，版权归原厂，不转分发 |
| `spl-unlock.bin` / `splloader` 裁剪图 | 由厂商 SPL 派生，同上 |
| `fdl1-dl.bin` / `fdl2-dl.bin` / `fdl2-cboot.bin` | 展锐下载器固件 |
| `pgpt.bin` | GPT 原始转储，属设备固件数据 |
| `init_boot*.img` / `boot_a.img` / `vbmeta_a.img` 等 | 设备固件镜像 |
| `spd_dump.exe` / `Channel9.dll` / `gen_spl-unlock.exe` | 第三方工具，请从原作者仓库获取（见 README 致谢） |
| 各类 APK / 驱动包 | 第三方分发物，请走官方渠道 |

需要这些的话，请自行从设备上用文档里给出的命令重新抓取——这样也顺便验证了流程。
