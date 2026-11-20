#!/usr/bin/env python3
"""Offline, snapshot-driven Tizen cleanup planner for the Q80T.

No TV connection, runtime changes or privileged commands. Never use another
Samsung model's package IDs as a drop-in profile.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from contextlib import closing
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[2]
MODEL = "QA65Q80TAWXXY"
FIRMWARE = "T-NKMUABC-2743.0"
FIELDS = ("app_disable", "app_onboot", "app_autorestart")
DISABLED = ("true", "false", "false")
VALID_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\Z")
PROTECTED_IDS = frozenset({
    "com.samsung.tv.csfs", "org.tizen.tv-viewer", "org.tizen.menu",
    "com.samsung.tv.quicklaunch", "com.samsung.tv.coba.setting",
    "org.tizen.remote-management", "iN5p1j5y6b.DansTV",
})
# Prevent accidentally disabling the normal TV UI, critical connectivity
# or current access path even if an enthusiastic profile lists those IDs.
PROTECTED_TERMS = (
    "launcher", "smarthub", "homescreen", "home-app", "settings",
    "network", "bluetooth", "hdmi", "inputservice", "tv-viewer",
    "drm", "audio", "sound", "firmware", "upgrade", "update",
    "remotepc", "remote-management",
)


def validate_app_id(value: object) -> str:
    if not isinstance(value, str) or not VALID_ID.fullmatch(value):
        raise ValueError(f"Invalid application ID: {value!r}")
    lowered = value.lower()
    if value in PROTECTED_IDS or any(term in lowered for term in PROTECTED_TERMS):
        raise ValueError(f"Protected/critical application ID: {value}")
    return value


def sql_literal(value: str | None) -> str:
    if value is None:
        return "NULL"
    if value not in ("true", "false"):
        raise ValueError(f"Unknown registry flag representation: {value!r}")
    return "'" + value + "'"


def open_snapshot(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ValueError(f"Snapshot not found: {path}")
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise ValueError("Snapshot SQLite integrity check failed")
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info(package_app_info)")
        }
        if not {"app_id", *FIELDS}.issubset(columns):
            raise ValueError("Unknown package_app_info schema; inspect this Q80T first")
        return connection
    except Exception:
        connection.close()
        raise


def fetch_flags(db: sqlite3.Connection, app_id: str) -> tuple[str | None, ...]:
    records = db.execute(
        "SELECT app_disable, app_onboot, app_autorestart "
        "FROM package_app_info WHERE app_id=?", (app_id,)
    ).fetchall()
    if len(records) != 1:
        raise ValueError(f"{app_id}: expected one registry row, found {len(records)}")
    flags = tuple(records[0])
    for value in flags:
        sql_literal(value)
    return flags


def read_profile(path: Path, groups: list[str]) -> list[dict[str, str]]:
    profile = json.loads(path.read_text(encoding="utf-8"))
    if profile.get("model") != MODEL or profile.get("firmware") != FIRMWARE:
        raise ValueError("Profile has not been verified for this exact Q80T/firmware")
    if profile.get("registry") != "/opt/dbspace/.pkgmgr_parser.db":
        raise ValueError("Unexpected registry path in profile")
    group_definitions = profile.get("groups")
    if not isinstance(group_definitions, dict):
        raise ValueError("Profile groups must be an object")
    if not groups:
        raise ValueError("Select one or more reviewed groups")
    selected = []
    seen = set()
    for group in groups:
        entry = group_definitions.get(group)
        if not isinstance(entry, dict) or not isinstance(entry.get("apps"), list):
            raise ValueError(f"Unknown group or missing app list: {group}")
        for item in entry["apps"]:
            if not isinstance(item, dict):
                raise ValueError(f"{group}: each selected app needs a reason and evidence")
            app_id = validate_app_id(item.get("id"))
            reason, evidence = item.get("reason"), item.get("evidence")
            if not all(isinstance(x, str) and x.strip() for x in (reason, evidence)):
                raise ValueError(f"{app_id}: reason and Q80T-specific evidence required")
            if app_id in seen:
                raise ValueError(f"App appears in multiple selected groups: {app_id}")
            seen.add(app_id)
            selected.append({
                "app_id": app_id, "group": group,
                "reason": reason.strip(), "evidence": evidence.strip(),
            })
    if not selected:
        raise ValueError("No approved app IDs. Collect Q80T inventory before planning")
    return selected


def make_sql(records: list[dict], restore: bool = False) -> str:
    """Generate all-or-nothing, optimistic-concurrency-checked SQL."""
    lines = [
        "-- Review against a new, read-only snapshot before use.",
        "-- Run with sqlite3 -bail through a separately authorised procedure.",
        "BEGIN IMMEDIATE;",
        "CREATE TEMP TABLE danstv_guard (ok INTEGER CHECK(ok=1));",
    ]
    for record in records:
        app_id = record["app_id"]
        before = tuple(record["before"][field] for field in FIELDS)
        expected = DISABLED if restore else before
        conditions = " AND ".join(
            f"{field} IS {sql_literal(value)}"
            for field, value in zip(FIELDS, expected)
        )
        lines.append(
            "INSERT INTO danstv_guard SELECT COUNT(*)=1 "
            f"FROM package_app_info WHERE app_id='{app_id}' AND {conditions};"
        )
    for record in records:
        after = tuple(record["before"][field] for field in FIELDS) if restore else DISABLED
        assignments = ", ".join(
            f"{field}={sql_literal(value)}"
            for field, value in zip(FIELDS, after)
        )
        lines.append(
            f"UPDATE package_app_info SET {assignments} "
            f"WHERE app_id='{record['app_id']}';"
        )
    lines.extend(("DROP TABLE danstv_guard;", "COMMIT;", ""))
    return "\n".join(lines)


def private_output(path: Path) -> Path:
    resolved = path.resolve()
    private_root = (ROOT / ".local").resolve()
    if private_root not in resolved.parents:
        raise ValueError("Output must be inside .local/ (contains private TV inventory)")
    if resolved.exists():
        raise ValueError("Output already exists; do not overwrite rollback history")
    return resolved


def inspect(snapshot: Path, output: Path) -> None:
    with closing(open_snapshot(snapshot)) as db:
        # Only the columns needed for a future reviewed profile; no private
        # account fields or broad proprietary database export.
        rows = db.execute(
            "SELECT app_id,app_disable,app_onboot,app_autorestart "
            "FROM package_app_info ORDER BY app_id"
        ).fetchall()
        apps = []
        for app_id, *values in rows:
            if not isinstance(app_id, str) or not VALID_ID.fullmatch(app_id):
                continue
            apps.append({
                "app_id": app_id,
                "protected": app_id in PROTECTED_IDS or
                any(term in app_id.lower() for term in PROTECTED_TERMS),
                **dict(zip(FIELDS, values)),
            })
    output.mkdir(mode=0o700, parents=True)
    (output / "inventory.json").write_text(
        json.dumps({
            "target_model": MODEL, "expected_firmware": FIRMWARE,
            "snapshot_sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
            "apps": apps,
        }, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Read-only inventory written to {output / 'inventory.json'}")
    print("This inventory does not prove running services, dependencies or debloat safety.")


def plan(snapshot: Path, profile: Path, groups: list[str], output: Path) -> None:
    selected = read_profile(profile, groups)
    records = []
    with open_snapshot(snapshot) as db:
        for item in selected:
            flags = fetch_flags(db, item["app_id"])
            if flags == DISABLED:
                raise ValueError(
                    f"{item['app_id']}: already at requested state; "
                    "remove it from the plan instead of treating it as a new change"
                )
            records.append({
                **item, "before": dict(zip(FIELDS, flags)),
                "after": dict(zip(FIELDS, DISABLED)),
            })
    before = {
        "model": MODEL, "firmware": FIRMWARE,
        "snapshot_sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
        "groups": groups, "apps": records,
        "caveat": "Offline plan only: exact firmware and original state require "
                  "independent on-TV verification and backup before application.",
    }
    output.mkdir(mode=0o700, parents=True)
    for filename, body in (
        ("apply.sql", make_sql(records)),
        ("restore.sql", make_sql(records, restore=True)),
        ("before.json", json.dumps(before, indent=2) + "\n"),
    ):
        (output / filename).write_text(body, encoding="utf-8")
    print(f"Generated {len(records)} guarded changes and inverse SQL in {output}")
    print("NOT applied to TV. Verify actual registry state, backup and recovery first.")


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("inspect", "plan"):
        command = sub.add_parser(action)
        command.add_argument("--snapshot", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
        if action == "plan":
            command.add_argument("--profile", type=Path, required=True)
            command.add_argument("--groups", nargs="+", required=True)
    args = parser.parse_args()
    try:
        out = private_output(args.output)
        if args.action == "inspect":
            inspect(args.snapshot, out)
        else:
            plan(args.snapshot, args.profile, args.groups, out)
    except (ValueError, sqlite3.Error, OSError, json.JSONDecodeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
