#!/system/bin/sh
# KSU service.sh — 开机自启 supervisor（勿用 pkill -f，会自伤）
# supervisor 内用 cmdline 校验 pidfile 属主，PID 复用不会挡启动；
# 多实例由 daemon 自身锁目录去重，重复运行本脚本无害。
MODDIR=${0%/*}
[ -f "$MODDIR/disable" ] && exit 0
setsid /system/bin/sh "$MODDIR/supervise.sh" >/dev/null 2>&1 &
