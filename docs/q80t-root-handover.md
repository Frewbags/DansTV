# Q80T root integration handover

Updated **21 November 2026**, after the successful read-only TV trial.
Branch: `feature/q80t-windows-setup`; draft PR #1.
Target: **QA65Q80TAWXXY**, **T-NKMUABC-2743.0**, Tizen 5.5 / ARMv7.

**Resume from the saved snapshot, not from root acquisition.**
See [verified hardware milestone](q80t-nov21-snapshot-success.md),
[operating procedure](../scripts/tiz0wn/README.md) and
[completion checklist](q80t-finish-checklist.md).

## What actually worked

On 21 November, the owner completed a single checksum-gated
SDB-stage → Samsung Remote PC → Shared Folder → local HTTP report trial:

- Windows: `npm run check:home` passed (Home/static checks, 9 cleanup
  tests, 15 transport cases with 3 Linux-only skips, 7 assessment tests).
  The PowerShell source parser check also passed after fixing a malformed
  `ListenStaged` block. Disposable Linux ran **15/15** transport tests.
- Host Doctor passed exact Q80T model/firmware and owned lab prerequisites.
- `root-bridge.ps1 -Action PrepareStaged` reported `STAGED-READY`.
  This uploaded **two** fresh staging files through SDB and rotated only
  the dedicated disposable Windows/XRDP credentials.
- `root-bridge.ps1 -Action ListenStaged` entered
  `Snapshot receiver ready`. The owner connected from Samsung Remote PC
  and opened **Shared Folder once**.
- Listener reported `STAGE-HASH-VERIFIED` then `SNAPSHOT-RECEIVED`.
  The assessor reported the exact firmware marker matched and read-only
  Home preference, `XF86Home` and service-prerequisite observations.
- On exit, the dedicated XRDP lab was restarted, the temporary listener
  permission revoked and the **original host/XRDP credentials restored**.
  The owner's TV-saved Remote PC password needs to match the normal
  credential again; that step was not separately confirmed.

The private snapshot is saved under ignored
`.local/tiz0wn-lab/snapshot-*.txt` on the owner's PC. It was **not**
uploaded to GitHub. Its token-bearing filename and full contents may
reveal private device/network identifiers: never paste or commit them.

**Meaning:** one successful full read-only diagnostic, with report framing
and an on-TV survey-body checksum. This is stronger than the earlier
16 November one-shot UID-0 proof, but **not** cryptographic device
attestation, an authenticated persistent broker, a reusable root shell,
Home control, boot persistence or proven independent recovery.
No TV system configuration, Home mapping, firmware or packages changed.

## Why the working method is different

The first staged trial failed at SDB `pull`:
`You cannot pull files from this path`. Despite
`filesync_support:pushpull`, this TV does not permit pulling that staging
path; SDB root and interactive shell are disabled.

The successful path **does not use SDB pull**. It stages a tiny loader and
the separately generated fixed survey using SDB `push` acknowledgments.
When the owner triggers the previously demonstrated Remote PC/Shared Folder
execution context, the loader computes the TV-side survey SHA-256 and
POSTs only its checksum. The bounded receiver compares it with the host
copy, approves a matching one-use session, then accepts a framed
read-only result. Report collection and credential restoration are
automatic on normal listener completion.

The loader itself is not independently attested; receipt/marker checks are
not cryptographic identity checks. Keep the receiver confined to the
trusted LAN. `root-bridge.ps1` is the **hardware-tested pathway**.
The separate `staged-snapshot.ps1` and its Python companion are
unfinished prototypes and **must not** be substituted.

## Read-only evidence from the assessor

- Exact firmware marker matched.
- `db/appfw/home_appid`, `db/appfw/startup_appid`,
  `db/appfw/booting_appid_backup`, `db/first_screen/type`,
  `db/menu/smart_hub/ontvsetting/auto_start`: **reported**.
- `XF86Home` context: **observed**.
- Node in shell PATH, dotnet launcher, app-data directory, survey shell
  SMACK label: **observed**.
- **Still unmeasured:** native Home main-operation handler, Tizen
  web-service Node runtime, authenticated root broker.
- **Home/startup write authorisation: NO.**

The assessor deliberately suppresses original values. Presence of a
section does not prove the value, a valid app mapping, service runtime,
SMACK permissions or compatibility with a borrowed Home method.
Inspect the full report **locally and privately**.

## Where to resume (no TV session required)

1. **Preserve** the existing snapshot, receipt metadata and local lab
   configuration. Confirm the original host credentials and firewall are
   restored; `root-bridge.ps1 -Action Doctor` should pass in
   Administrator PowerShell with Docker Desktop running.
2. **Review the actual saved report privately.** Record each Home
   preference and `XF86Home` table/schema observation with explicit
   query-success/missing-value status. Review service, mount, security-label
   and partition evidence; do not infer a root-owned broker from Node's
   presence.
3. **Plan an off-TV verified backup** of the original Home database and
   typed preference values, plus an independent restoration mechanism.
   The current read-only snapshot is **not** that database backup.
4. **Identify the Q80T-native Home main-operation handler** and what
   happens with Back, Live TV, HDMI, standby and app return. Do not use
   a 2022 Tizen 6.5 or different-model `home-ctx.sh` mapping on assumption.
5. Only after backup/recovery are proved, separately consider a
   reversible, model-specific Home routing experiment. Boot and
   debloat changes remain separate gates.

**No further root trial is needed just to begin analysis.** A second,
fresh-session read-only run may be useful later to establish
repeatability, but this is not a current prerequisite to reviewing
the evidence already captured.

## Later repeat (if justified; not an automatic next action)

Use the [reviewed operating procedure](../scripts/tiz0wn/README.md):
verify tests/Doctor, `-Action PrepareStaged`, start
`-Action ListenStaged`, then a **single** owner-operated Remote PC
login and **single** Shared Folder activation. A successful receiver
prints `STAGE-HASH-VERIFIED` followed by `SNAPSHOT-RECEIVED`,
assesses locally and calls Restore. If the listener fails or is
interrupted, inspect recovery state and invoke
`root-bridge.ps1 -Action Restore` as needed, then Doctor.

Do **not** use the older `-Action Prepare` long-password flow,
the failed SDB-pull gate, or the untested separate
`staged-snapshot.ps1 -Action Prepare`.

## Upstream architecture / remaining restrictions

The [Curtisg890/Vetro Tizen 5.5 assessment](q80t-vetro-tizen55-architecture.md)
separates root acquisition, authenticated broker, widget, Home routing
and boot persistence. The fork's TU7000/KTSU firmware is not this
Q80T/NKMUABC build, and its public code does not supply this TV's
native Home mapping, an installed root broker or safe boot hook.

No changes to firmware, installed packages, Home/startup, service
disablement or raw partitions have been authorised or executed.
**Cold-boot persistence and firmware writes remain blocked** until an
exact matching official image, verified original-block backups and
a credible independent recovery path exist. Never transfer
foreign-model offsets.
