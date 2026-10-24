"""Execute the shipped shell policy; no Python policy reimplementation."""
import os
import pathlib
import subprocess
import tempfile
import unittest

POLICY = pathlib.Path(__file__).resolve().parents[1] / "module" / "policy.sh"


class PolicyTests(unittest.TestCase):
    def decide(self, values):
        self.assertTrue(POLICY.is_file(), "fail-closed dual-cap policy is missing")
        command = '. "$1"; shift; cg_decide "$@"'
        result = subprocess.run(
            ["sh", "-c", command, "test", str(POLICY), *map(str, values)],
            text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()


class TierTests(PolicyTests):
    COOL = [41000, 48000, 39000, 38000, 70, 1, 0]

    def tier(self, values, current="YIELD", dwell=0, gate=80):
        return self.decide([*values, current, dwell, gate])

    def test_invalid_sensor_must_not_boost(self):
        for invalid in ["", "NaN", "-1", "0", "999999"]:
            with self.subTest(invalid=invalid):
                self.assertEqual(self.tier([invalid, 48000, 39000, 38000, 70, 1, 0]), "YIELD")

    def test_cool_on_and_off_reach_fast_from_native(self):
        self.assertEqual(self.tier(self.COOL), "FAST")
        self.assertEqual(self.tier([39000, 49000, 39000, 38000, 70, 1, 0], "YIELD"), "FAST")

    def test_warm_tiers_and_hot_yield(self):
        self.assertEqual(self.tier([43000, 53000, 43000, 42500, 70, 1, 0]), "BOOST")
        self.assertEqual(self.tier([45000, 53000, 43000, 42000, 70, 1, 0]), "YIELD")
        self.assertEqual(self.tier([41000, 58000, 39000, 38000, 70, 1, 0]), "YIELD")
        self.assertEqual(self.tier([41000, 48000, 39000, 38000, 80, 1, 0]), "YIELD")
        self.assertEqual(self.tier([41000, 48000, 39000, 38000, 70, 0, 0]), "YIELD")
        # cooling=1 re-entry: strict FAST gate, else BOOST gate, else stay YIELD
        self.assertEqual(self.tier([41000, 48000, 39000, 38000, 70, 1, 1]), "BOOST")
        self.assertEqual(self.tier([39000, 49000, 39000, 38000, 70, 1, 1]), "FAST")
        self.assertEqual(self.tier([43000, 48000, 39000, 38000, 70, 1, 1]), "YIELD")

    def test_soc_gate_is_configurable(self):
        self.assertEqual(self.tier([41000, 48000, 39000, 38000, 82, 1, 0]), "YIELD")
        self.assertEqual(self.tier([41000, 48000, 39000, 38000, 82, 1, 0], gate=100), "FAST")

    def test_fast_hysteresis_and_dwell(self):
        mid = [42800, 53000, 42500, 41500, 70, 1, 0]
        self.assertEqual(self.tier(mid, "BOOST"), "BOOST")
        self.assertEqual(self.tier(mid, "FAST", 20), "BOOST")
        self.assertEqual(self.tier(mid, "FAST", 2), "FAST")
        hot = [44000, 56000, 44000, 43000, 70, 1, 0]
        self.assertEqual(self.tier(hot, "FAST", 2), "YIELD")


class DaemonTests(unittest.TestCase):
    def run_daemon(self, invalid=False):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            files = {
                'sys/class/power_supply/battery/temp': '390',
                'sys/class/power_supply/battery/capacity': '70',
                'sys/class/power_supply/battery/current_now': '-9000000',
                'sys/class/power_supply/battery/voltage_now': '4300000',
                'sys/class/power_supply/usb/online': '1',
                'sys/class/thermal/thermal_message/board_sensor_temp': '39000',
                'sys/class/thermal/thermal_message/screen_state': '1',
                'sys/class/xm_power/charger/charger_thermal/wired_ctrl_limit': '12',
                'sys/class/xm_power/charger/charger_thermal/wired_chg_curr': '2000000',
            }
            sensors = [('battery', 'bad' if invalid else '41000'),
                       ('batt_temp', '39000'), ('charger_therm', '48000'),
                       ('quiet_therm', '39000'), ('conn_therm', '38000'),
                       ('conn_therm2', '38000')]
            for i, (name, temp) in enumerate(sensors):
                files[f'sys/class/thermal/thermal_zone{i}/type'] = name
                files[f'sys/class/thermal/thermal_zone{i}/temp'] = temp
            for name, value in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value + '\n')
            env = dict(os.environ, CG_ROOT=str(root), CG_TICKS='2', CG_INTERVAL='0')
            result = subprocess.run(['sh', str(POLICY.parent / 'charge-guard.sh')],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            log = (root / 'data/adb/charge-guard.log').read_text()
            level = (root / 'sys/class/xm_power/charger/charger_thermal/wired_ctrl_limit').read_text().strip()
            current = (root / 'sys/class/xm_power/charger/charger_thermal/wired_chg_curr').read_text().strip()
            self.assertFalse((root / 'data/adb/charge-guard.pid').exists())
            return log, level, current

    def test_fast_dual_cap_and_conservative_exit(self):
        log, level, current = self.run_daemon()
        self.assertIn('tier=FAST', log)
        self.assertIn('level=0 sic=15600000', log)
        self.assertEqual((level, current), ('12', '2000000'))

    def test_invalid_sensor_leaves_native_controls_untouched(self):
        log, level, current = self.run_daemon(invalid=True)
        self.assertIn('tier=YIELD', log)
        self.assertNotIn('tier=FAST', log)
        self.assertEqual((level, current), ('12', '2000000'))


if __name__ == "__main__":
    unittest.main()
