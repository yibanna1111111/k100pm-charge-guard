#!/system/bin/sh
# charge-guard daemon — songyuan (REDMI K100 Pro Max) · author: yibanna
# 亮屏期间把 wired_chg_curr 顶回满速目标；温控越线放权给原生 mi_thermald。
# 纯 sysfs 运行时写入，零持久修改，杀掉/重启即恢复原生行为。

MODDIR=/data/adb/modules/charge-guard
LOG=/data/adb/charge-guard.log
PIDF=/data/adb/charge-guard.pid
DISABLE=$MODDIR/disable
NODE=/sys/class/xm_power/charger/charger_thermal/wired_chg_curr
TARGET=15600000            # 满速目标(µA)，驱动自会钳到可达值
BAT_HI=48000; BAT_LO=44000 # 电池温控墙(m°C)：越线放权 / 回落接管（对齐 ACC 50/45 略严）
CHG_HI=58000; CHG_LO=52000 # charger_therm 温控墙（轻载基线实测 ~44°C）
NTFY=https://ntfy.yibanna.dpdns.org/hermes-alert
CURL=/data/data/com.termux/files/usr/bin/curl

log() { echo "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG"; }

# 温控区按名字解析（zone 编号跨重启不保证稳定）
BATZ=""; CHGZ=""
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null)
  [ "$t" = "battery" ] && BATZ=$z
  [ "$t" = "charger_therm" ] && CHGZ=$z
done
[ -z "$BATZ" ] || [ ! -e "$NODE" ] && { log "FATAL: nodes missing (batz=$BATZ node ok=$([ -e "$NODE" ] && echo y))"; exit 1; }
log "start pid=$$ batz=$BATZ($(/system/bin/basename $BATZ)) chgz=${CHGZ:-none}"

alert() {
  log "ALERT: $1"
  [ -x "$CURL" ] && "$CURL" -m 5 -f -X POST -o /dev/null \
    -H "Title: charge-guard" -H "Priority: high" \
    -d "$1" "$NTFY" 2>/dev/null
}

echo $$ > "$PIDF"
ENGAGED=1; TICK=0
while :; do
  [ -f "$DISABLE" ] && { log "disable file, exit"; rm -f "$PIDF"; exit 0; }
  BT=$(cat "$BATZ/temp" 2>/dev/null); BT=${BT:-0}
  CT=0; [ -n "$CHGZ" ] && CT=$(cat "$CHGZ/temp" 2>/dev/null) && CT=${CT:-0}
  SCREEN=$(dumpsys power 2>/dev/null | grep -m1 mWakefulness)

  case "$SCREEN" in *Awake*) AWAKE=1;; *) AWAKE=0;; esac

  if [ "$ENGAGED" = 1 ]; then
    if [ "$BT" -ge "$BAT_HI" ] || [ "$CT" -ge "$CHG_HI" ]; then
      ENGAGED=0
      alert "温控放权原生策略 电池$((BT/1000)).$((BT/100%10))°C charger$((CT/1000)).$((CT/100%10))°C"
    elif [ "$AWAKE" = 1 ]; then
      echo "$TARGET" > "$NODE" 2>/dev/null
    fi
  else
    if [ "$BT" -le "$BAT_LO" ] && [ "$CT" -le "$CHG_LO" ]; then
      ENGAGED=1; log "温控回落恢复接管 bat=$((BT/1000))°C chg=$((CT/1000))°C"
    fi
  fi

  # 60s 心跳一行，日志超 200KB 截尾
  TICK=$((TICK+5))
  if [ "$TICK" -ge 60 ]; then
    TICK=0
    A=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
    C=$(cat "$NODE" 2>/dev/null)
    log "hb eng=$ENGAGED awake=$AWAKE bat=$((BT/1000)).$((BT/100%10)) chg=$((CT/1000)).$((CT/100%10)) node=$C actual=$A"
    [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 204800 ] && { tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
  fi
  sleep 5
done
