#!/system/bin/sh
# charge-guard daemon — songyuan (REDMI K100 Pro Max) · author: yibanna
# Dual-cap conservative controller. Native thermald, JEITA and voltage taper remain active.
# Runtime sysfs writes only. Clean shutdown hands back conservative votes, not stale maxima.
PATH=/system/bin:/system/xbin:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=${0%/*}
ROOT=${CG_ROOT:-}
STATE=$ROOT/data/adb
LOG=$STATE/charge-guard.log
PIDF=$STATE/charge-guard.pid
LOCK=$STATE/charge-guard.lock
NODE=$ROOT/sys/class/xm_power/charger/charger_thermal
# Driver creates gates 0444 each boot; root must open the write bit before voting.
chmod 0666 "$NODE/wired_chg_curr" "$NODE/wired_ctrl_limit" 2>/dev/null || true
PS=$ROOT/sys/class/power_supply/battery
INTERVAL=${CG_INTERVAL:-1}
MAX_TICKS=${CG_TICKS:-0}
SOC_GATE=${CG_SOC_GATE:-90}
mkdir -p "$STATE" || exit 1
. "$MODDIR/policy.sh" || exit 1
log() { printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
read_value() { cat "$1" 2>/dev/null; }
valid_temp() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ "${#1}" -le 6 ] && [ "$1" -ge 1000 ] && [ "$1" -le 100000 ]
}
max_temp() {
    maximum=0
    for temperature in "$@"; do
        valid_temp "$temperature" || { echo 0; return; }
        [ "$temperature" -gt "$maximum" ] && maximum=$temperature
    done
    echo "$maximum"
}
pid_matches() {
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    case "$(tr '\000' ' ' < "/proc/$1/cmdline")" in
        *"sh $MODDIR/charge-guard.sh"*) return 0;;
        *) return 1;;
    esac
}
if ! mkdir "$LOCK" 2>/dev/null; then
    owner=$(read_value "$LOCK/pid")
    if [ -z "$owner" ]; then sleep 1; owner=$(read_value "$LOCK/pid"); fi
    pid_matches "$owner" && exit 0
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null || exit 0
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$LOCK/pid"
printf '%s\n' "$$" > "$PIDF"
OWNED=0
release() {
    [ "$OWNED" = 1 ] || return 0
    # A one-time conservative handoff; the running native service can replace it.
    sys_w '2000000' "$NODE/wired_chg_curr" 2>/dev/null
    sys_w '12' "$NODE/wired_ctrl_limit" 2>/dev/null
    OWNED=0
    log 'handoff conservative level=12 sic=2000000; native controls subsequent updates'
}
cleanup() {
    release
    [ "$(read_value "$PIDF")" = "$$" ] && rm -f "$PIDF"
    [ "$(read_value "$LOCK/pid")" = "$$" ] && { rm -f "$LOCK/pid"; rmdir "$LOCK"; }
    log "stop pid=$$"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
BATZ=; FGZ=; CHGZ=; QUIETZ=; PORTZ=; PORT2Z=
for zone in "$ROOT"/sys/class/thermal/thermal_zone*; do
    case "$(read_value "$zone/type")" in
        battery) BATZ=$zone;; batt_temp) FGZ=$zone;; charger_therm) CHGZ=$zone;;
        quiet_therm) QUIETZ=$zone;; conn_therm) PORTZ=$zone;; conn_therm2) PORT2Z=$zone;;
    esac
done
log "start v1.4 pid=$$ battery=$BATZ gauge=$FGZ charger=$CHGZ"
COOLING=0; TICK=0; PREVIOUS=; TIER=YIELD; DWELL=0
sys_w() { printf "$1\n" > "$2" 2>/dev/null && return 0; chmod 0666 "$2" 2>/dev/null; printf "$1\n" > "$2" 2>/dev/null; }
apply_tier() {
    case "$1" in
        FAST)  sys_w '15600000' "$NODE/wired_chg_curr" || return 1
               sys_w '0' "$NODE/wired_ctrl_limit" || return 1
               OWNED=1;;
        BOOST) sys_w '6000000' "$NODE/wired_chg_curr" || return 1
               sys_w '6' "$NODE/wired_ctrl_limit" || return 1
               OWNED=1;;
        *)     release;;
    esac
    return 0
}
while :; do
    [ -f "$MODDIR/disable" ] && { log 'disable file, exit'; exit 0; }
    GAUGE=$(read_value "$PS/temp")
    case "$GAUGE" in ''|*[!0-9]*) GAUGE=0;; *)
        if [ "${#GAUGE}" -le 4 ]; then GAUGE=$((GAUGE*100)); else GAUGE=0; fi;;
    esac
    B=$(max_temp "$(read_value "$BATZ/temp")" "$(read_value "$FGZ/temp")" "$GAUGE")
    C=$(read_value "$CHGZ/temp")
    BOARD=$(max_temp "$(read_value "$QUIETZ/temp")" "$(read_value "$ROOT/sys/class/thermal/thermal_message/board_sensor_temp")")
    PORT=$(max_temp "$(read_value "$PORTZ/temp")" "$(read_value "$PORT2Z/temp")")
    SOC=$(read_value "$PS/capacity")
    ONLINE=$(read_value "$ROOT/sys/class/power_supply/usb/online")
    NEXT=$(cg_decide "$B" "$C" "$BOARD" "$PORT" "$SOC" "$ONLINE" "$COOLING" "$TIER" "$DWELL" "$SOC_GATE")
    apply_tier "$NEXT" || { log 'write failure, exit to native'; exit 1; }
    if [ "$NEXT" = "$TIER" ]; then DWELL=$((DWELL+1)); else DWELL=0; fi
    TIER=$NEXT
    [ "$NEXT" = YIELD ] && COOLING=1 || COOLING=0
    if [ "$TIER" != "$PREVIOUS" ] || [ $((TICK%10)) -eq 0 ]; then
        log "tier=$TIER screen=$(read_value "$ROOT/sys/class/thermal/thermal_message/screen_state") bat=$B chg=$C board=$BOARD port=$PORT soc=$SOC level=$(read_value "$NODE/wired_ctrl_limit") sic=$(read_value "$NODE/wired_chg_curr") actual=$(read_value "$PS/current_now") voltage=$(read_value "$PS/voltage_now")"
        PREVIOUS=$TIER
        size=$(wc -c < "$LOG")
        [ "$size" -gt 204800 ] && { tail -n 150 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
    fi
    TICK=$((TICK+1))
    [ "$MAX_TICKS" -gt 0 ] && [ "$TICK" -ge "$MAX_TICKS" ] && exit 0
    sleep "$INTERVAL"
done
