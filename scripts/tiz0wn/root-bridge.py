"""One-shot, LAN-restricted read-only root inventory receiver for owned Q80T.

The Samsung Remote PC/CIFS route was independently proved UID 0 on this
device. This tool serves only a fixed, source-controlled read-only survey,
never arbitrary operator-supplied shell. No firmware, Home or service writes.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
from pathlib import Path
import re
import socket
import threading

ROOT = Path(__file__).resolve().parents[2]
LIMIT = 512 * 1024


def command_text(mode: str, host: str, token: str) -> bytes:
    if mode != "Snapshot":
        raise ValueError("Only read-only Snapshot is currently enabled")
    survey = (ROOT / "scripts/tiz0wn/snapshot.sh").read_text(encoding="utf-8")
    # This file runs in the existing, verified privileged shell through
    # Bash sourcing from /tmp, not as a signed executable. The downloaded
    # script's report uses an independently allowed outbound POST.
    script = f"""# DansTV Q80T one-shot read-only baseline
# No writes except a temporary /tmp report, removed after collection.
OUT=/tmp/.danstv-baseline-$$
(
  printf 'DANSTV-ROOT-CHANNEL mode=Snapshot\\n'
  /usr/bin/id
  printf '\\n=== Boot / firmware identifiers ===\\n'
  (cat /etc/tizen-release 2>/dev/null || :)
  (cat /etc/info.ini 2>/dev/null | grep -Ei 'model|build|release|version' | head -30 || :)
  printf '\\n=== Boot identity / mount and context ===\\n'
  (cat /proc/sys/kernel/random/boot_id 2>/dev/null || :)
  (mount 2>/dev/null | grep -E ' on / | on /opt | on /opt/dbspace ' || :)
  (ls -l /etc/profile.d/bash_prompt_custom.sh 2>/dev/null || :)
  (ls -l /opt/dbspace/.app-context.db 2>/dev/null || :)
  (ls -l /usr/bin/sqlite3 /usr/bin/curl /usr/bin/vconftool 2>/dev/null || :)
  printf '\\n=== Firmware partitions (no block reads) ===\\n'
  (cat /proc/partitions 2>/dev/null | head -30 || :)
  printf '\\n=== Launch target and services ===\\n'
  (vconftool get db/first_screen/type 2>/dev/null || :)
  (systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -Ei 'acr|advert|content|update|remotepc|hbbtv|airplay|tvctx|launcher' | head -70 || :)
  printf '\\n=== Existing DansTV survey ===\\n'
{survey}
  printf '\\nDANSTV-END-OF-REPORT\\n'
) > "$OUT" 2>&1
/usr/bin/curl -fsS --connect-timeout 5 --max-time 25 \\
  -X POST --data-binary @"$OUT" \\
  http://{host}:8181/r/{token} >/dev/null 2>&1
rm -f "$OUT"
"""
    return script.encode("utf-8")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--host", required=True)
    p.add_argument("--tv", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--mode", choices=["Snapshot"], default="Snapshot")
    args = p.parse_args()
    host = str(ipaddress.IPv4Address(args.host))
    tv = str(ipaddress.IPv4Address(args.tv))
    if not (ipaddress.IPv4Address(host).is_private and ipaddress.IPv4Address(tv).is_private):
        p.error("only private-LAN hosts allowed")
    if not re.fullmatch("[0-9a-f]{24,48}", args.token):
        p.error("expected a fresh hexadecimal per-session token")
    output = Path(args.output).resolve()
    expected = (ROOT / ".local/tiz0wn-lab").resolve()
    if expected not in output.parents:
        p.error("output must remain inside .local/tiz0wn-lab")
    if output.exists():
        p.error("output exists; refusing to overwrite the baseline")
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = command_text(args.mode, host, args.token)
    if len(payload) > LIMIT:
        p.error("survey too large")
    finished = threading.Event()
    state = {"served": 0, "received": 0}

    class Receiver(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args: object) -> None:
            pass

        def send_data(self, code: int, body: bytes = b"") -> None:
            self.send_response(code)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if body:
                self.wfile.write(body)

        def do_GET(self) -> None:
            if self.client_address[0] != tv or self.path != f"/d/{args.token}":
                self.send_data(404)
                return
            state["served"] += 1
            print("TV fetched bounded snapshot script", flush=True)
            self.send_data(200, payload)

        def do_POST(self) -> None:
            if self.client_address[0] != tv or self.path != f"/r/{args.token}":
                self.send_data(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "-1"))
            except ValueError:
                self.send_data(400)
                return
            if not 0 < length <= LIMIT or state["received"]:
                self.send_data(413)
                return
            body = self.rfile.read(length)
            if b"DANSTV-ROOT-CHANNEL mode=Snapshot" not in body or b"DANSTV-END-OF-REPORT" not in body:
                self.send_data(422)
                return
            output.write_bytes(body)
            state["received"] += 1
            self.send_data(204)
            print("SNAPSHOT-RECEIVED: " + str(output), flush=True)
            print(body.decode("utf-8", errors="replace")[:8500], flush=True)
            finished.set()

    server = ThreadingHTTPServer((host, 8181), Receiver)
    server.timeout = 1
    print(f"One-shot root snapshot listening on {host}:8181; TV {tv}.", flush=True)
    print("Reconnect the TV Remote PC, open Samsung Shared Folder once.", flush=True)
    try:
        deadline = datetime.now(timezone.utc).timestamp() + 300
        while not finished.is_set() and datetime.now(timezone.utc).timestamp() < deadline:
            server.handle_request()
        if not finished.is_set():
            print("NO-REPORT: Snapshot not received (not proof of root failure).", flush=True)
            if state["served"]:
                print("TV fetched script; return POST did not arrive.", flush=True)
    except KeyboardInterrupt:
        print("Interrupted; restore temporary credentials.", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
