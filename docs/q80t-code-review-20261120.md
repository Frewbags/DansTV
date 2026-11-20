# DansTV Q80T — focused code review (20 November 2026)

Scope: `feature/q80t-windows-setup`, draft PR #1. Static review of the
Windows deployment, bounded snapshot transport, Home research controls and
release readiness. **No television commands or privilege changes performed.**

## Corrected in this review

| Priority | Finding | Correction |
| --- | --- | --- |
| P1 — recovery | `root-bridge.ps1 -Action Restore` was blocked by a changed/missing **TV** address or firmware preflight even though it only needs to revoke and recover the dedicated local lab. This could prevent credential recovery after Prepare. | Restore now retains the exact dedicated account/share ownership guard but does not require current TV/preflight records. Fresh Doctor/Prepare/Listen still require Q80T model and firmware checks. |
| P1 — recovery | A snapshot session without its credential backup was silently removed and the script incorrectly reported successful credential restoration. | Revoke the temporary rule, preserve the orphaned session file and **fail explicitly** that local password state is unknown; only claim credentials restored when the backup was actually replayed. |
| P2 — preflight | Doctor checked port occupancy but could pass despite a stale temporary callback firewall exception. | Reject an existing named snapshot firewall rule; direct the owner to Restore. |
| P2 — Windows | `q80t-windows.ps1` still invoked `python` despite the user's confirmed `py` setup and the new cross-platform runner. | Use `py -3` consistently for owner widget preparation and signed-package verification. |

These are code corrections, **not** evidence of successful on-TV Home routing or
live execution of the recovery path. PowerShell behaviour needs verification
on the owner's Windows environment.

## Open risks and acceptance gates

1. **P1 — no tested restore of TV Home:** The Q80T has no evidenced Home
   baseline exported and verified off-TV, no proven independent restore
   transport, and no real physical Home/Back/cold-boot trial. Do not apply
   `home-ctx.sh`, Arn0's different routing method, or startup modifications.
2. **P1 — root survey runs sourced network code:** The bounded diagnostic
   fetches a temporary shell script over unauthenticated **HTTP** on a trusted
   private LAN and sources it in a privileged context. Its token/source checks
   protect the PC receiver, not the shell's download against active LAN
   interception. Keep this strictly isolated; do not repurpose it for
   persistent operations or treat its success markers as attestation.
   A stronger transport/integrity design is recommended before any
   privileged state-changing extension.
3. **P2 — unverified TV APIs:** Optional `TVAudioControl` and app/HDMI launch
   paths have synthetic test coverage but must be physically exercised on the
   current Q80T firmware and output configuration.
4. **P2 — no completed CI on the reviewed head:** The new `npm run check`
   combines lint, launcher mocks, offline assets and Home/transport/assessment
   tests. Windows/Linux workflow jobs are declared, but GitHub had no recorded
   runs at review time. The previously reported Windows 9/9 cleanup and 18/18
   launcher successes predate the latest changes; do not claim they verify
   this head.
5. **P2 — licensing boundary:** Bundled Kayo/7plus/9Now/10 Play icon
   adaptations are attributed separately as CC BY-NC-SA 4.0, not under the
   repository's MIT code licence. Preserve notices and do not market or
   commercially redistribute them as MIT assets. See
   `THIRD_PARTY_NOTICES.md`.

## Next owner-side check (no television changes)

```powershell
git pull --ff-only origin feature/q80t-windows-setup
npm run check
# Administrator PowerShell only, after the test suite passes:
.\scripts\tiz0wn\root-bridge.ps1 -Action Doctor
```

Stop on any failure or changed model/firmware/credentials. Before making any
TV Home changes, follow `docs/q80t-finish-checklist.md`.

Review outcome: **source-quality and rollback improvements committed; device
Home takeover and release acceptance remain blocked on hardware evidence.**
