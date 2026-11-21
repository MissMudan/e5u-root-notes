# 05 · 端到端完整流程（一条龙 checklist）

> 每一步都给"预期输出"和"这一步失败怎么办"。照顺序走，**不要跳步**。
> 遇到与预期不符时，停下来判断，不要"再试一次看看"。

## 阶段 0 · 前置

详见 [00-preparation.md](00-preparation.md)。最小必要条件：

```
adb 可通 + adb shell 是 uid=0 + 构建号已记录 + 关键分区已备份 + 能进 BootROM + 驱动正确
```

## 阶段 1 · 打通下载模式通道

**目的**：证明 `spd_dump` 能正常读写，这是全流程的地基。

```powershell
Get-Process spd_dump -ErrorAction SilentlyContinue | Stop-Process -Force
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec r splloader r uboot reset
```

| | 内容 |
| --- | --- |
| 预期 | `Successfully connected to port: N` → `Load FDL Done` → `Read Part Done: splloader, size: 0x40000` → `Read Part Done: uboot_a, size: 0x300000` |
| 产物 | `splloader.bin` 262144B、`uboot.bin` 3145728B |
| 失败 A：`usb_send failed (0/1)` | 驱动不对（换官方 4.20.4201）或设备不在 BootROM（重新按键进入） |
| 失败 B：`Access denied` | 上一条 `spd_dump` 还占着 COM 口，先 `Stop-Process` |
| 失败 C：端口出现几十秒就消失 | 机器自己继续启动，抓住窗口立即执行，或重新进 BROM |

**这一步不通就不要往下走。**

## 阶段 2 · 备份原始镜像（二次确认）

```powershell
(Get-Item splloader.bin).Length    # 262144
(Get-Item uboot.bin).Length        # 3145728
```

把这两个文件复制到一个**不会被误删的目录**，并记录 MD5。

## 阶段 3 · 生成解锁载荷

用本机 SPL 生成（不要用别人的）：

```powershell
.\gen_spl-unlock.exe splloader.bin          # 产出 spl-unlock.bin，同时 splloader.bin 被裁剪
```

预期：

- `spl-unlock.bin` 大小 = SPL 真实长度（本项目 66152B）
- 用 `diff-spl.ps1` 比对，应只有一处差异，本项目在偏移 `0xB25C`：
  `D2 00 00 94 60 00 00 34` → `1F 20 03 D5 1F 20 03 D5`

把裁剪后的 `splloader.bin`（66152B）另存为 `splloader_trim.bin`，这两个文件都要留好：

- `spl-unlock.bin` —— 用于写解锁标志
- 裁剪版 SPL —— 用于最后还原

## 阶段 4 · 擦两槽 SPL + 写 cboot

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec r splloader r uboot e splloader e splloader_bak w uboot fdl2-cboot.bin reset
```

| | 内容 |
| --- | --- |
| 预期 | `Erase Part Done: splloader` / `splloader_bak`，随后 `Write Part Done: uboot_a, size: 0x300000` |
| 后果 | **设备从此无法正常启动**，只能停在 BootROM。这是设计如此，不是坏了 |
| 关键 | 必须先 `e splloader` 和 `e splloader_bak`。只擦一个槽，机器会回落到另一槽的原版 SPL 正常开机，`flash.locked` 仍为 1，会让人误判流程无效 |

## 阶段 5 · 执行解锁载荷

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl spl-unlock.bin 0x65000800
```

| | 内容 |
| --- | --- |
| 预期 | 输出到 `EXEC FDL1` 后出现 `CHECK_BAUD FAIL` + `device removed` —— **这是预期，不是失败** |
| 解释 | 载荷接手后重新枚举端口，主机侧握手必然中断 |

