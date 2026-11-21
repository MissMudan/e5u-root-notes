# 04 · 已验证走不通的路（省得重复劳动）

以下每一条都在真机上跑过并拿到明确失败输出，不是"听说不行"。

## Bootloader / 解锁相关

| 尝试 | 结果 |
| --- | --- |
| 开发者选项 "OEM 解锁" 开关 | 打开后**立即自动弹回**。写入方是 TEE 里的 `vendor.sprd.hardware.oemlock-service` + `oemlock_ca.so`，状态存在安全世界，userland 改不动 |
| `fastboot flashing unlock` | `unknown cmd.` |
| `fastboot oem unlock` | `Unlock bootloader fail.` |
| `fastboot oem get_identifier_token` | 返回 `4535554F503130303030463038`（就是 SN 的十六进制，没有可利用信息） |
| `fastboot flashing unlock_bootloader` | 需厂商 `rsa4096_vbmeta` 私钥签 `certificate.bin`；主机 fastboot 37.0.1 直接拦该非标准命令 |
| `fastboot oem get_unlock_ability` | `Not implement.` |
| `fastboot getvar unlock_ability` / `getvar secure` | 返回空 |
| `fastboot oem edl` / `oem reboot-edl` / `oem download` | 全部 `unknown cmd.` —— **fastboot 无法跳下载模式** |
| `adb shell reboot edl` | 只是普通重启进 Android |

## BL 锁定状态下直接刷机

**不行**。锁定态下 `uboot` 会逐个校验 `boot` / `dtbo` / `init_boot` / `vendor_boot`（`verify_ret:0x0` 才放行），只有 `LOCK FLAG IS : UNLOCK` 才跳过校验。硬刷补丁过的 `init_boot` 不会开机。

所以"先进 fastboot 刷机绕开解锁"这条路在逻辑上就不成立。

## 驱动相关

| 尝试 | 结果 |
| --- | --- |
| 2015 版通用 VCOM（`SPRD_NPI_USBDriver_1.4`） | 能枚举成 `SPRD U2S Diag`，但 `spd_dump` 首包即 `usb_send failed (0/1)` |
| 手改 INF 的 `CdcControlLineState` | 哈希不匹配，系统拒装；还误删过一次驱动包 |
| 官方 `SPD_Driver_R4.20.4201` | **成功**。`SprdVendorRequest=1` 是关键 |
| `spd_dump` 不带 libusb 回退 | 该 exe 只走 Channel9/COM（源码 `Wrapper.cpp` → `CBootModeOpr`），没有 USB 后端可选 |
| nightly.link 获取预编译 `spd_dump` | 各种拼法全 404。工作流确有成功 run，但匿名拿不到 artifact |

## 连接与端口

| 现象 | 原因与处理 |
| --- | --- |
| 端口只存在几十秒就消失 | 机器自动继续启动/断电。趁窗口内立刻执行命令，或重新按组合键 |
| `Successfully connected to port` 紧跟 `usb_send failed (0/1)` | 设备停在上一次 `spd_dump` 的 `FDL2 >` 提示态，不在 BootROM 等待态。先 `Stop-Process spd_dump -Force`，再让设备重新上电 |
| `Access denied` | 上一条 `spd_dump` 还占着 COM 口没退出 |
| 整机无反应 | 电池放干，电脑 USB 0.5A 充不进去，先充再试 |

## 分区命名

GPT 里共 70 个分区，但**没有 `splloader` / `splloader_bak`** —— SPL 走独立 LUN（adb 侧 `spl_a`→`/dev/block/sdb`、`spl_b`→`/dev/block/sdc`），`splloader` 是 `spd_dump` 的特殊名，不要试图从分区表里找它。

`miscdata`、`misc`、`uboot_a/b`(各 3MB)、`uboot_log`(16MB) 在列表内。分区表 XML 里的 `<Partition id="misc" size="1"/>`，size 单位不是字节。

## 网络类（顺手记录）

Private DNS 指到 `dns.adguard.com` 在境内不通，`private_dns_mode` 已回滚为 `opportunistic`。
