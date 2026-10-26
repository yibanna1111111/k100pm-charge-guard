#!/system/bin/sh
# Pure tier policy. Temps millidegrees C, SOC percent.
# Tiers: FAST(level0 native table 15.6A) / BOOST(level6 6A) / YIELD(level12 native).
# Hysteresis: entry gates are stricter than exit gates. $8 = current tier, $9 = ticks in tier.
# These gates are engineering choices, not manufacturer ratings. JEITA/voltage taper stay native.
cg_fast_entry() {
    [ "$1" -lt 42000 ] && [ "$2" -lt 52000 ] && [ "$3" -lt 42000 ] && [ "$4" -lt 41000 ]
}
cg_fast_exit() {
    [ "$1" -ge 43500 ] || [ "$2" -ge 55000 ] || [ "$3" -ge 43500 ] || [ "$4" -ge 42500 ]
}
cg_boost_ok() {
    [ "$1" -lt 44500 ] && [ "$2" -lt 57000 ] && [ "$3" -lt 44000 ] && [ "$4" -lt 43000 ]
}
cg_decide() {
    # battery(max sensor), charger, board(max skin), connector, SOC, online, cooling, tier, dwell, soc_gate
    [ "$#" -eq 10 ] || { echo 'YIELD'; return; }
    for value in "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$9" "${10}"; do
        case "$value" in ''|*[!0-9]*) echo 'YIELD'; return;; esac
        [ "${#value}" -le 6 ] || { echo 'YIELD'; return; }
    done
    for value in "$1" "$2" "$3" "$4"; do
        [ "$value" -ge 1000 ] && [ "$value" -le 100000 ] || { echo 'YIELD'; return; }
    done
    [ "$5" -le 100 ] && [ "$6" -le 1 ] || { echo 'YIELD'; return; }
    [ "$6" -eq 1 ] || { echo 'YIELD'; return; }
    [ "${10}" -le 100 ] || { echo 'YIELD'; return; }
    [ "$5" -lt "${10}" ] || { echo 'YIELD'; return; }
    case "$8" in FAST|BOOST|YIELD) ;; *) echo 'YIELD'; return;; esac
    # After a yield, re-entry needs stricter temps than normal entry (hysteresis).
    if [ "$7" -eq 1 ]; then
        if [ "$1" -lt 40000 ] && [ "$2" -lt 50000 ] && [ "$3" -lt 40000 ] && [ "$4" -lt 39000 ]; then
            echo 'FAST'
        elif [ "$1" -lt 42000 ] && [ "$2" -lt 55000 ] && [ "$3" -lt 42000 ] && [ "$4" -lt 41000 ]; then
            echo 'BOOST'
        else echo 'YIELD'
        fi
        return
    fi
    if [ "$8" = FAST ] && [ "$9" -lt 10 ]; then
        cg_fast_exit "$1" "$2" "$3" "$4" || { echo 'FAST'; return; }
    fi
    if cg_fast_entry "$1" "$2" "$3" "$4"; then echo 'FAST'
    elif cg_boost_ok "$1" "$2" "$3" "$4"; then echo 'BOOST'
    else echo 'YIELD'
    fi
}
