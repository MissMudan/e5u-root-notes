#!/system/bin/sh
# E5U 性能档开机自动应用
sleep 20
PROFILE=$(cat /data/adb/e5u_profile 2>/dev/null)
[ "$PROFILE" = "stock" ] && exit 0
[ -n "$PROFILE" ] && sh /data/adb/perfctl.sh "$PROFILE"
exit 0
