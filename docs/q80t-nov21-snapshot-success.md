# Q80T read-only root snapshot — verified hardware milestone

Date: **21 November 2026**. Branch: `feature/q80t-windows-setup`.
Target: Australian Samsung **QA65Q80TAWXXY**, **T-NKMUABC-2743.0**,
Tizen 5.5 / ARMv7.

Status: **one successful, owner-observed, checksum-gated read-only snapshot**.
This is not a persistent root shell, independently authenticated root broker,
Home-button reassignment, firmware patch, or verified recovery mechanism.

## Observed end-to-end result

In Administrator PowerShell, the owner ran `npm run check:home` and
`root-bridge.ps1 -Action Doctor`: both passed on the Windows PC.
The 15 transport tests passed in Windows with 3 Linux-only skips and
then all **15/15 passed in a disposable Linux container without skips**.
The other suites (9 cleanup tests, 7 assessor tests, Home SQL/static guards)
passed. The Windows PowerShell parser check had previously caught a malformed
receiver block; that block was fixed before this hardware session.

The owner then ran:

1. `root-bridge.ps1 -Action PrepareStaged` — **STAGED-READY**.
   Two unique files were SDB-uploaded to the TV's SDK staging area:
   a short loader and the fixed, read-only survey body. SDB acknowledged
   each upload. This was **not** an SDB read-back or byte-for-byte attestation.
2. `root-bridge.ps1 -Action ListenStaged` — **Snapshot receiver ready**.
3. On the TV, the owner connected Samsung Remote PC to the existing disposable
   Windows/Docker XRDP host using the prepared temporary credential and
   opened **Shared Folder once**.
4. The listener reported, in sequence:

   ```text
   STAGE-HASH-VERIFIED: TV observed expected survey bytes.
   SNAPSHOT-RECEIVED: [private report path]
   ```

5. The local assessor printed `Root transport: success markers present
   (not cryptographic proof)`, `Exact firmware marker: matched`, and the
   evidence summary below. The listener exited, then reported the disposable
   container started and **snapshot access revoked; lab credentials restored**.
   The TV's *saved* Remote PC password may still need updating separately.

The raw report and receipt metadata remain **only on the owner's PC** under
ignored `.local/tiz0wn-lab/`. The filename/session token, password, IP addresses,
unique device identifiers, raw Home values and report content must **not**
be copied into Git or public issues.

## The working method and the SDB limitation

The initial SDB `push` / `pull` verification attempt failed with
`You cannot pull files from this path`. The Q80T advertised
`filesync_support:pushpull` but had `intershell_support:disabled`,
`sdbd_rootperm:disabled` and `appcmd_support:disabled`; these capabilities
did not guarantee permission to pull the SDK staging file. That failed trial
stopped before rotating credentials.

The successful **checksum-gated** version removes SDB `pull` entirely.
The disposable lab uploads a loader and survey with fresh names. The
TV-side loader computes the survey's SHA-256 and POSTs that **digest only**
to the bounded LAN receiver. The receiver compares it against the locally
computed survey digest and replies `OK` only for a matching, single-use
session. The loader then invokes the pre-staged fixed survey; the receiver
accepts one bounded, correctly framed result and the wrapper restores
the disposable Windows/XRDP credentials and temporary firewall rule.

This verifies the **TV-observed survey body** matches what the host generated.
The loader itself is only SDB-upload acknowledged, not independently attested.
The receiver's IP/token checks and report markers are not cryptographic
device authentication. Do not expose it outside the owned trusted LAN.

## Read-only findings, and what they *do not* prove

| Observation from local privacy-preserving assessor | Status |
| --- | --- |
| Firmware | Exact marker matched |
| `db/appfw/home_appid`, `db/appfw/startup_appid`, `db/appfw/booting_appid_backup` | Reported |
| `db/first_screen/type`, `db/menu/smart_hub/ontvsetting/auto_start` | Reported |
| `XF86Home` context | Observed |
| Node executable in snapshot shell PATH | Observed |
| dotnet launcher executable | Observed |
| App-data directory | Observed |
| Snapshot shell SMACK label | Observed |
| Native Home main-operation handler | **Not measured** |
| Tizen web-service Node runtime | **Not measured** |
| Privileged/authenticated broker | **Not measured** |
| Home/startup modification | **Not authorised; none performed** |

`Reported` and `observed` mean the assessor saw evidence sections/indicators,
**not** that the original preference values were independently checked or that
Home re-routing is possible. The full report must be inspected **privately**.
There is no confirmed off-TV Home DB backup and no independently tested recovery
route. No firmware, Home mapping, startup configuration, apps, packages or
services were changed by this read-only trial.

## Resume procedure (not a request to repeat the trial)

**Current priority is analysis of the saved report, not another root trial.**
If a later read-only run is justified, use only the reviewed
`root-bridge.ps1 -Action PrepareStaged` then `-Action ListenStaged`
workflow in [the operational README](../scripts/tiz0wn/README.md).
Do **not** use the older long-password `-Action Prepare`, the original
SDB-pull procedure, or the separate unvalidated
`staged-snapshot.ps1 -Action Prepare` prototype.

Preflight: Administrator PowerShell, Docker Desktop running, exact saved
model/firmware/ownership, `npm run check:home`,
the 15-case Linux transport suite, then `root-bridge.ps1 -Action Doctor`.
If prepared, start the listener first, then connect Remote PC and open
Shared Folder **once**. Never repeatedly trigger a stale session.
On exit or interruption, verify Restore and Doctor; update the TV's saved
ordinary Remote PC credential if necessary. Never paste a credential, token
or private report into chat.

Next engineering gates, **before any TV write**:

1. Read the actual preference/key-filter values and service/partition
   metadata **privately**, recording each query's success or failure.
2. Establish a consistent, independently verified **off-TV** backup of the
   original Home database and typed baseline values.
3. Demonstrate an **independent recovery path** that does not depend on
   a fragile one-shot privilege trigger, before even a reversible Home test.
4. Determine native Home main-operation handling on this exact firmware;
   verify physical Home/Back/TV/HDMI behaviour only after rollback is sound.
5. Treat signed web-service runtime, broker authentication, boot persistence
   and any foreign-model offsets as **unproven**.

The milestone is a working **single-session read-only diagnostic**, not a
completed Samsung Home replacement.
