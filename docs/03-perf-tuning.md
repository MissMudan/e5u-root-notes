# 03 · 性能调度（UMS9230）

## 原厂调频结构（本机实测）

```
policy0（6×A55）  governor=uscfreq  min=max=1820000       ← 原厂直接钉在满频
policy6（2×A75）  governor=uscfreq  768000–2210000
GPU 23100000.gpu  governor=simple_ondemand  384000000–850000000
sched_util_clamp_min = 1024                              ← 原厂已把 util 下限拉满
```

档位表：

```
policy0: 614400 768000 884000 1040000 1228800 1378000 1536000 1612000 1716000 1820000
policy6: 768000 1040000 1228800 1404000 1536000 1690000 1820000 1898000 1950000 2210000
GPU    : 384 512 614.4 768 850 (MHz)
```

`uscfreq` 是展锐自家的自适应调速器，可调项：

```
up_rate_limit_us=500  down_rate_limit_us=1000
freq_margin=20/30     timer_slack_val_us=5000
```

温控由 `sprd_thermal` + IPA（`power_allocator`）驱动，冷却设备为 `cpufreq-cpu0`(0-9)、`cpufreq-cpu6`(0-9)、`thermal-cpu-0/1`、`devfreq-23100000.gpu`(0-4)。实测空载 SoC 约 36–39°C、电池 23–24°C。

## 结论：真正的余量在大核响应和 GPU 下限

- 小核原厂已经是满频，没有提升空间
- 大核虽然上限 2.21GHz，但 `uscfreq` 在轻载时长期守在 1.2GHz 左右，升频有延迟
- GPU `simple_ondemand` 会掉到 384MHz，游戏里帧时间抖动主要来自这里

## 四档方案

`scripts/perfctl.sh` 提供 stock / mid / perf / turbo 四档，切换即生效，无需重启。

| 档位 | 大核 | GPU | 适用 |
| --- | --- | --- | --- |
| `stock` | uscfreq 768M–2.21G | ondemand 384–850M | 原厂，省电 |
| `mid` | uscfreq，下限抬到 1.22G | ondemand，下限 512M | 日常，减少升频延迟 |
| `perf` | performance，钉 2.21G | performance，钉 850M | 游戏，全程满频 |
| `turbo` | perf + 升频零延迟、降频迟钝、关 `sched_energy_aware` | 同 perf | 冲帧率，功耗/发热最大 |

用法（需要 root）：

```powershell
adb shell "/debug_ramdisk/su -c 'sh /data/adb/perfctl.sh status'"
adb shell "/debug_ramdisk/su -c 'sh /data/adb/perfctl.sh perf'"
```

档位会写进 `/data/adb/e5u_profile`，由 `service.d/e5u_perf.sh` 在开机 20 秒后自动重放。

**`stock` 档下脚本会直接 `exit 0`**——即开面完全不碰系统调频，等于彻底交还原厂，不会出现"切回原厂但小核下限被放宽"这种残留。

## 注意事项

满频不等于更快。这台机器散热空间很小，持续负载会把 SoC 顶到温控线，IPA 自动降频，实际帧率反而可能比 `mid` 更抖。建议按场景切换，而不是常年挂 `perf`。

`perf` 档实测空载 SoC 由 37°C 升到 39°C 左右，属正常范围，未触发冷却设备介入。
