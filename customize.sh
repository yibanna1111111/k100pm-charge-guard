#!/system/bin/sh
# charge-guard installer hooks

ui_print "- Charge Guard v1.4: 双闸同调亮屏充电提速守护"
ui_print "- 三档温控: FAST(凉) / BOOST(温) / 放权原生(热)"
ui_print "- 纯 sysfs 运行时写入, 重启即恢复原生"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/policy.sh" 0 0 0755
set_perm "$MODPATH/charge-guard.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- 重启后 daemon 自动启动，亮屏即生效"
