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

## Source references

- [tiz0wn](https://github.com/sebastianspicker/tiz0wn) (MIT)
- [Tizen 5.5 Home key trial](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/home-key-menu-plan.md)
- [Home context script](https://github.com/sebastianspicker/tiz0wn/blob/main/exploits/tiz0wn-root/live/home-ctx.sh)
- [Debloat capability research](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/debloat-capabilities.md)
- [Debloat plan and rollback](https://github.com/sebastianspicker/tiz0wn/blob/main/docs/debloat-plan-2026-11-05.md)
- [Root compatibility and firmware coverage](https://github.com/sebastianspicker/tiz0wn/blob/main/README.md)

The original license and upstream author credit must be retained if distributing
adapted scripts. Do not bundle or redistribute Samsung firmware images.
