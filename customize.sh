#!/system/bin/sh
# charge-guard installer hooks

ui_print "- Charge Guard v1.1: 亮屏充电提速守护"
ui_print "- 温控墙: 电池 48/44°C, charger 58/52°C"
ui_print "- 纯 sysfs 运行时写入, 重启即恢复原生"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/charge-guard.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- 重启后 daemon 自动启动，亮屏即生效"
