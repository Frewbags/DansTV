"""Offline tests for Q80T private report assessment; never contacts a device."""
import importlib.util
from pathlib import Path
import unittest

module_path = Path(__file__).with_name("assess-snapshot.py")
spec = importlib.util.spec_from_file_location("snapshot_assessment", module_path)
assessor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assessor)


def fixture(keys=True, context=True, valid=True):
    result = [
        "DANSTV-ROOT-CHANNEL mode=Snapshot",
        "DANSTV-EUID=0",
        "=== Timestamp / platform ===",
        "Sample Q80T inventory (fake data)",
        "=== Home / startup preference inventory (read-only) ===",
    ]
    if keys:
        result.extend([
            "db/appfw/home_appid: string com.samsung.tv.csfs",
            "db/appfw/startup_appid: string com.samsung.tv.csfs",
            "db/appfw/booting_appid_backup: (not readable or absent)",
            "db/first_screen/type: string com.samsung.tv.csfs",
            "db/menu/smart_hub/ontvsetting/auto_start: int 1",
        ])
    result.extend([
        "Version=T-NKMUABC-2743.0;",
        "Native main-operation handler: not measured by this shell survey",
        "=== Home key context (read-only) ===",
    ])
    if context:
        result.extend(["appid|key|request|target_selector|args",
                       "com.samsung.tv.csfs|XF86Home|launch|package:com.samsung.tv.csfs|sample"])
    else:
        result.append("No readable app-context database")
    result.extend(["=== End of snapshot ===", "DANSTV-EXIT=0" if valid else "DANSTV-EXIT=1",
                   "DANSTV-END-OF-REPORT", ""])
    return "\n".join(result)


class AssessmentTests(unittest.TestCase):
    def test_fingerprint_and_home_inventory(self):
        result = assessor.assess(fixture())
        self.assertEqual(result["firmware_marker"], "matched")
        self.assertEqual(result["home_key_filter"], "observed")
        self.assertEqual(result["home_prefs"]["db/appfw/home_appid"], "reported")
        self.assertEqual(result["home_prefs"]["db/appfw/booting_appid_backup"], "unavailable")
        self.assertEqual(result["native_main_operation"], "not measured")
        self.assertFalse(result["home_change_authorised"])

    def test_missing_home_inventory_is_not_assumed(self):
        result = assessor.assess(fixture(keys=False, context=False))
        self.assertTrue(all(x == "missing" for x in result["home_prefs"].values()))
        self.assertEqual(result["home_key_filter"], "unavailable")
        self.assertFalse(result["home_change_authorised"])

    def test_firmware_must_be_reported_once_in_the_dedicated_section(self):
        expected = "Version=T-NKMUABC-2743.0;"
        wrong = assessor.assess(fixture().replace(expected, "Version=T-OTHER-2743.0;"))
        self.assertEqual(wrong["firmware_marker"], "not observed")

        misplaced = fixture().replace(expected, "Version=unknown;")
        misplaced = misplaced.replace("Sample Q80T inventory (fake data)",
                                      expected + "\nSample Q80T inventory (fake data)")
        self.assertEqual(assessor.assess(misplaced)["firmware_marker"], "not observed")

        repeated = fixture().replace(expected, expected + "\n" + expected)
        self.assertEqual(assessor.assess(repeated)["firmware_marker"], "not observed")

    def test_rejects_failed_or_spoofed_report_markers(self):
        for report in (
            fixture(valid=False),
            fixture().replace("DANSTV-EUID=0", "DANSTV-EUID=901"),
            fixture().replace("DANSTV-END-OF-REPORT", "TRUNCATED"),
        ):
            with self.assertRaises(ValueError):
                assessor.assess(report)

    def test_does_not_expose_snapshot_values_in_summary(self):
        result = assessor.assess(fixture())
        joined = "\n".join(result["home_prefs"].values())
        self.assertNotIn("com.samsung.tv.csfs", joined)
        self.assertNotIn("192.", joined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
