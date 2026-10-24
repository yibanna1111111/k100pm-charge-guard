# charge-guard

REDMI K100 Pro Max（songyuan）亮屏充电提速 KernelSU/Magisk 模块。

## 问题

HyperOS 亮屏时 `mi_thermald` 把充电电流强制压到 ~4A（实测 18W，灭屏 34-41W），
即使电池温度只有 34-37°C、充电器功率充足。这是策略性限流，不是热保护。

## 原理

常驻 daemon 在**亮屏且温度正常**时每 5s 把真实控制节点顶回满速目标：

```
/sys/class/xm_power/charger/charger_thermal/wired_chg_curr = 15600000  (µA)
```

`/sys/class/power_supply/battery/` 下的 `charge_control_limit` 等公开节点是摆设，写入无效。
`mi_thermald` 约 15-25s 回写压制，所以需要 daemon 持续对抗。

**纯 sysfs 运行时写入，零持久修改。杀掉 daemon 或重启 = 原生行为立即恢复。**

## 温控墙（fail-safe）

| 传感器 | 越线放权 | 回落接管 |
|---|---|---|
| battery | ≥48°C | ≤44°C |
| charger_therm | ≥58°C | ≤52°C |

- 越线：daemon 停写，原生 `mi_thermald` 策略立即接管，并发 ntfy 推送告警（可选，删掉 `NTFY` 行即禁用）。
- daemon 崩溃 = 不写 = 原生接管，无残留风险。
- 阈值参考社区主流模块 ACC 的默认值（max 50 / resume 45）略严一档，因为本模块是主动顶流。

## 实测效果

| 场景 | 模块关 | 模块开 |
|---|---|---|
| 亮屏充电（SOC 78%，安克 55W PD 头） | ~4.3A / 18W | ~5.3A / 23W |
| 灭屏充电 | 不受影响 | 不受影响 |

注意两层物理上限，软件无法突破：

1. **充电器合同**：第三方 PD/PPS 头按协商功率封顶（如 18.6V×3A≈55W）；小米原装头走私有 MIPPS 协议才跑满 100W。
2. **CV 涓流区**：SOC >80% 后电池进入恒压收尾，电流自然衰减，这是锂电池电化学特性。**强推涓流电流 = 镀锂/鼓包/热失控风险，本模块不做，也请不要用任何手段尝试。**

## 安装

**方式一（推荐）**：下载 [charge-guard-v1.3.zip](https://github.com/yibanna1111111/k100pm-charge-guard/releases/download/v1.3/charge-guard-v1.3.zip)，KernelSU / Magisk App 里「从本地安装」直接刷入，重启生效。

**方式二（手动）**：

```sh
# 复制模块文件到手机后：
su -c 'mkdir -p /data/adb/modules/charge-guard'
su -c 'cp module.prop service.sh charge-guard.sh /data/adb/modules/charge-guard/'
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

- 日志：`/data/adb/charge-guard.log`（60s 心跳：eng/awake/node/actual）
- daemon 状态：`kill -0 $(su -c 'cat /data/adb/charge-guard.pid')`
- 温控区按 `type` 名解析（battery / charger_therm），zone 编号跨重启不保证稳定
- 改阈值：编辑 `charge-guard.sh` 顶部 `BAT_HI/BAT_LO/CHG_HI/CHG_LO`，kill pid 后重跑 `service.sh`
  （**不要 `sed -i` 运行中的 sh 脚本**，sh 增量读文件会打死 daemon）

## 适配其他机型

控制节点路径因平台而异。找法：亮屏充电时逐个 `cat` `/sys/class/*power*/**/*curr*`，
被 `mi_thermald`/`thermald` 周期性回写压制的可写节点即目标。原理相通，节点自测。

## License

MIT

author: yibanna
