#!/system/bin/sh
# 卸载：杀 daemon + 删模块目录。sysfs 写入本身不持久，原生策略 15s 内自动接管。
PID=$(cat /data/adb/charge-guard.pid 2>/dev/null)
[ -n "$PID" ] && kill "$PID" 2>/dev/null
rm -f /data/adb/charge-guard.pid /data/adb/charge-guard.log
rm -rf /data/adb/modules/charge-guard
echo "charge-guard removed"