## 阶段 6 · 验证解锁标志

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec read_part miscdata 8192 64 m.bin
```

**不要带 `reset`**，否则没读出文件设备就复位了。执行完会停在 `FDL2 >`，先 `Stop-Process spd_dump` 再读文件。

判定（样本见 `artifacts/miscdata-unlocked.txt`）：

```
全 0（64/64 零字节）                     → 未解锁，回到阶段 4 重做
32B 哈希 + 16B + 16B（后两段相同）        → 已解锁，继续
```

## 阶段 7 · 还原并开机

```powershell
.\spd_dump.exe --wait 60 exec_addr 0x65015f08 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0x9efffe00 exec w splloader splloader_trim.bin w uboot uboot.bin w misc misc-wipe.bin reset
```

| | 内容 |
| --- | --- |
| 预期 | 三条 `Write Part Done`：`splloader`(0x40000) / `uboot_a`(0x300000) / `misc`(0x800) |
| 注意 | 写 66152B 到 256KB 区域时工具会自动补齐，日志显示 `file size: 0x40000`，正常 |
| 失败：又是 `usb_send failed (0/1)` | 设备停在上一次 `FDL2 >` 提示态而非 BootROM。清进程 → 关机 → 同时按住音量加+减 → 插线 → 重跑 |

`reset` 后设备**不一定自动上电**，手动长按电源 3–5 秒开机。

开机后验证：

```
ro.boot.flash.locked         = 0
ro.boot.verifiedbootstate    = orange
ro.boot.vbmeta.device_state  = unlocked
```

三条同时成立才算真解锁。此时 `sys.boot_completed=1`、adb 正常。

## 阶段 8 · 打 root 补丁

详见 [02-magisk-root.md](02-magisk-root.md)。核心三步：

```powershell
.\scripts\patch-init-boot.ps1 -Apk Magisk.apk -InitBoot backup\init_boot_a.img    # 提组件 + 机内打补丁
# 确认 ramdisk 里有 init（约 200KB）
adb shell "dd if=/data/local/tmp/magisk/new-boot.img of=/dev/block/by-name/init_boot_a bs=4096 && sync"
adb shell "dd if=/data/local/tmp/magisk/new-boot.img of=/dev/block/by-name/init_boot_b bs=4096 && sync"
```

**双槽都要写**。重启后：

```
/debug_ramdisk/magisk -v        → 31.1:MAGISK:R 或 46f5f839-kitsune:MAGISK:R
/debug_ramdisk/su -c id         → uid=0 context=u:r:magisk:s0
ps -A | grep magisk             → magiskd（root）
```

`su` 不在 adb 默认 PATH，必须用全路径 `/debug_ramdisk/su`。

## 阶段 9 · 可选：性能调度

```powershell
adb push scripts\perfctl.sh /data/adb/perfctl.sh
adb push scripts\e5u_perf.sh /data/adb/service.d/e5u_perf.sh
adb shell "sed -i 's/\r$//' /data/adb/perfctl.sh /data/adb/service.d/e5u_perf.sh; chmod 755 /data/adb/perfctl.sh /data/adb/service.d/e5u_perf.sh"
adb shell "/debug_ramdisk/su -c 'sh /data/adb/perfctl.sh perf'"
```

注意 Windows 写的脚本带 CRLF，**必须 `sed -i 's/\r$//'`**，否则 sh 报 `bad interpreter`。

## 阶段 10 · 收尾

- 记录三个可回滚镜像（原厂 / 当前补丁 / 任何中间态）
- 关掉不需要的调试开关
- 提醒用户：别升 OTA、别用不同签名的面具覆盖

## 全流程时间参考

| 阶段 | 实测耗时 |
| --- | --- |
| 驱动排查（首次） | 最长，占全流程 60% 以上 |
| 1–7 解锁 | 顺利时 20–30 分钟，含反复进 BROM |
| 8 root | 5–10 分钟 |
| 9 性能 | 2 分钟 |

**瓶颈从来不是解锁逻辑，而是驱动和"能不能稳定进 BootROM"。**
