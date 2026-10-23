#!/system/bin/sh
# KSU service.sh — 开机自启，pidfile 幂等（勿用 pkill -f，会自伤）
MODDIR=${0%/*}
[ -f "$MODDIR/disable" ] && exit 0
if [ -f /data/adb/charge-guard.pid ]; then
  PID=$(cat /data/adb/charge-guard.pid 2>/dev/null)
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && exit 0
fi
setsid /system/bin/sh "$MODDIR/charge-guard.sh" >/dev/null 2>&1 &
