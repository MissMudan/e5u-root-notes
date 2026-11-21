#!/system/bin/sh
# E5U 性能调度切换器 (UMS9230 / 虎贲T620)
# 用法: perfctl.sh stock|mid|perf|status

POL0=/sys/devices/system/cpu/cpufreq/policy0
POL6=/sys/devices/system/cpu/cpufreq/policy6
GPU=/sys/class/devfreq/23100000.gpu

echo_val() {
  # $1=file $2=value
  [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null
}

apply_stock() {
  echo_val $POL0/scaling_governor uscfreq
  echo_val $POL0/scaling_min_freq 1820000
  echo_val $POL0/scaling_max_freq 1820000
  echo_val $POL6/scaling_governor uscfreq
  echo_val $POL6/scaling_min_freq 768000
  echo_val $POL6/scaling_max_freq 2210000
  echo_val $GPU/governor simple_ondemand
  echo_val $GPU/min_freq 384000000
  echo_val $GPU/max_freq 850000000
  echo_val /proc/sys/kernel/sched_util_clamp_min 1024
  echo_val /proc/sys/kernel/sched_util_clamp_min_rt_default 1024
  echo "已恢复原厂调度"
}

apply_mid() {
  echo_val $POL6/scaling_governor uscfreq
  echo_val $POL6/scaling_min_freq 1228800
  echo_val $POL6/scaling_max_freq 2210000
  echo_val $GPU/governor simple_ondemand
  echo_val $GPU/min_freq 512000000
  echo_val $GPU/max_freq 850000000
  echo_val /proc/sys/kernel/sched_util_clamp_min 1024
  echo "已切到 均衡档: 大核下限1.22G / GPU下限512M"
}

apply_perf() {
  echo_val $POL6/scaling_governor performance
  echo_val $POL6/scaling_min_freq 2210000
  echo_val $POL6/scaling_max_freq 2210000
  echo_val $GPU/governor performance
  echo_val $GPU/min_freq 850000000
  echo_val $GPU/max_freq 850000000
  echo_val /proc/sys/kernel/sched_util_clamp_min 1024
  echo_val /proc/sys/kernel/sched_util_clamp_min_rt_default 1024
  echo "已切到 性能档: 大核2.21G / GPU850M 常驻"
}

apply_turbo() {
  # 性能档 + 抬高升频积极性 + 放开温控 IPA 的激进降频
  apply_perf > /dev/null
  echo_val $POL6/uscfreq/up_rate_limit_us 0
  echo_val $POL6/uscfreq/down_rate_limit_us 20000
  echo_val $POL6/uscfreq/freq_margin 5
  echo_val /proc/sys/kernel/sched_energy_aware 0
  echo_val /sys/kernel/debug/sched/features NO_TTWU_QUEUE
  echo "已切到 爆发档: 大核2.21G常驻 + 升频无延迟 + 降频迟钝"
}

status() {
  echo "小核 policy0: gov=$(cat $POL0/scaling_governor) cur=$(cat $POL0/scaling_cur_freq) range=$(cat $POL0/scaling_min_freq)-$(cat $POL0/scaling_max_freq)"
  echo "大核 policy6: gov=$(cat $POL6/scaling_governor) cur=$(cat $POL6/scaling_cur_freq) range=$(cat $POL6/scaling_min_freq)-$(cat $POL6/scaling_max_freq)"
  echo "GPU        : gov=$(cat $GPU/governor) cur=$(cat $GPU/cur_freq) range=$(cat $GPU/min_freq)-$(cat $GPU/max_freq)"
  echo "sched_clamp: min=$(cat /proc/sys/kernel/sched_util_clamp_min) max=$(cat /proc/sys/kernel/sched_util_clamp_max)"
  echo "soc温度    : $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
  echo "当前档位   : $(cat /data/adb/e5u_profile 2>/dev/null)"
}

case "$1" in
  stock) apply_stock;  echo stock > /data/adb/e5u_profile ;;
  mid)   apply_mid;    echo mid   > /data/adb/e5u_profile ;;
  perf)  apply_perf;   echo perf  > /data/adb/e5u_profile ;;
  turbo) apply_turbo;  echo turbo > /data/adb/e5u_profile ;;
  status|"") status ;;
  *) echo "用法: perfctl.sh stock|mid|perf|turbo|status" ;;
esac
