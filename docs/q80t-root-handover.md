# Q80T root integration handover

Originally 16 November 2026; revised 21 November 2026. Branch: `feature/q80t-windows-setup`; draft PR #1.

> **21 November hardware follow-up:** The read-only snapshot remains uncollected. Normal RDP/Shared Folder and restoration were verified; a 128-character alphanumeric credential and short punctuation credentials authenticated on the Q80T. A combined long/mixed-character test failed even though its Linux hash matched. The entry-transport cause is not yet established. The standalone Docker readiness checker passed locally; the new staged flow now has its own bounded XRDP/TCP readiness check, including during restoration. See [offline status and next-session checklist](q80t-nov21-offline-status.md) for the current evidence. Do not repeat old snapshot instructions blindly.

The [Curtisg890 Tizen 5.5 integration architecture assessment](q80t-vetro-tizen55-architecture.md) separates root acquisition, the authenticated broker, the web widget, Home routing, and boot persistence. **Nothing in the fork provides Q80T-verified boot persistence or a Q80T Home launcher.** The snapshot and assessor now include conservative read-only service-prerequisite signals, but no new TV evidence has been collected.

## Confirmed versus pending

- Owner confirmed Remote PC/CIFS effective UID 0 on QA65Q80TAWXXY / T-NKMUABC-2743.0. Preserve this milestone; do not retry the unavailable dotnet route.
- Current branch was pulled with fast-forward only; remote remained at `ce7f372` before this increment.
- Disposable Docker XRDP lab was observed running. No `lab.env.before-uid` backup remains. This is consistent with earlier restore, but Windows account/firewall state was not verified: the current agent process is not Administrator.
- Agent Bus connection was refused; no board claim was delivered. Its current sender accepts the token through `AGENT_BUS_TOKEN`, not the documented `-Token` switch.
- Snapshot transport now has Windows Prepare/Listen/Restore, fresh session tokens, fixed read-only inventory, combined stdout/stderr, EUID/exit framing, bounded HTTP, exclusive report creation, and normal temporary-file cleanup. The password helper accepts an exact active snapshot session as well as the original UID trial.
- No command in this increment contacted the television. No Home, package, startup or firmware changes were performed. Snapshot transport and credential restoration remain **hardware-unverified**.

## Validation

The standard tool suite needs Unix `termios`; `npm run check:tools` cannot run directly on this Windows Python installation. A disposable Linux container with a read-only repository mount, Git and curl passed all 15 tool tests, the existing Home SQL safeguards and all 8 transport tests. The latter include a real Bash command-substitution → curl download → source → report POST round trip against local Linux, including removal of the downloaded script. This is host evidence, not TV compatibility evidence.

PowerShell scripts parse successfully. Python diagnostics for the receiver are clean; Serena cannot resolve the optional `websocket` dependency, although the active Windows Python interpreter can locate the installed module. No app source changed.

## Resume here — staged short-password trial (21 November update)

**Do not run the obsolete `Prepare`/long-password snapshot sequence.** A new
`PrepareStaged`/ `ListenStaged` flow has been committed but **not tested on
the TV or the owner's Windows machine yet**. It is distinct from the older
failed long-credential experiment and has an SDB upload/readback + SHA-256
gate before rotating credentials. The exact staged file is base64-encoded
as shell content, avoiding UEP script-path execution; the Remote PC password
only references the staged text, without literal space, `<`, `|` or `&`.
A bounded HTTP callback remains for report receipt, not code download.

1. On the Windows PC with TV access: `git pull --ff-only origin feature/q80t-windows-setup`, then `npm run check:home`. If either fails, **stop**. From Administrator PowerShell run `.\\scripts\\tiz0wn\\root-bridge.ps1 -Action PrepareStaged`. It performs the Doctor preflight, SDB push/pull hash verification and XRDP readiness checks before reporting `STAGED-READY`. If SDB pull is denied, it stops *without* credential rotation.
2. Only after `STAGED-READY`, run `.\\scripts\\tiz0wn\\root-bridge.ps1 -Action ListenStaged` in the same elevated shell. On TV, connect to Remote PC with the printed temporary short password and open **Shared Folder** once. Receiver either validates a report or times out, then automatically restores lab credentials; check Doctor afterwards. Give the owner one action at a time and do not ask them to paste the lab password into chat. If interrupted before Listen, run `-Action Restore` and `-Action Doctor`.
3. Inspect the private report and receipt. Confirm UID, build, Home schema, native values, services and partition metadata individually; a successful report does not prove every optional query worked. Verify listener stop, firewall removal and dedicated credential restoration. Repeat with a fresh token to establish repeatability.
4. Extend the bounded operation allowlist only after the first complete TV trial. Capture a consistent Home DB backup and typed values, transfer and hash-verify off-TV copies, and prove restore transport before Home apply. The current snapshot does not export the full DB.
5. Validate reversible Home routing, physical navigation and rollback before any debloat. Measure actual services rather than importing a generic list.
6. Persistent boot work remains gated on the exact official NKMUABC image, live-build match, independently derived offsets and original block backups plus credible recovery. No foreign-model offsets.

Full commands, trial limits and restore procedure: `scripts/tiz0wn/README.md`.

## Upstream review

Reviewed the current tiz0wn issue #1 discussion and Q70T, USB-root and Vetro README references. Q90T testimony distinguishes Remote PC proof from its later USB/persistence work and warns about UEP, unsigned script execution and limited no-boot recovery. Vetro's current compatibility table does not support root features on stock Tizen 5.5. These are method references, never firmware compatibility proof for this Australian Q80T. No new upstream code was copied in this increment; retain existing notices.
