# DansTV Q80T completion gates

Updated **21 November 2026** after a successful read-only root snapshot.
Target only: **QA65Q80TAWXXY**, Tizen 5.5, **T-NKMUABC-2743.0**.
Owner branch: `feature/q80t-windows-setup`, draft PR #1.

## Hardware evidence and current state

| Item | Status |
| --- | --- |
| Standalone DansTV WGT | Previously installed/launched by owner; latest physical regression pending |
| UI/device simulations | 18/18 launcher/device tests on Windows (20 Nov); latest physical checks pending |
| Home/static and cleanup guards | Passed on Windows 21 Nov; 9/9 cleanup tests |
| Bounded snapshot transport simulations | Windows 15 cases passed (3 Linux-only skipped); **Linux 15/15 passed** |
| Read-only report assessor | **7/7 passed**; hides raw private values |
| Windows PowerShell parser | Passed following 21 Nov syntax fix; included in `check:home` |
| Root diagnostic on Q80T | **SUCCESS, 21 Nov: TV checksum verified, complete framed snapshot received** |
| XRDP/Windows credentials | Listener logged **access revoked and original lab credentials restored**; TV-saved password still to verify |
| Home preferences and `XF86Home` | Report sections/indicators present; original values require **private review** |
| Node PATH / dotnet / app-data / shell SMACK label | Observed in read-only snapshot; **service/runtime compatibility unproven** |
| Native Home main-operation | **Not measured** |
| Privileged service / authenticated broker | **Not provisioned or verified** |
| Independently verified off-TV Home DB backup / recovery | **Not done** |
| Home replacement and cold-boot persistence | **Not achieved** |
| Debloat, Home writes, firmware/boot changes | **None applied** |

The [verified milestone record](q80t-nov21-snapshot-success.md) preserves
the observed sequence and privacy boundaries. The older
[offline status](q80t-nov21-offline-status.md) is historical pre-success
evidence, not the current instructions.

## Verified snapshot method (for later reuse, not the immediate next task)

The TV rejected `sdb pull` from its SDK staging path despite advertising
`filesync_support:pushpull`. The working **checksum-gated** method
does not attempt SDB pull. Instead, the host SDB-pushes a loader and a
separate fixed survey. The owner connects Samsung Remote PC and opens
Shared Folder **once**. The loader sends the survey's TV-observed SHA-256
to the one-use LAN receiver, which only approves the expected digest.
The survey posts a bounded, framed report. The wrapper then restores the
disposable account and callback permissions.

The tested entrypoint is
`scripts/tiz0wn/root-bridge.ps1 -Action PrepareStaged`, followed by
`-Action ListenStaged` **before** the TV action; see the
[operational README](../scripts/tiz0wn/README.md) for preflight,
safe failure and restoration instructions. The older long-password
`-Action Prepare` and the separate untested
`staged-snapshot.ps1 -Action Prepare` are **not** replacements.
One successful trial does not prove repeatability or establish
cryptographic attestation.

## Resume work — no TV operation needed

- [ ] Preserve raw report/receipt **only** in the owner's ignored
      `.local/tiz0wn-lab/` directory; never commit, paste or publish
      raw values, private addresses, token, password or unique device IDs.
- [ ] Verify `root-bridge.ps1 -Action Doctor` after Restore if not yet
      rerun, then ensure the TV's saved Remote PC password uses the
      ordinary restored lab credential.
- [ ] Privately inspect the actual five Home preference values and
      `XF86Home` context. Distinguish successful query/value from
      placeholder, missing row or error; don't infer mappings from
      the safe assessor's `reported` wording.
- [ ] Examine service/SMACK/runtime/partition evidence. Verify the
      native Home main-operation handler separately; it was not measured.
- [ ] Capture exact current Home DB/key-filter schema and typed originals.
      Establish a **consistent off-TV copy with verified hash** and a
      separately accessible restore/recovery route before any write.
- [ ] Review the [Vetro architecture comparison](q80t-vetro-tizen55-architecture.md).
      Keep signed web-service runtime and authenticated broker work
      separate from the read-only snapshot success.

## Later gated acceptance sequence

1. **Reversible Home trial**: only with model-specific native handler,
   independently tested recovery, off-TV backups and exact-value
   restore plan. Physical Home, Back, Live TV, HDMI, app returns,
   standby/wake and Samsung Settings must be checked.
2. **Cold boot / persistence**: test only after Home works safely;
   never use Q60T/Q70T/Q90T offsets on this NKMUABC firmware.
   A matching official image, original block backup and credible
   hardware recovery remain mandatory for any firmware work.
3. **Cleanup/debloat**: identify specific Q80T services/dependencies
   and allow only reversible, bounded changes, preserving tuner, DRM,
   connectivity, updates and app lifecycle.
4. **Repeatability**: if later needed, a fresh read-only session
   should independently reproduce checksum verification, snapshot
   receipt, and restoration. Do not infer repeatability from one run.

## Stop conditions

**No Home/startup/firmware writes** if the original values are not
known, native operation is unmeasured, off-TV copies cannot be
verified, recovery is not independently available, model/firmware
has changed, or an existing Home method could conflict.

**End goal (not yet achieved):** DansTV opens with the physical Home
button, survives standby/cold boot, keeps the original Samsung
essentials operational and can be restored independently.
