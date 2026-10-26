#!/system/bin/sh
# charge-guard supervisor — daemon 死亡 5s 内自动复活；disable 文件退出
MODDIR=${0%/*}
PIDF=/data/adb/charge-guard.pid
while :; do
    [ -f "$MODDIR/disable" ] && exit 0
    PID=$(cat "$PIDF" 2>/dev/null)
    ALIVE=0
    if [ -n "$PID" ] && [ -r "/proc/$PID/cmdline" ]; then
        case "$(tr '\000' ' ' < "/proc/$PID/cmdline")" in
            *"sh $MODDIR/charge-guard.sh"*) ALIVE=1;;
        esac
    fi
    [ "$ALIVE" = 0 ] && /system/bin/sh "$MODDIR/charge-guard.sh"
    sleep 5
done
