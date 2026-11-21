"""Offline tests for the private Q80T Home database backup extractor."""
from __future__ import annotations

import base64
from contextlib import closing
import hashlib
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "home_backup_extractor", HERE / "extract-home-backup.py"
)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HomeBackupTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.db = Path(self.root.name) / "stock.db"
        with closing(sqlite3.connect(self.db)) as conn:
            conn.execute(
                "CREATE TABLE key_filter("
                "appid TEXT, key TEXT, request TEXT, target_selector TEXT, args TEXT)"
            )
            conn.execute(
                "INSERT INTO key_filter VALUES (?,?,?,?,?)",
                ("com.samsung.tv.csfs", "XF86Home", "launch",
                 "package:com.samsung.tv.csfs", "entry_point:smarthub_key"),
            )
            conn.execute(
                "CREATE TABLE managed_app(appid TEXT PRIMARY KEY, ui_type TEXT, source TEXT)"
            )
            conn.execute(
                "INSERT INTO managed_app VALUES ('com.samsung.tv.searchall','UI','test')"
            )
            # closing() closes the connection but does not commit its transaction.
            # Persist the fixture before the read-only verifier opens the DB.
            conn.commit()
        self.data = self.db.read_bytes()
        self.report = self.mkreport(self.data)

    @staticmethod
    def mkreport(data: bytes) -> str:
        digest = hashlib.sha256(data).hexdigest()
        return (
            "DANSTV-EUID=0\n"
            "Version=T-NKMUABC-2743.0;\n"
            f"HOME-DB-BEGIN sha256={digest} bytes={len(data)}\n"
            + base64.b64encode(data).decode("ascii")
            + "\nHOME-DB-END\nDANSTV-EXIT=0\nDANSTV-END-OF-REPORT\n"
        )

    def test_valid_backup_and_stock_row(self):
        self.assertEqual(module.decode_backup(self.report), self.data)
        self.assertEqual(module.verify_sqlite(self.db), (False, True))

    def test_changed_checksum_fails_closed(self):
        altered = self.report.replace("sha256=", "sha256=" + "0", 1)
        with self.assertRaises(module.BackupError):
            module.decode_backup(altered)

    def test_missing_end_fails(self):
        with self.assertRaises(module.BackupError):
            module.decode_backup(self.report.replace("HOME-DB-END", ""))

    def test_duplicate_start_fails(self):
        start = self.report.split("\n")[2]
        with self.assertRaises(module.BackupError):
            module.decode_backup(self.report.replace(start, start + "\n" + start))

    def test_missing_root_exit_fails(self):
        with self.assertRaises(module.BackupError):
            module.decode_backup(self.report.replace("DANSTV-EXIT=0", "DANSTV-EXIT=1"))

    def test_invalid_sqlite_fails(self):
        with self.assertRaises(module.BackupError):
            module.decode_backup(self.mkreport(b"this is not a database" * 200))

    def test_unexpected_home_row_fails(self):
        # sqlite3.Connection's context manager commits, but does not close.
        # Keep both an explicit commit and close for Windows temp-file cleanup.
        with closing(sqlite3.connect(self.db)) as conn:
            conn.execute(
                "UPDATE key_filter SET target_selector='package:unexpected'"
            )
            conn.commit()
        with self.assertRaises(module.BackupError):
            module.verify_sqlite(self.db)


if __name__ == "__main__":
    unittest.main()
