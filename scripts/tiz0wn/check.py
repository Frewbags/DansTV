"""Offline tests for the SQL in the optional Tizen 5.5 Home-key trial.

Run with: python scripts/tiz0wn/check.py
No device connection, shell, or privileged operation is performed.
"""
from pathlib import Path
import re
import sqlite3

ROOT = Path(__file__).resolve().parent
HOME = (ROOT / "home-ctx.sh").read_text(encoding="utf-8")
PREFLIGHT = (ROOT / "preflight.ps1").read_text(encoding="utf-8")
SNAPSHOT = (ROOT / "snapshot.sh").read_text(encoding="utf-8")
APP = "AbCdEf1234.DansTV"
ORIGINAL = "package:com.samsung.tv.csfs"
TARGET = "package:" + APP
WHERE = "appid='com.samsung.tv.csfs' AND key='XF86Home' AND request='launch'"

assert "DANSTV_HOME_WRITE_CONFIRM" in HOME, "Apply must require explicit opt-in"
assert "need_root" in HOME and "need_record" in HOME
assert ".backup" in HOME and "sha256sum" in HOME
assert "scripts/tiz0wn" not in SNAPSHOT, "Snapshot must be a read-only standalone TV script"
# The Q80T inventory must capture the alternative native Home/startup
# preference selectors before anyone infers compatibility from another model.
for key in (
    "db/appfw/home_appid",
    "db/appfw/startup_appid",
    "db/appfw/booting_appid_backup",
    "db/first_screen/type",
    "db/menu/smart_hub/ontvsetting/auto_start",
):
    assert key in SNAPSHOT, "Missing read-only Home preference inventory: " + key
assert "Native main-operation handler: not measured" in SNAPSHOT
assert "Tizen 5.5 service prerequisites (read-only)" in SNAPSHOT
for signal in (
    "Node executable in PATH:",
    "dotnet launcher executable:",
    "apps_rw data directory:",
    "Survey shell SMACK label:",
    "Web-service Node version: not measured",
    "Broker ownership and authentication: not measured",
):
    assert signal in SNAPSHOT, "Missing conservative Tizen 5.5 runtime signal: " + signal

assert not re.search(r"\bvconftool\s+set\b|\bapp_operation_set_current_app\b|\bsqlite3\s+\$DB\s+UPDATE\b", SNAPSHOT), "Snapshot must not modify Home or startup"
assert "install" not in PREFLIGHT.lower() or "does not" in PREFLIGHT.lower()
assert "com.samsung.tv.csfs" in HOME and "com.samsung.tv.searchall" in HOME
assert not re.search(r"\b(pkgcmd\s+-[uD]|rm\s+-rf|mkfs|dd\s+if=)", HOME), "Home script must not bulk-delete or overwrite partitions"

# Cross-platform source guards for Windows snapshot credential recovery.
# This does not execute Administrator commands or open real credentials.
BRIDGE = (ROOT / "root-bridge.ps1").read_text(encoding="utf-8")
COMPOSE = (ROOT / "lab" / "compose.yml").read_text(encoding="utf-8")
assert "--env-file" not in BRIDGE, "Never feed a password-bearing lab.env to Compose interpolation"
assert "env_file:" in COMPOSE and "format: raw" in COMPOSE
assert "${LAB_HOST_IP:" in COMPOSE, "Host port must come from scoped LAB_HOST_IP"
assert "[Environment]::GetEnvironmentVariable('LAB_HOST_IP', 'Process')" in BRIDGE
assert "Remove-Item Env:LAB_HOST_IP" in BRIDGE
assert "if ($Action -ne 'Restore')" in BRIDGE, "Restore must bypass the current TV firmware gate"
assert "if ($hadSession -and -not $hadBackup)" in BRIDGE, "Preserve unknown credential state"
rotate = BRIDGE.split("function Rotate(", 1)[1].split("if ($Action -eq 'Restore')", 1)[0]
assert rotate.index("Assert-DockerReady") < rotate.index("Set-LocalUser")
assert "Invoke-LabCompose -composeArgs @('config', '--quiet')" in rotate

# Extract actual SQL strings from the checked-in shell script, then execute them
# in an isolated SQLite fixture. This catches misspelled columns/conditions and
# verifies that unrelated key rules and managed apps are not changed.
commands = re.findall(r'sqlite3 "\$DB" "(BEGIN IMMEDIATE;.*?COMMIT;)"', HOME, re.S)
assert len(commands) == 2, "Expected exactly one apply and one restore transaction"
def render_sql(template):
    return (template.replace("$WHERE", WHERE)
            .replace("$TARGET", TARGET)
            .replace("$ORIGINAL", ORIGINAL)
            .replace("$app", APP))

connection = sqlite3.connect(":memory:", isolation_level=None)
connection.executescript("""
CREATE TABLE key_filter (appid TEXT, key TEXT, request TEXT, target_selector TEXT, args TEXT);
CREATE TABLE managed_app (appid TEXT, ui_type TEXT, source TEXT);
INSERT INTO key_filter VALUES
  ('com.samsung.tv.csfs','XF86Home','launch','package:com.samsung.tv.csfs','entry_point:smarthub_key'),
  ('org.tizen.remote-management','XF86Home','longpress','package:keep','5300'),
  ('com.samsung.tv.csfs','XF86Display','launch','package:com.samsung.tv.csfs','source_key');
INSERT INTO managed_app VALUES
  ('com.samsung.tv.searchall','full','existing-source'),
  ('com.samsung.tv.csfs','partial','system-source');
""")
original_keys = connection.execute("SELECT * FROM key_filter ORDER BY appid,key").fetchall()
original_apps = connection.execute("SELECT * FROM managed_app ORDER BY appid").fetchall()
connection.executescript(render_sql(commands[0]))
assert connection.execute("SELECT target_selector FROM key_filter WHERE " + WHERE).fetchone()[0] == TARGET
assert connection.execute("SELECT appid,ui_type,source FROM managed_app WHERE appid=?", (APP,)).fetchone() == (APP, "full", "existing-source")
assert connection.execute("SELECT COUNT(*) FROM key_filter").fetchone()[0] == len(original_keys)
connection.executescript(render_sql(commands[1]))
assert connection.execute("SELECT * FROM key_filter ORDER BY appid,key").fetchall() == original_keys
assert connection.execute("SELECT * FROM managed_app ORDER BY appid").fetchall() == original_apps
connection.close()
print("tiz0wn Q80T integration: Home apply/restore SQL round trip and static safeguards passed.")
