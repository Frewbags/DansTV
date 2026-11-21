# Q80T offline status — historical pre-success record (21 November 2026)

**Superseded for operational use.** Later on 21 November the owner
successfully completed the checksum-gated `root-bridge.ps1` staged
read-only snapshot with `STAGE-HASH-VERIFIED`, `SNAPSHOT-RECEIVED`,
a positive privacy-preserving assessor summary and automatic restoration
of the dedicated Windows/XRDP lab credentials. The **SDB pull restriction**
was bypassed by verifying the survey SHA-256 from the TV; SDB pull was
not used in the working method.

**Current source of truth:** [verified hardware milestone](q80t-nov21-snapshot-success.md),
[current handover](q80t-root-handover.md) and
[canonical operating instructions](../scripts/tiz0wn/README.md).
Do not follow the old long-password or SDB-pull steps below.
The text below is preserved as evidence of *earlier* unsuccessful
attempts, not as a description of the current branch or TV state.

---

## Archived earlier troubleshooting (before the successful snapshot)

Scope: owner-operated QA65Q80TAWXXY, T-NKMUABC-2743.0 (Tizen 5.5). This note records observed behaviour and host-only checks. It **does not** establish that a full privileged snapshot has been collected and it does not authorise Home/startup/firmware writes.

## Evidence established on hardware

- The earlier *short* Remote PC → Shared Folder diagnostic produced one UID-0 proof (16 November). This is not proof of a repeatable root channel or of Home-button control.
- With the normal generated lab password, Samsung Remote PC connects to the disposable **Windows-PC-hosted** Docker XRDP desktop; Shared Folder shows the test JPG. The Samsung TV is the RDP client; XRDP is **not installed on the TV**.
- After a Prepare → Restore cycle, Doctor passed, the container was observed `running`, and TCP/3389 accepted connections. The normal TV Remote PC and Shared Folder login then worked.
- One earlier Compose recreation had left the XRDP container in `Created` with no listener despite Compose reporting a start; a manual container start recovered it. This **is not fixed in root-bridge.ps1**; the standalone readiness checker is an independent diagnostic.
- The original longer snapshot attempts did **not** yield a validated report. At least one failed before the Shared Folder step. On timeout/cancellation, the listener printed `NO-REPORT`, performed its Restore, and a subsequent Doctor passed.
- Samsung's built-in remote text injection could display a password without committing it. Changing and removing a character committed the normal generated password, but not all longer test inputs.
- SmartThings entered and Samsung authenticated a **128-character alphanumeric** password against a matching disposable Linux XRDP account. Short passwords with `$` and with other punctuation also authenticated.
- A combined 128-character password with punctuation failed XRDP PAM authentication **even though** an independent shadow-hash comparison reported the full intended password matched. This suggests a client-entry/transport mismatch, but the exact character corruption/truncation is **unproven**.
- Previous 32-character test failures were explained by a credential-setting mismatch; changing the password interactively via `passwd` led to successful Windows RDP and Samsung logins. Do not generalise this to all future failures.
- Disposable test users `tvlengthtest`, `tvsymboltest` and `tvinputtest` were reportedly removed at the end of testing. Verify if needed; do not assume the names still exist.

## Source review findings at the earlier point in time (historical)

- `scripts/tiz0wn/root-bridge.ps1` currently defines `Doctor`, `Prepare`, `Listen`, and `Restore`; **the checked-in diagnostic password construction is unchanged**. Nothing in this note changes it.
- `Rotate` checks Docker's engine and Compose exit status but does **not** wait for a `running` container or a listening TCP/3389. `Doctor` also does not assert this condition. This explains how a false-success report remains possible.
- `Restore` retains the backup if `Rotate` throws, but successful Compose exit alone does not prove operational XRDP, and authentication on the TV is a further separate gate.
- `paste-password.py` uses Samsung's text-input command and explicitly warns it cannot tell whether the TV accepted the field value.
- `root-bridge.py` only accepts a validated report from the configured TV IP, tied to a one-time session token and expected report markers. **No such report has yet been obtained on this Q80T**.
- The independently developed `tools/container-readiness/` utility was reportedly verified locally with 23 Pester tests and a real `READY` response. **It is not present on the GitHub branch at the time this note was written**; preserve/commit it from the Windows checkout if desired.

## Updated offline architecture work

The [Curtisg890/Vetro Tizen 5.5 architecture comparison](q80t-vetro-tizen55-architecture.md) has been completed. The snapshot survey now includes read-only shell observations for Node presence, the signed dotnet launcher, app-data directory and survey SMACK label. The private-report assessor reduces those to **statuses only**; it never treats them as a verified service runtime, trusted broker or permission to modify Home. Synthetic tests were added to `test_assess_snapshot.py`; they still require execution in a checkout or CI to establish a passing run.

## Work possible without the TV

Run from the Windows repository root, with Docker Desktop running. These checks do not start a TV diagnostic trial:

```powershell
npm run check:home
.\scripts\tiz0wn\test-compose-interpolation.ps1
.\scripts\tiz0wn\root-bridge.ps1 -Action Doctor
docker ps -a --filter "name=danstv-remote-pc-lab"
```

The `Doctor` command requires Administrator PowerShell. The Compose interpolation test uses synthetic credentials and does not read the actual lab password. The readiness checker can be used separately from the local checkout, specifying the address from the ignored ownership marker and port 3389. A TCP-ready status does **not** prove authentication.

Before finishing host-only work, confirm no `lab.env.before-snapshot`, `lab.env.before-uid`, or `snapshot-session.json` marker remains and that Doctor passes. Do not paste `lab.env`, tokens, shadow hashes, raw snapshot reports, device serial numbers or unique network identifiers into chat or commits.

## Earlier next-session plan (superseded)

1. Confirm normal Remote PC and Shared Folder authentication (known-good baseline), and verify that the backup, firewall and listener have returned to their normal state.
2. Establish an **independent, harmless** end-to-end test for the exact long/mixed-character text-entry behaviour before relying on a diagnostic password. A saved hash match on Linux alone is not sufficient.
3. Review host-side lifecycle readiness and failure recovery. Keep test-account authentication separate from the privileged diagnostic.
4. If a full read-only inventory is subsequently obtained, review actual Home preferences, key-filter schema, services and partition metadata; retain an off-TV original database copy and independent recovery proof before any state-changing Home work.

## Earlier status before the successful trial (superseded)

No complete privileged snapshot, independently recoverable Home database backup, proven Home-button redirection, validated persistent boot hook, or model-exact firmware patch. Q70T/Q90T results on T-NKMDEUC must not be assumed compatible with this T-NKMUABC Q80T.
