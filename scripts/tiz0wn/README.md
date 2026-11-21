# DansTV + tiz0wn: Tizen 5.5 takeover workstream

This integration applies the experimentally validated *architecture* from
[sebastianspicker/tiz0wn](https://github.com/sebastianspicker/tiz0wn) to the
Samsung QA65Q80TAWXXY (Q80T, Tizen 5.5/ARMv7).
The owner supplied an About This TV photo showing **T-NKMUABC-2743.0**
(build field **B2052220/A70B05**). Do not commit the serial number, TVkey,
MAC addresses or other device-unique fields visible on that screen.

Samsung documents T-NKMUABC as one of its 2020 NKM firmware variants;
the T-NKMDEUC-2743.0 Q90T in tiz0wn's published case is related, not
binary-identical. Both are useful for *method* comparison, but the correct
firmware is **T-NKMUABC**, not **T-NKMDEUC**. The owner preflight requires
the former exact string when `-Firmware` is provided, and does not claim
the SDB capability call can verify a full firmware build.
Source: https://security.samsungtv.com/securityUpdates
Samsung model page: https://www.samsung.com/au/support/model/QA65Q80TAWXXY/

Tiz0wn is MIT-licensed (Copyright © 2026 Sebastian J. Spicker); see upstream
`LICENSE` and `NOTICE.md`. This code is adapted, not an assertion that its
Q60T firmware offsets apply to a Q80T.

## Hardware milestone — 16 November 2026

The owner tested the Australian QA65Q80TAWXXY with
**T-NKMUABC-2743.0** and reported the following from the bounded
Remote PC → Shared Folder callback:

```text
Listening on 192.168.50.215:8181 for one TV callback.
UID0-PROOF: Q80T command substitution executed with effective UID 0.
```

The host also observed an authenticated SMB session from the TV and the
TV displayed a JPG from its temporary Windows SMB share. This establishes
**one tested instance of effective-UID-0 command execution**, but not a
general-purpose root shell, privilege persistence, Home redirection, or
any firmware modification. No raw partition write has been performed on
this Q80T.

The owner should run `uid-probe.ps1 -Action Restore` if its
`Prepare` state is still active. That restores the dedicated temporary
lab account passwords; it does not delete the lab, which remains
available for controlled testing. Do not commit any credential files.

A bounded **read-only snapshot transport** is implemented in
`root-bridge.py` with `root-bridge.ps1` for Windows orchestration. Local
HTTP and Linux Bash/curl round trips pass. The longer diagnostic
was attempted on the TV in November 2026, but **no validated full snapshot
was received**. The checked-in trigger remains unchanged, and long
mixed-character credential handling is unresolved; do not blindly repeat
the previous trial. It is not a general root shell. See the
[21 November offline status](../../docs/q80t-nov21-offline-status.md)
and current [handover](../../docs/q80t-root-handover.md).

### Experimental staged transport — not ready for use

**Do not run `staged-snapshot.ps1 -Action Prepare` yet.** The new
`staged-snapshot.py` and `staged-snapshot.ps1` helpers are an untested
prototype; their current short-credential construction is inconsistent,
and no Windows or Samsung hardware tests have been completed.
Neither helper was run against the owner's TV. No claim of successful SDB
staging, collection or XRDP restoration is made.

The concept is to stage a fixed, read-only survey via SDB, verify its
bytes with a read-back, perform one owner-operated Remote PC/Shared
Folder action, retrieve a private report, and restore dedicated lab
credentials. This design may still be blocked by firmware-specific SDB
upload permissions or security labels. Correct and test the
implementation in an authorised development environment before enabling
any privileged trial. `root-bridge.ps1 -Action Doctor` remains the
existing safe host-only preflight.

### Preferred next Q80T trial — short staged snapshot (experimental)

**This is a new, separately gated procedure.** It is not yet hardware-verified on the
Q80T; it stops before credential rotation if SDB upload/readback or its SHA-256
verification fails. A successful SDB transfer proves only that the SDK can
read back the staged bytes, not that the privileged SMB shell can read or
run them. No Home, firmware, service or startup state is changed.

The new staged mode avoids a long mixed-character TV password. The short
password consists of a built-in shell `eval` and `cat` of an SDB-staged,
hash-verified one-line text-form survey. It uses only the measured
`$()` and `${IFS}` grammar rather than the TV-rejected `<`, literal
spaces or IME-dropped pipe character. The full survey is decoded and executed
by the signed shell **from command content**, not through an executable
script path (Tizen UEP can reject execution of uploaded files). The existing
single-use LAN HTTP receiver is kept **only for report collection** because
some retail Tizen firmware prohibits SDB file pulls. In staged mode, the
receiver never supplies a downloadable root script.

From **Administrator PowerShell** on the existing Windows host, with
Docker Desktop running, run from the repository root:

```powershell
git pull --ff-only origin feature/q80t-windows-setup
npm run check:home
.\scripts\tiz0wn\root-bridge.ps1 -Action PrepareStaged
```

The script checks the exact Q80T model/firmware and existing disposable
account/share, connects with SDB, uploads only the bounded survey to the
owner SDK staging folder, **pulls that file back and compares its SHA-256**.
Only after those gates pass does it back up and rotate the dedicated lab
credentials, recreate the Docker XRDP service, check TCP/3389, and enable a
TV-IP-only temporary listener rule. The short, temporary Remote PC password
is printed locally. Do **not** paste passwords, tokens or private files into
issues, logs or chat.

In the same elevated PowerShell window, start the bounded report receiver:

```powershell
.\scripts\tiz0wn\root-bridge.ps1 -Action ListenStaged
```

Only then, on the TV, enter the displayed short password in Remote PC,
connect and open **Shared Folder** once. The password may also be sent by
`py scripts/tiz0wn/paste-password.py send` while that field is focused,
although Samsung may not commit remote text entry; SmartThings input or
manual entry can still be required. The receiver accepts one successful
report from the configured TV IP and exact one-use token, prints a
privacy-preserving assessment and **automatically runs Restore** when it
ends. It times out after five minutes, then restores; it does not retry
the TV trigger.

If you have to interrupt or Prepare succeeds but Listen cannot be run,
restore from Administrator PowerShell:

```powershell
.\scripts\tiz0wn\root-bridge.ps1 -Action Restore
.\scripts\tiz0wn\root-bridge.ps1 -Action Doctor
```

Restore revokes the firewall rule and returns the ordinary dedicated lab
credentials; normal TV Remote PC saved credentials may need updating. A
staging file may remain if the TV never executed it or could not remove
it; it is not a boot hook, but should be deleted through an independently
verified owner-safe path later. Never run a stale staged trigger. If SDB
`pull` is blocked, stop: **no password rotation or TV root attempt is
performed** and the failed stage should be treated as untrusted. Report
only the error message, not credentials.

**Trust boundary:** The SDB-stage hash check closes *transfer* ambiguity but
does not prove the file cannot be replaced on the TV before execution. The
callback is restricted by TV IP, session token, a bounded body and report
markers; these are **not cryptographic attestation** of the TV. Only use on
the owner's isolated private network, and do not generalise this experimental
read-only workflow into arbitrary commands or firmware writes.

### Reference procedure: bounded snapshot trial (currently blocked)

**Do not repeat the former long mixed-character password attempt as written.**
It failed to deliver a validated Q80T snapshot in November 2026. The
shorter hardware proof, normal RDP login, and Linux password-hash checks
do not establish that this longer credential is entered without alteration
by SmartThings/the TV. Before another trial, independently validate the
exact credential transport with a harmless test account, then re-review
the privilege-boundary and report-integrity safeguards. The commands below
remain as historical/recovery documentation, **not an instruction to run
Prepare without that review**. See the
[architecture assessment](../../docs/q80t-vetro-tizen55-architecture.md)
and the [offline findings](../../docs/q80t-nov21-offline-status.md).

First run the **read-only host doctor** from Administrator PowerShell
in the repository root, after updating your branch and running `npm run check`:

```powershell
.\scripts\tiz0wn\root-bridge.ps1 -Action Doctor
```

Doctor verifies the private model/firmware preflight, dedicated account and
SMB share, Docker, Python launcher, callback port, reviewed helper files
and that no previous trial is active. It does **not** connect to the TV
or change a credential or firewall rule.

**Docker Desktop must be running**, not merely installed. Doctor checks the
Docker engine and performs a quiet Compose configuration validation. The
snapshot wrapper supplies `LAB_HOST_IP` from the private ownership marker
only for the duration of each Compose invocation; the Compose service's
`env_file: format: raw` still reads the original ignored `lab.env`. The
password-bearing file is **not** passed through Compose's CLI `--env-file`,
which would interpolate the intentional literal `${IFS}` token. The process
environment is restored after the command, including on failure.

For an additional no-TV test, run
`./scripts/tiz0wn/test-compose-interpolation.ps1` in PowerShell with the
Docker Compose CLI available. It uses a disposable **synthetic** password
and copy of the YAML under the OS temporary directory; it never reads or
prints the real lab password. This is also checked by Windows CI. A
successful Doctor or synthetic test does **not** verify the TV trigger,
credential Restore or physical Home-button compatibility. If it fails, resolve that exact
prerequisite before attempting Prepare; never bypass model or firmware guards.

Use an Administrator PowerShell window from the repository root. Prepare
restarts only the disposable XRDP container and rotates only its dedicated
lab account credentials. The recorded exact model/firmware preflight and
lab ownership must match; addresses are read from private configuration.

```powershell
.\scripts\tiz0wn\root-bridge.ps1 -Action Prepare
```

Then run `-Action Listen` in that window. While it listens, focus the TV's
Remote PC password field. From a second window, use the already paired
`py scripts/tiz0wn/paste-password.py send`. This sends only the prepared
password, without Enter. Confirm acceptance on the TV, reconnect to the
disposable desktop and open Samsung Shared Folder once. If that password
field rejects remote text entry, enter the password from the private
`lab.env` locally; do not paste it into chat.

The trigger fetches a fixed survey, sources it in the proven shell context,
captures stdout and stderr together and POSTs the report with an explicit
EUID and survey exit status. The downloaded script and temporary report
are removed on the normal completion path. An interrupted execution may
leave these files in `/tmp`; no permanent TV settings are changed. Optional
inventory queries can fail without failing the whole survey: inspect the
report before asserting any individual capability.

The receiver allows only the configured TV IP and fresh 96-bit session
token, one download and one validated result, with a five-minute deadline,
three-second socket timeout and 512 KiB report limit. A non-root, incomplete
or failed report is rejected. Existing reports cannot be overwritten.
Reports and receipt metadata remain in ignored `.local/tiz0wn-lab/` and
their contents are not printed. This is trusted-LAN HTTP with a bearer
token, without encryption or server identity protection; never expose it
outside the trusted lab network.

After the report is saved, **do not paste the raw snapshot into chat**:
it may include unique network and device identifiers. Obtain a safe status
summary using the local assessor (which never prints raw values or app IDs):

```powershell
$report = Get-ChildItem .local\tiz0wn-lab\snapshot-*.txt |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($report) {
    py scripts\tiz0wn\assess-snapshot.py --report $report.FullName
}
```

It reports the exact-firmware marker, whether each Home preference was
readable, whether an XF86Home row was observed and the native-operation
query that **remains unmeasured**. This summary cannot approve Home writes;
an off-TV database backup and verified restoration access are still required.
Validate it offline through `npm run check` or
`py scripts/tiz0wn/test_assess_snapshot.py`.

Listen exits nonzero without a validated report and always invokes Restore
after the receiver exits. Restore removes the callback firewall rule,
restores the previous dedicated account/XRDP credentials, and removes the
session token file. It retains the backup until both credential restores
succeed. After Prepare without Listen, interruption or failure, run:

```powershell
.\scripts\tiz0wn\root-bridge.ps1 -Action Restore
```

Restore the TV's saved Remote PC password to the ordinary lab password as
well. To enter the *original* lab password without displaying it, after
`Restore` and a passing `Doctor`, focus the TV Remote PC password box and
run `py scripts/tiz0wn/paste-password.py send-normal` from the PC. This
new action reads only the ignored local `.local/tiz0wn-lab/lab.env`, accepts
the original `rdp-lab.ps1`-generated credential format, and refuses to send
if any UID/snapshot backup or session marker still exists. It sends only
text, with no Enter key or navigation, and does **not** run a snapshot.
It cannot prove that Samsung's password input accepted external text; inspect
the masked field on the TV before connecting. Never paste credentials into
chat. The host receiver exits on result/timeout; Ctrl+C stops it early.
Repeatability, the TV credential restoration and physical Shared Folder
flow still require owner observation. Do not proceed to Home writes until
the actual Q80T report and independent recovery path are verified.

### Remaining acceptance gates

1. A repeatable, authenticated root command channel must return
   reproducible output from the actual Q80T without requiring firmware
   modification, and have a verified stop/revoke path.
2. Capture the Home-key table, `db/first_screen/type`, current package
   state, startup services, and read-only platform/partition metadata.
3. Export and verify an **off-TV** copy of the original Home database
   before a reversible Home-button trial. Test Home, Back, Live TV,
   HDMI, standby and reopening apps, with a tested restore procedure.
4. Debloat only measured and identified services using reversible,
   model-verified disablement, preserving tuner, DRM, connectivity,
   upgrades and app lifecycle until checked.
5. Before a persistent boot hook: obtain the **exact** official
   T-NKMUABC-2743.0 image and matching live-build stamp; compute
   per-image offsets and pre/post hashes, retain the original bytes
   off-TV, and establish a credible hardware recovery path.
   **Never apply Q60T/Q70T/Q74T/Q90T offsets to this set.**

Outcome target: DansTV opens with Home, reliably survives a full
cold boot, Samsung essentials remain operational, debloating is
reversible and ordinary operation needs neither a PC nor a USB drive.
None of these target outcomes is asserted as installed today.

### Offline privacy and cleanup planning (not deployed)

Current tooling adds an **offline-only**, model-guarded Tizen registry
cleanup planner and synthetic regression tests:

- `scripts/tiz0wn/cleanup-plan.py` inspects a private Q80T SQLite snapshot,
  then generates guarded `apply.sql`, `restore.sql` and a precise before-state.
- `scripts/tiz0wn/q80t-cleanup-profile.example.json` contains deliberately
  **no candidates** until exact app IDs and dependencies are established on
  this television. It does not copy a Tizen 9 or Android list.
- `scripts/tiz0wn/test_cleanup_plan.py` tests backup state, expected-value
  guards, drift refusal, protected core IDs, wrong model and schema handling.
- `docs/q80t-privacy-and-cleanup.md` covers non-privileged privacy switches
  and source comparisons for CleanYourTV, Quiet Tizen and Arn0 Launcher.

Arn0's 2022 Tizen 6.5 Q70B reportedly changed the main Home app-control
operation and `db/appfw/home_appid` without root. This is an **alternative
research approach**, not a verified Q80T path. Do not apply it alongside
`home-ctx.sh` without exact live queries and independent rollback.

All generated plans remain private under `.local/`. Nothing is run on the
television automatically. See `docs/q80t-privacy-and-cleanup.md`.
## Current implementation

| Component | Status | Source |
| --- | --- | --- |
| Standalone DansTV widget | Installed/tested by owner independently of this integration | `scripts/q80t-windows.ps1` |
| Windows device/version/identity preflight | **Implemented, read-only** | `preflight.ps1` |
| CPU load, RAM, process and app inventory | **Implemented as a root-side read-only script** | `snapshot.sh` |
| Tizen 5.5 Home-key database routing | **Implemented as an unexecuted root-side trial** | `home-ctx.sh` |
| Exact-value Home restoration | **Implemented with a saved baseline; untested on Q80T** | `home-ctx.sh restore` |
| Debloat package lifecycle | **Use upstream's audited `pkgstate`, not an ad-hoc package remover** | tiz0wn `exploits/tiz0wn-root/payload/pkgstate` |
| Bounded TV-side launcher command for a future boot hook | **Implemented, not installed or hardware-tested** | `boot-launch.sh` |
| Root acquisition / boot persistence | **Not ported or executed** | tiz0wn's firmware-specific build-run and agent |
| Home double-press/Back, TV power-on | **Not solved by upstream Tizen 5.5 trial** | tiz0wn `docs/home-key-menu-plan.md` |

No service, root kit, Home hook, boot hook or package change is installed by these
source files. The existing user-signed WGT is unaffected.

## Step 1: Windows read-only preflight — can run now

From `C:\Users\Daniel\DansTV`:

```powershell
git pull origin feature/q80t-windows-setup
.\scripts\tiz0wn\preflight.ps1
```

For a full firmware fingerprint, first read **TV Settings → Support → About
This TV**, including the full software/build identifier, not just "Tizen 5.5".
Then:

```powershell
.\scripts\tiz0wn\preflight.ps1 -Firmware "T-NKMUABC-2743.0"
```

These commands only request SDB capabilities and write a private
`.local/tiz0wn-preflight.json` on the PC. The confirmed Q80T details
are model `QA65Q80TAWXXY`, firmware `T-NKMUABC-2743.0`,
Tizen 5.5, ARMv7 and `intershell_support=disabled`. They do **not** prove
root access or tell us which rootfs partition, vulnerability path or block
offset the Q80T uses.

### Offline firmware file inspection (optional)

Samsung's **Australian** Q80T support page currently lists a
`T-NKMUABC.zip` package at 2730.6; the owner-confirmed TV runs 2743.0.
Other official Samsung regional support pages list the NKMUABC 2743.0
archive. For source analysis, obtain a **matching 2743.0** firmware archive
through an official Samsung support page, retaining the download provenance.
**Do not install an older release or flash a foreign-region ZIP** as part of
this work. The ZIP is approximately 1.7 GB.

Once the *official* `T-NKMUABC.zip` archive is already saved locally:

```powershell
python scripts/tiz0wn/firmware-inventory.py "C:\\path\\to\\T-NKMUABC.zip" --sha256
```

This inspects the ZIP directory and optionally computes its SHA-256.
`--check-contents` does a full (slower) CRC verification. No network access,
decryption, extraction, exploit or TV-side operation is performed. Archive
filenames alone do **not** establish the embedded release version or root
patch compatibility; any later firmware parser must verify that separately.

### First root attempt: generic archive route (Windows)

The [upstream samsung-tv-root](https://github.com/chris-ritsen/samsung-tv-root)
v0.0.13 release (14 November 2026) includes an alternative **archive-root**
path, without a model whitelist. The tool attempts root and checks the target
for a capability-bearing Samsung .NET host, tar and the SDB foothold. It has
not been verified on this Q80T. The related NKMDEUC Q90T report lacked
`/usr/bin/dotnet`, so this Q80T may also be incompatible.

Use `probe-root.ps1`, which downloads the official Windows x86-64 release
into ignored `.local/`, verifies its published SHA-256 and passes the
configured Samsung SDB path. The tool never signs or replaces the DansTV WGT.

```powershell
.\scripts\tiz0wn\preflight.ps1 -Firmware T-NKMUABC-2743.0
.\scripts\tiz0wn\probe-root.ps1 -Action Prepare
.\scripts\tiz0wn\probe-root.ps1 -Action Doctor
# This next command executes an actual SDB exploitation/root attempt:
.\scripts\tiz0wn\probe-root.ps1 -Action Probe
```

`Prepare` is download-only. `Doctor` checks the host. `Probe` exercises
the SDB package-name vulnerability and **attempts temporary root access**,
then performs the upstream cleanup. It does not modify Home, disable packages
or install a persistent boot hook, though a failed attempt might leave
temporary staging files. Do not confuse `doctor` with an on-TV compatibility
check, or `Probe` with a safe read-only query. If the probe reports missing
.NET or capabilities, record that result and move to firmware-specific
Remote PC/CIFS or USB exploitation instead of forcing a different
platform profile.

Upstream: [v0.0.13 releases](https://github.com/chris-ritsen/samsung-tv-root/releases/tag/v0.0.13)
and [generic archive route](https://github.com/chris-ritsen/samsung-tv-root/blob/master/QUICKSTART.md).

### Verified Q80T test: generic archive route is unavailable

**16 November 2026:** on QA65Q80TAWXXY / T-NKMUABC-2743.0,
`probe-root.ps1 -Action Doctor` passed all **host** prerequisites,
but `-Action Probe` returned:
`TV is missing /usr/bin/dotnet; archive-root requires Samsung's capability-bearing dotnet host`.
Therefore **the archive route cannot run on this firmware**. Do not
retry using `--runtime`, swap in `dotnet-launcher`, or select a
different model's `qn90b`/`qn90f` profile. The upstream tool exited
before proving root; no persistent Home/debloat write was requested.

**Next route: Remote PC / CIFS.** Tiz0wn reports UID-0 proofs on the
related `T-NKMDEUC-2743.0` Q90T and persistent root on a Q74T.
Check the physical **Home → Source → Remote Access → Remote PC** UI
on the Q80T before constructing a disposable RDP+SMB lab host; its
actual presence and credential/Shared Folder flow on the *Australian*
firmware must be observed. Samsung's 2020 Q80T manual lists the feature.
A bounded, volatile UID probe is the first target; do not stage the
rootfs patch, SDK-account edits, or startup hook as part of that test.
If the route works, analyse an **exact T-NKMUABC** firmware image
before building any persistent payload. Never reuse offsets from NKMDEUC.

**Windows host prerequisites for the disposable upstream lab** (not
verified on this PC): `docker --version`, `docker compose version`,
and `wsl --status`. Do not enable Remote Desktop or SMB sharing
on the user's primary Windows installation: use an isolated lab
container/VM and dedicated credentials. The Q80T acts as an RDP
client, so the PC/VM hosts the endpoint; checking port 3389 on the TV
will not establish support.

### Disposable Windows Remote PC / Shared Folder lab

**Current owner measurements:** Docker Desktop + WSL 2 work; Windows' own
SMB service already owns TCP/445 as PID 4; TCP/3389 is free; the TV has
Remote Access → Remote PC and Shared Folder. Docker Desktop cannot
publish a second SMB server to the **same** host port 445, so use Windows'
existing SMB service with a new, restricted temporary share, and Docker
only for a disposable XRDP desktop on 3389. The Docker and Windows service
components share one LAN IP and a randomly generated temporary username/password.
No permanent TV or firmware modification is performed.

The source lives in `scripts/tiz0wn/lab/` and the Windows
`rdp-lab.ps1` wrapper. The setup script has three explicit operations:

```powershell
# In Windows PowerShell **Run as Administrator**, from the repository root:
.\scripts\tiz0wn\rdp-lab.ps1 -Action Setup
.\scripts\tiz0wn\rdp-lab.ps1 -Action Status
# Once finished, or after a partially failed Setup:
.\scripts\tiz0wn\rdp-lab.ps1 -Action Cleanup
```

`Setup` automatically selects the PC's outgoing LAN address toward the
configured Q80T, generates a 16-character password, saves credentials in
ignored `.local/tiz0wn-lab/lab.env`, creates local Windows user
`danstvprobe`, a restricted `DansTVProbe` SMB share, firewall
allow rules restricted to the TV IP, then builds/starts an XFCE/XRDP
container on `<PC-IP>:3389`. It **does not disable Windows SMB**,
alter any existing Windows share, or enable Windows RDP. The rule
allowlisting the TV does not remove other existing firewall allow rules:
ensure this is a trusted LAN, not an exposed/public network. There is a
normal `readme.txt` inside the share for connectivity confirmation.

`Status` checks the disposable user/share, container, and PC-facing
ports. `Cleanup` requires a matching local ownership marker before
removing the service, temporary Windows account/share, the two named
firewall rules and generated credential file. It deliberately retains
the local test folder for inspection. If Setup fails, run Cleanup;
do not repeatedly overwrite or disable system services.

On TV, enter the PC LAN IP printed by Setup in **Remote PC**.
Use the same `danstvprobe` username and password stored locally
(the script explains how to display it); enable **Remember credentials /
Shared Folder** when available. Connect to the disposable desktop,
accept its local self-signed certificate only for the test, and
open **Shared Folder** from the in-session toolbar. The temporary share
should be `\\<PC-IP>\DansTVProbe`. Do **not** enter an exploit string
during this first connectivity check. Check the resulting on-TV UI
rather than assuming a successful Docker health check proves the TV path.

The next (separate) stage is one bounded volatile UID-0 test following
tiz0wn's `docs/DISCLOSURE.md` and `docs/trigger-grammar.md` research,
*not* the permanent firmware patch. An exact local Windows/Docker
environment can be tested on its own before changing the TV-side
credential field. Share credentials privately; do not commit them or paste
them into a public chat.

### One-shot UID callback proof (Q80T; no firmware patch)

When both PC-side ports are live and the TV has **actually displayed a JPG**
via Samsung Shared Folder, use the reversible `uid-probe.ps1` helper
to test whether the Q80T shares the Q60T Remote PC credential injection.
This is a live local-owner security test, not a read-only operation.

Open an **elevated** PowerShell window:

```powershell
cd C:\Users\Daniel\DansTV
.\scripts\tiz0wn\uid-probe.ps1 -Action Prepare
```

It copies the original `lab.env` to ignored
`.local/tiz0wn-lab/lab.env.before-uid`, rotates the **temporary**
Windows `danstvprobe` password and Docker XRDP login to the
identical, ~60-character string printed by the helper, and opens a
TV-IP-restricted Windows firewall rule for PC TCP/8181. It does not
modify the primary Windows account or any existing shares.
The Docker `env_file` uses Compose `format: raw` to avoid accidental
interpolation of the literal Bash expressions in the password.

Open a **second elevated** PowerShell window and run:

```powershell
cd C:\Users\Daniel\DansTV
.\scripts\tiz0wn\uid-probe.ps1 -Action Listen
```

The callback listens on the recorded host IP TCP/8181, accepts one
request from the Q80T address, and replies HTTP 204. It stops after
one TV request or a timeout. A request to `/0` yields
`UID0-PROOF`; another numeric path reports a nonzero EUID;
absence of a callback is **inconclusive** and does not prove the TV
is patched.

**On the TV:** leave the previous RDP session, edit the existing
Remote PC connection's password to the printed probe **exactly**
(including shell characters), ensure **Remember credentials** is on,
reconnect using username `danstvprobe`, then open Samsung's **Shared
Folder** control and select `DansTVProbe` once. An RDP or SMB login
failure before reaching Shared Folder is not a root-test result.
Do not paste the temporary credentials into chat or GitHub.

Regardless of the test outcome:

```powershell
.\scripts\tiz0wn\uid-probe.ps1 -Action Restore
.\scripts\tiz0wn\rdp-lab.ps1 -Action Status
```

This puts the original temporary `danstvprobe` password back in
Windows and XRDP, stops using the one-shot callback, deletes the extra
firewall rule and removes the temporary credential backup. Restore
the **TV saved** Remote PC password as well. When testing is complete,
`rdp-lab.ps1 -Action Cleanup` removes the lab account/share,
including any remaining one-shot callback firewall rule and backup.

The callback URL contains the Bash effective-UID variable, not
persistent device changes. Actual `root` proof is limited to this
specific execution path. Unlike the stock Q60T proof, it depends on
a network callback being permitted; callback failure can also mean
credentials were rejected, a TV field character was changed, shell
parsing differed or networking failed.

## Step 2: Root route — separate, firmware-gated stage

1. Clone tiz0wn into ignored `.local/tiz0wn-upstream` or a separate development
   directory. It contains a vendor-specific Remote PC/CIFS proof, an offline
   firmware-image patch builder, and a persistent root command agent.
2. Use the Q80T's *exact* firmware and full build string to decide whether any
   root route applies. Tiz0wn's verified Q60T profile
   (`GQ55Q60TGUXZG / T-NKLDEUC-REL-202607022001`) is not the Q80T.
   Its Q90T report describes the related `T-NKMDEUC` family,
   but that is a different regional image from Q80T's `T-NKMUABC`.
3. Run upstream's **offline** builder tests before attempting a TV exploit.
   Derive hash/offset targets from the **matching official Q80T firmware**.
   Never reuse the Q60T's p19 or Q90T's p18 patch offsets.
4. Establish a bounded root command channel and a working recovery command
   before using either of the root-side scripts here. Ordinary SDB on this
   retail Q80T does not offer an interactive shell.
5. Keep any root listener disabled when not needed. Prefer tiz0wn's
   local-command-file agent over unauthenticated LAN root-shell projects.

We have not copied or installed the root acquisition chain. Its hardware
applicability cannot be inferred solely from the Tizen major version.

## Step 3: Measure the baseline

After a root channel exists, run `snapshot.sh` through that channel and save
stdout to a **private local file**. The script reads Linux's `/proc/stat`
over one second, selected `/proc/meminfo` fields, running processes,
`pkgcmd -l`, and the native Home key row. It does not write the TV.

Compare snapshots in consistent situations:
Samsung Home idle, DansTV idle, and after exercising app navigation/return.
This is the missing actual-TV CPU/RAM baseline; do not treat browser
timings as hardware benchmarks.

## Step 4: Home key — root-side experiment

Source: tiz0wn's `live/home-ctx.sh` and
`docs/home-key-menu-plan.md`. On its verified Q60T Tizen 5.5 routed
`XF86Home` through `tvctx-manager` and
`/opt/dbspace/.app-context.db`, not `db/appfw/home_appid`.

After checking **your Q80T's** table/owner and confirming a functioning root
channel, stage `home-ctx.sh` on the TV and invoke it explicitly with the
installed DansTV app ID (from `.local/signing.json`, not a template ID):

```sh
sh home-ctx.sh status  YOUR10CHARID.DansTV
sh home-ctx.sh backup  YOUR10CHARID.DansTV
# Copy BOTH saved baseline files from /opt/usr/share/danstv-home/ to your PC,
# confirm the copied DB hash matches, and keep an independent recovery channel.
DANSTV_HOME_WRITE_CONFIRM=I_HAVE_OFF_TV_BACKUP sh home-ctx.sh apply YOUR10CHARID.DansTV
# Check the physical Home button from a source and from a streaming app.
sh home-ctx.sh restore YOUR10CHARID.DansTV
sh home-ctx.sh status  YOUR10CHARID.DansTV
```

The script only changes the exact Samsung `XF86Home` **short-press**
`key_filter` row and inserts a managed app row. It checks that the original
Samsung Home row is present, takes a consistent SQLite baseline backup before
a write, uses a transaction, reloads the TV context manager, and can restore
the original target and remove the added managed row. Long-press rules and
other app entries are left alone.

The script expects a full-screen managed app reference
(`com.samsung.tv.searchall`) and refuses to guess if absent. It is not
capable of creating root access. A reboot before the initial restore is not
part of this experiment. Even on the source Q60T, second-press toggle and
Back behaviour were not solved: examine them before enabling persistence.

## Step 5: Wake and cold-boot startup

Tiz0wn verified on its Q60T that the **already persistent root boot hook**
can request `app_launcher -s <app-id>` after the Tizen web-app framework is
available. Our `boot-launch.sh` is a separate, bounded one-shot component.
It has a `check` (no launch) mode and a `start` mode with a maximum
of three attempts through `timeout`. It does **not** create a boot hook.

Only after root persistence and Home restoration are verified on the Q80T,
stage this file into the root agent's controlled payload directory, and
test a one-time launch while Samsung Home remains the default:

```sh
sh boot-launch.sh check YOUR10CHARID.DansTV
sh boot-launch.sh start YOUR10CHARID.DansTV
```

Then independently integrate it with the firmware-specific *tiz0wn* boot
worker (or a verified platform `app_onboot` row) and perform a supervised
cold-boot test. Do not assume ordinary `on-boot` widget manifest
attributes are honoured by Tizen 5.5. Never launch the web app ahead of the
web-app service's readiness. Measure startup and keep a boot-level disable
marker so recovery doesn't depend on the launcher UI.

## Step 6: Debloat — adopt the reversible upstream levers

Once root and **live inventory** are confirmed, use upstream `pkgstate` to
**plan**, **disable**, read back and **enable** individual service apps. Avoid
deletion first: `pkgcmd -u` uninstall can be difficult to reverse without the
exact original package. Tiz0wn's tested `pkgstate` tracks global disable
flags and has a transaction log; some multi-app packages are deliberately
refused.

| Candidate to examine first | Effect to verify |
| --- | --- |
| `org.tizen.acr-service-app` | Automatic content recognition/tracking |
| `org.tizen.multi-assistant-service` | Voice assistant functionality |
| `com.samsung.tv.multiscreen` | Multi View / casting |
| `org.tizen.ScreenMirroring-daemon` | Screen mirroring |
| `com.samsung.tv.nfc-monitor` | NFC pairing |
| `com.samsung.tv.waapp-contents-provider` | Wireless-audio content browsing |

These are **candidates from Q60T research**, not a Q80T disable list.
Preserve `com.samsung.tv.csfs` until Home takeover/rollback is proven,
`org.tizen.tv-viewer` for free-to-air TV and HDMI, DRM/app-launch
infrastructure, all your streaming apps including Jellyfin, network
services, and the app/package manager.

Example, once upstream pkgstate is actually staged, reviewed and available on
the *rooted* TV:

```sh
sh pkgstate plan disable org.tizen.acr-service-app
# If preflight and planned reversal are both verified, test exactly one:
sh pkgstate disable org.tizen.acr-service-app
sh pkgstate enable  org.tizen.acr-service-app
```

Do not bulk-apply Q60T package lists to the Q80T. Disable progressively;
record RAM/CPU and functional regressions after each candidate, then build
a Q80T-specific allowlist with rollback entries.

## Offline validation

Run `python scripts/tiz0wn/check.py` (also included in `npm run win:check`).
The test executes the actual apply/restore SQL in an isolated SQLite database
and checks that unrelated Home-key and managed-app records are preserved.
It does **not** prove compatibility with the Q80T registry or root context.

Run `python -B scripts/tiz0wn/test-root-bridge.py` for local HTTP transport
and password/session checks. The additional full Bash/curl integration
test runs only in a disposable Linux root container with curl installed.
Never run that test as root on a TV.

## Source references

- [tiz0wn](https://github.com/sebastianspicker/tiz0wn) (MIT)
- [Tizen 5.5 Home key trial](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/home-key-menu-plan.md)
- [Home context script](https://github.com/sebastianspicker/tiz0wn/blob/main/exploits/tiz0wn-root/live/home-ctx.sh)
- [Debloat capability research](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/debloat-capabilities.md)
- [Debloat plan and rollback](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/debloat-plan-2026-11-05.md)
- [Root compatibility and firmware coverage](https://github.com/sebastianspicker/tiz0wn/blob/main/README.md)

The original license and upstream author credit must be retained if distributing
adapted scripts. Do not bundle or redistribute Samsung firmware images.
