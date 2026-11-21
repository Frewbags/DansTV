#!/usr/bin/env python3
"""Extract and verify the private Q80T Home DB copy from a staged snapshot.

Offline-only. Reads one locally stored snapshot and creates an exclusive
off-TV backup under ignored .local/tiz0wn-lab/. Never contacts the TV.
Do not upload or commit either the input report or the output database.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import os
from pathlib import Path
import re
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[2]
LAB = (ROOT / ".local" / "tiz0wn-lab").resolve()
MAX_REPORT = 512 * 1024
MAX_BACKUP = 256 * 1024
BEGIN = re.compile(r"^HOME-DB-BEGIN sha256=([0-9a-f]{64}) bytes=(\d+)$", re.M)
END = "HOME-DB-END"
STOCK_HOME = ("package:com.samsung.tv.csfs", "entry_point:smarthub_key")
APP_ID = "iN5p1j5y6b.DansTV"


class BackupError(ValueError):
    pass


def decode_backup(text: str) -> bytes:
    if ("DANSTV-EUID=0" not in text or
        "DANSTV-EXIT=0" not in text or
        "DANSTV-END-OF-REPORT" not in text or
        "Version=T-NKMUABC-2743.0;" not in text):
        raise BackupError("Incomplete report or unexpected Q80T firmware markers")
    matches = list(BEGIN.finditer(text))
    if len(matches) != 1 or text.count(END) != 1:
        raise BackupError("Expected exactly one complete Home DB backup block")
    begin = matches[0]
    marker = text.find(END, begin.end())
    if marker < 0 or (marker > 0 and text[marker - 1] != "\n"):
        raise BackupError("No complete Home backup END marker")
    encoded = text[begin.end():marker].strip()
    if not encoded or len(encoded) > (MAX_BACKUP * 4 // 3 + 2048):
        raise BackupError("Empty or oversized encoded backup")
    try:
        size = int(begin.group(2))
        if not 1024 <= size <= MAX_BACKUP:
            raise BackupError("Unexpected Home DB byte count")
        data = base64.b64decode("".join(encoded.splitlines()), validate=True)
    except (binascii.Error, ValueError) as exc:
        raise BackupError("Invalid Home DB backup encoding or size") from exc
    if len(data) != size or hashlib.sha256(data).hexdigest() != begin.group(1):
        raise BackupError("Home DB SHA-256 / byte count mismatch")
    if not data.startswith(b"SQLite format 3\x00"):
        raise BackupError("Backup is not a SQLite database")
    return data


def verify_sqlite(path: Path) -> tuple[bool, bool]:
    # Read-only URI; never modify the off-TV backup, even during verification.
    with sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True) as conn:
        result = conn.execute("PRAGMA quick_check;").fetchall()
        if result != [("ok",)]:
            raise BackupError("SQLite quick_check did not report ok")
        rows = conn.execute(
            "SELECT target_selector,args FROM key_filter "
            "WHERE appid='com.samsung.tv.csfs' AND key='XF86Home' "
            "AND request='launch'"
        ).fetchall()
        if rows != [STOCK_HOME]:
            raise BackupError("Original Samsung XF86Home row not present exactly once")
        # Inspect but do not assume the managed-app reference row exists.
        managed = conn.execute(
            "SELECT COUNT(*) FROM managed_app WHERE appid=?", (APP_ID,)
        ).fetchone()[0]
        reference = conn.execute(
            "SELECT COUNT(*) FROM managed_app WHERE appid='com.samsung.tv.searchall'"
        ).fetchone()[0]
        return bool(managed), bool(reference)


def extract(path: Path) -> tuple[Path, bool, bool]:
    report = path.resolve()
    if LAB not in report.parents or not report.is_file():
        raise BackupError("Report must be a private .local/tiz0wn-lab/snapshot-*.txt")
    if not re.fullmatch(r"snapshot-[0-9a-f]{24,48}\.txt", report.name):
        raise BackupError("Unexpected snapshot filename; refusing unsafe destination")
    if report.stat().st_size > MAX_REPORT:
        raise BackupError("Report exceeds receiver's size limit")
    data = decode_backup(report.read_text(encoding="utf-8", errors="strict"))
    destination = report.with_suffix(".home.db")
    try:
        fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise BackupError("Backup already exists. Never overwrite it.") from exc
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        managed, reference = verify_sqlite(destination)
        return destination, managed, reference
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="Private snapshot report under .local/tiz0wn-lab")
    args = parser.parse_args()
    try:
        backup, managed, reference = extract(args.report)
    except (BackupError, OSError, sqlite3.Error, UnicodeError) as exc:
        print(f"HOME-BACKUP-FAILED: {exc}", file=sys.stderr)
        return 1
    digest = hashlib.sha256(backup.read_bytes()).hexdigest()
    print(f"HOME-BACKUP-VERIFIED: {backup}")
    print(f"Bytes: {backup.stat().st_size}, SHA-256: {digest}")
    print("Samsung stock XF86Home row: verified")
    print(f"DansTV managed_app row present: {managed}")
    print(f"Reference searchall managed_app row present: {reference}")
    print("Independent recovery method: NOT YET VERIFIED. No Home writes authorised.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
