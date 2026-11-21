# Q80T Home-button database backup — pre-write gate

Target: **QA65Q80TAWXXY**, firmware **T-NKMUABC-2743.0**.
Installed DansTV app ID observed through SDB `applist`:
`iN5p1j5y6b.DansTV`. The tracked source manifest's
`nClrkHome1.FrameHome` is **not the installed application ID**.
SDB's `sqlite3 -readonly ... "PRAGMA quick_check;"` produced no
output despite returning 0; therefore it did **not** verify database
access or integrity.

The original 21 November snapshot shows:
`com.samsung.tv.csfs` handles `XF86Home`, launch request,
`target_selector=package:com.samsung.tv.csfs`,
`args=entry_point:smarthub_key`. This text survey is **not** a
restorable SQLite backup.

## New source change — awaiting Q80T hardware confirmation

The existing **checksum-gated** staged `snapshot.sh` now exports an
**offline-verifiable consistent SQLite backup** of
`/opt/dbspace/.app-context.db` as Base64 in the **private** snapshot
report. It uses SQLite `.backup` with the live **source read-only**,
opens its temporary destination under `/tmp`, validates both
`PRAGMA quick_check=ok` and the **exact original Home row**, bounds
the export at 256 KiB, includes a SHA-256 digest, and removes the
temporary file. This does **not** edit the live Home database.
The private report can contain other app-context records: **never
publish or commit it**, even though the report is text.

After the next successfully received snapshot, from the repo's
PowerShell directory, run:

```powershell
py -3 .\scripts\tiz0wn\extract-home-backup.py .\.local\tiz0wn-lab\snapshot-<NEW-TOKEN>.txt
```

Replace the placeholder with the full path printed as
`SNAPSHOT-RECEIVED`. The extractor runs **offline**, verifies
framing, exact firmware, expected byte count, SHA-256, SQLite
`PRAGMA quick_check` and original `XF86Home` row, and writes a
new **exclusive** file alongside the report named
`snapshot-<NEW-TOKEN>.home.db`. It refuses to overwrite any prior
backup. It reports whether the currently installed DansTV app already
has a `managed_app` row and whether the reference fullscreen app
`com.samsung.tv.searchall` is present.

A missing `HOME-DB-BEGIN` or `HOME-DB-UNAVAILABLE` means **backup
not acquired**. Do not infer success from an SDB exit code or from
`SNAPSHOT-RECEIVED` alone.

## Gates before any Home-button write

1. Successful **off-TV** extractor output:
   `HOME-BACKUP-VERIFIED`, including matching byte count/digest,
   and confirmation that the original Samsung Home row is present.
2. Independently operable **recovery mechanism**, not relying only on
   the Home button or the same temporary Remote PC exploit route.
   This is **not yet established**.
3. Live Q80T-specific check of `managed_app` and `tvctx-manager`
   reload semantics; do not assume a borrowed model's method works.
4. A deliberately scoped one-step Home trial with immediate
   restore and cold-boot functional tests after recovery is verified.

**No Home modifications are currently authorised.** The separate
`home-ctx.sh` `backup`/`apply`/`restore` implementation remains
unexecuted and must not be invoked as though independently tested.
