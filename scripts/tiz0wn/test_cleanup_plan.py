"""Offline tests for Q80T cleanup plan; creates only synthetic temporary DBs."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = Path(__file__).with_name("cleanup-plan.py")
spec = importlib.util.spec_from_file_location("danstv_cleanup", MODULE)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)


class CleanupPlanTests(unittest.TestCase):
    def setUp(self):
        (ROOT / ".local").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="danstv-cleanup-", dir=ROOT / ".local")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.snapshot = self.work / "snapshot.db"
        self.profile = self.work / "profile.json"
        self.connection = sqlite3.connect(self.snapshot)
        self.addCleanup(self.connection.close)
        self.connection.executescript("""
          CREATE TABLE package_app_info(
            app_id TEXT PRIMARY KEY,
            app_disable TEXT,
            app_onboot TEXT,
            app_autorestart TEXT
          );
          INSERT INTO package_app_info VALUES
            ('com.example.ads-service','false','true','true'),
            ('org.example.voice','false','false','true'),
            ('org.tizen.tv-viewer','false','true','true'),
            ('com.samsung.tv.csfs','false','true','true'),
            ('com.samsung.tv.coba.setting','false','true','true');
        """)
        self.connection.commit()
        self.selected = ["advertising", "voice"]
        self.write_profile()

    def write_profile(self, **changes):
        profile = {
            "model": planner.MODEL,
            "firmware": planner.FIRMWARE,
            "registry": "/opt/dbspace/.pkgmgr_parser.db",
            "groups": {
                "advertising": {
                    "description": "Synthetic fixture, not a real Samsung bloat ID",
                    "apps": [{
                        "id": "com.example.ads-service",
                        "reason": "Synthetic test advertising component",
                        "evidence": "Synthetic Q80T fixture, not live TV evidence",
                    }],
                },
                "voice": {
                    "description": "Synthetic fixture, not a real Samsung bloat ID",
                    "apps": [{
                        "id": "org.example.voice",
                        "reason": "Synthetic test voice component",
                        "evidence": "Synthetic Q80T fixture, not live TV evidence",
                    }],
                },
            },
        }
        profile.update(changes)
        self.profile.write_text(json.dumps(profile), encoding="utf-8")
        return profile

    def flags(self):
        return {
            row[0]: row[1:]
            for row in self.connection.execute(
                "SELECT app_id,app_disable,app_onboot,app_autorestart "
                "FROM package_app_info ORDER BY app_id"
            )
        }

    def test_inventory_is_read_only_and_marks_critical_ids(self):
        original = self.flags()
        out = self.work / "inventory"
        planner.inspect(self.snapshot, out)
        data = json.loads((out / "inventory.json").read_text())
        self.assertEqual(data["target_model"], planner.MODEL)
        items = {item["app_id"]: item for item in data["apps"]}
        self.assertTrue(items["com.samsung.tv.csfs"]["protected"])
        self.assertTrue(items["org.tizen.tv-viewer"]["protected"])
        self.assertFalse(items["org.example.voice"]["protected"])
        self.assertEqual(self.flags(), original)

    def test_round_trip_restores_every_selected_flag(self):
        original = self.flags()
        out = self.work / "plan"
        planner.plan(self.snapshot, self.profile, self.selected, out)
        before = json.loads((out / "before.json").read_text())
        self.assertEqual(len(before["apps"]), 2)
        self.assertEqual(self.flags(), original)
        self.connection.executescript((out / "apply.sql").read_text())
        applied = self.flags()
        for name in ("com.example.ads-service", "org.example.voice"):
            self.assertEqual(applied[name], planner.DISABLED)
        for name in ("com.samsung.tv.csfs", "org.tizen.tv-viewer", "com.samsung.tv.coba.setting"):
            self.assertEqual(applied[name], original[name])
        self.connection.executescript((out / "restore.sql").read_text())
        self.assertEqual(self.flags(), original)

    def test_drift_refuses_to_apply_any_change(self):
        out = self.work / "plan"
        planner.plan(self.snapshot, self.profile, self.selected, out)
        self.connection.execute(
            "UPDATE package_app_info SET app_autorestart='false' WHERE app_id='org.example.voice'"
        )
        self.connection.commit()
        original = self.flags()
        with self.assertRaises(sqlite3.IntegrityError):
            self.connection.executescript((out / "apply.sql").read_text())
        self.connection.rollback()
        self.assertEqual(self.flags(), original)

    def test_drift_refuses_restore(self):
        out = self.work / "plan"
        planner.plan(self.snapshot, self.profile, self.selected, out)
        self.connection.executescript((out / "apply.sql").read_text())
        self.connection.execute(
            "UPDATE package_app_info SET app_onboot='true' WHERE app_id='org.example.voice'"
        )
        self.connection.commit()
        original = self.flags()
        with self.assertRaises(sqlite3.IntegrityError):
            self.connection.executescript((out / "restore.sql").read_text())
        self.connection.rollback()
        self.assertEqual(self.flags(), original)

    def test_rejects_wrong_model_and_firmware(self):
        for changed in ({"model": "DifferentModel"}, {"firmware": "T-OTHER-9999"}):
            self.write_profile(**changed)
            with self.assertRaisesRegex(ValueError, "exact Q80T"):
                planner.read_profile(self.profile, self.selected)
        self.write_profile()

    def test_refuses_critical_id_and_unproven_candidates(self):
        profile = self.write_profile()
        profile["groups"]["advertising"]["apps"][0]["id"] = "org.tizen.tv-viewer"
        self.profile.write_text(json.dumps(profile))
        with self.assertRaisesRegex(ValueError, "Protected"):
            planner.read_profile(self.profile, ["advertising"])
        profile["groups"]["advertising"]["apps"][0]["id"] = "com.example.ads-service"
        profile["groups"]["advertising"]["apps"][0].pop("evidence")
        self.profile.write_text(json.dumps(profile))
        with self.assertRaisesRegex(ValueError, "evidence required"):
            planner.read_profile(self.profile, ["advertising"])

    def test_duplicate_ids_missing_rows_and_unexpected_values(self):
        profile = self.write_profile()
        profile["groups"]["voice"]["apps"][0]["id"] = "com.example.ads-service"
        self.profile.write_text(json.dumps(profile))
        with self.assertRaisesRegex(ValueError, "multiple selected groups"):
            planner.read_profile(self.profile, self.selected)
        self.write_profile()
        with self.assertRaisesRegex(ValueError, "expected one registry row"):
            planner.fetch_flags(self.connection, "org.example.not-installed")
        self.connection.execute(
            "UPDATE package_app_info SET app_disable='0' WHERE app_id='org.example.voice'"
        )
        self.connection.commit()
        with self.assertRaisesRegex(ValueError, "Unknown registry flag"):
            planner.plan(self.snapshot, self.profile, self.selected, self.work / "no-output")

    def test_denies_plan_without_targets_and_overwriting_output(self):
        self.write_profile(groups={"advertising": {"apps": []}})
        with self.assertRaisesRegex(ValueError, "No approved app"):
            planner.read_profile(self.profile, ["advertising"])
        with self.assertRaisesRegex(ValueError, "inside .local"):
            planner.private_output(ROOT / "private-snapshot-output")
        (self.work / "exists").mkdir()
        with self.assertRaisesRegex(ValueError, "already exists"):
            planner.private_output(self.work / "exists")

    def test_schema_guard(self):
        missing = self.work / "missing-schema.db"
        with sqlite3.connect(missing) as connection:
            connection.execute("CREATE TABLE wrong_schema(id TEXT)")
        with self.assertRaisesRegex(ValueError, "Unknown package_app_info schema"):
            planner.open_snapshot(missing)


if __name__ == "__main__":
    unittest.main(verbosity=2)
