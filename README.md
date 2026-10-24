# charge-guard

REDMI K100 Pro Max（songyuan）亮屏充电提速 KernelSU/Magisk 模块。

## 问题

HyperOS 亮屏时 `mi_thermald` 把充电电流强制压到 ~4A（实测 18W，灭屏 34-41W），
即使电池温度只有 34-37°C、充电器功率充足。这是策略性限流，不是热保护。

## 原理

充电限流有**两道闸**，驱动取两者较小值（设备树 `mca_charger_thermal/wired_thermal`，19 档温控表，注意 DT 属性是**大端序**）：

```
实际协议电流 = min( wired_chg_curr 写入值, wired_ctrl_limit 档位对应电流表值 )
```

亮屏时 `mi_thermald` 把 `wired_ctrl_limit` 压到 12 档（PPS 仅 2A），只顶 `wired_chg_curr` 无效——这是 v1.3 之前提速失败的根因。

v1.4 daemon 每 1s **双闸同调**，按温度分三档：

| 档 | wired_ctrl_limit | wired_chg_curr | 进入条件（全部满足） |
|---|---|---|---|
| FAST | 0 | 15600000 | 电池<42 charger<52 板温<42 接口<41 |
| BOOST | 6 | 6000000 | 电池<44.5 charger<57 板温<44 接口<43 |
| YIELD | 放权原生 | 放权原生 | 其余（含传感器读数非法 = fail-closed） |

- 迟滞：FAST 退出线比进入线宽 1.5°C 且驻留 <10s 不降档；YIELD 后再进档需更严门槛。
- SOC ≥90（`CG_SOC_GATE`）放权原生涓流，绝不强推恒压收尾电流。
- 传感器取多源最大值（thermal battery zone / 燃料计 / charger / 板温 / 双接口），任一非法即整体放权。
- 退出/停用只写一次保守档（level 12 + 2A），后续由原生接管。

`/sys/class/power_supply/battery/` 下的 `charge_control_limit` 等公开节点是摆设，写入无效。

**纯 sysfs 运行时写入，零持久修改。杀掉 daemon 或重启 = 原生行为立即恢复。**

## 实测效果（2026-10-24，安克 PD/PPS 头，合同 ~42W）

| 场景 | v1.3 及以前 | v1.4 |
|---|---|---|
| 亮屏（SOC 82-83%，level 被原生压 12 档） | 1~2W | 峰值 7.58A×4.50V ≈ 34W，稳态 ~6A |
| 灭屏（SOC 77%） | ~42W | 同档不受影响 |
| 亮屏高电量（SOC 84%，CV 区） | — | 放权原生涓流，不强推 |

注意两层物理上限，软件无法突破：

1. **充电器合同**：第三方 PD/PPS 头按协商功率封顶（如 18.6V×3A≈55W）；小米原装头走私有 MIPPS 协议才跑满 100W。
2. **CV 涓流区**：SOC >80% 后电池进入恒压收尾，电流自然衰减，这是锂电池电化学特性。**强推涓流电流 = 镀锂/鼓包/热失控风险，本模块不做，也请不要用任何手段尝试。**

## 安装

**方式一（推荐）**：下载 [charge-guard-v1.3.zip](https://github.com/yibanna1111111/k100pm-charge-guard/releases/download/v1.3/charge-guard-v1.3.zip)，KernelSU / Magisk App 里「从本地安装」直接刷入，重启生效。

**方式二（手动）**：

```sh
# 复制模块文件到手机后：
su -c 'mkdir -p /data/adb/modules/charge-guard'
su -c 'cp module.prop service.sh policy.sh charge-guard.sh /data/adb/modules/charge-guard/'
su -c 'chmod 755 /data/adb/modules/charge-guard/*.sh'
# 重启，或手动拉起：
su -c '/data/adb/modules/charge-guard/service.sh'
```

## 卸载 / 临时停用

```sh
su -c /data/adb/charge-guard-uninstall.sh        # 彻底卸载
su -c 'touch /data/adb/modules/charge-guard/disable'  # 临时停用（daemon 下个循环自退）
```

## 排障

- 日志：`/data/adb/charge-guard.log`（档位切换 + 10s 心跳：tier/温度/level/sic/actual）
- daemon 状态：`kill -0 $(su -c 'cat /data/adb/charge-guard.pid')`
- 温控区按 `type` 名解析（battery / batt_temp / charger_therm / quiet_therm / conn_therm*），zone 编号跨重启不保证稳定
- 改阈值：编辑 `policy.sh` 的 `cg_fast_entry/cg_fast_exit/cg_boost_ok` 与 `charge-guard.sh` 顶部 `SOC_GATE`，kill pid 后重跑 `service.sh`
  （**不要 `sed -i` 运行中的 sh 脚本**，sh 增量读文件会打死 daemon）
- 回归测试：`python -m unittest discover -s tests`（策略纯函数 + 沙箱 daemon，不碰真机节点）

## 适配其他机型

控制节点路径因平台而异。找法：亮屏充电时逐个 `cat` `/sys/class/*power*/**/*curr*`，
被 `mi_thermald`/`thermald` 周期性回写压制的可写节点即目标。原理相通，节点自测。

## License

MIT

author: yibanna
