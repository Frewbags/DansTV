# DansTV Q80T completion gates

Updated 20 November 2026. Target only: QA65Q80TAWXXY, Tizen 5.5,
T-NKMUABC-2743.0. Owner branch: `feature/q80t-windows-setup`, draft PR #1.

## Current evidence

| Item | Status |
| --- | --- |
| Standalone DansTV web widget | Previously installed/launched by owner |
| Launcher/device simulation | **18/18 passed on owner's Windows PC (20 Nov)** |
| Cleanup planner simulation | **9/9 passed on owner's Windows PC (20 Nov)** |
| ESLint / widget static check | Passed on owner's Windows PC (20 Nov) |
| Cross-platform `npm run check`, Windows CI, snapshot assessor | Added subsequently; rerun/CI evidence pending |
| Volume / mute | Web API adapter has mock coverage; physical Q80T validation pending |
| HDMI, applications, Back and Samsung Settings | Automated mock coverage; full current-build hardware regression pending |
| Read-only root snapshot transport | Offline test implementation; **not yet verified on Q80T** |
| Elevated access | One bounded UID-0 callback observed, not an enduring root shell |
| Home-button replacement / cold boot | **Not achieved on this Q80T** |
| Service cleanup / boot modification | **Not applied** |

## Owner-side completion sequence

1. **Synchronise and test** from PowerShell, in
   `C:\Users\Daniel\DansTV`:

   ```powershell
   git pull --ff-only origin feature/q80t-windows-setup
   npm run check
   git status -sb
   ```

   Preserve `.serena/`, any private `.local/` files and pre-existing commits.
   If Git refuses a fast-forward, stop and review instead of resetting.
   `npm run check` is offline from the television.

2. **Validate the running web widget** separately: installed app identity,
   audio/mute, app launching, HDMI/console launch, Back, Samsung Settings,
   standby/wake. Keep Samsung Home accessible. Do not treat unit tests as
   physical-TV evidence.

3. **Run the read-only host Doctor** in Administrator PowerShell:

   ```powershell
   .\scripts\tiz0wn\root-bridge.ps1 -Action Doctor
   ```

   Doctor checks the exact saved model/firmware and local disposable lab
   prerequisites. It makes no TV change. Do not continue if a guard fails.

4. **With the owner present at the TV**, use the documented bounded snapshot
   procedure in `scripts/tiz0wn/README.md`. `Prepare` rotates only the
   dedicated Windows lab credentials, restarts its disposable XRDP container
   and opens a temporary firewall rule; `Listen` accepts one survey, then
   restores those changes. If interrupted after Prepare, explicitly use
   `root-bridge.ps1 -Action Restore`. Confirm the TV's saved Remote PC
   password is reset to the ordinary lab password. This is not a persistent
   root installation, nor is it risk-free.

5. **Keep raw reports private** under `.local/tiz0wn-lab/`. To produce a
   shareable evidence summary without raw IDs/IPs, run:

   ```powershell
   $report = Get-ChildItem .local\tiz0wn-lab\snapshot-*.txt |
     Sort-Object LastWriteTime -Descending | Select-Object -First 1
   if ($report) {
     py scripts\tiz0wn\assess-snapshot.py --report $report.FullName
   }
   ```

   The assessor checks report framing and whether specific Home values
   were captured. It is **not cryptographic authentication**, does not
   retrieve the native main-operation handler, and cannot authorise a write.
   Repeat a fresh read-only session before treating access as reliable.

6. **Resolve Home method and recovery** only after reviewing the actual
   Q80T evidence. Inspect `XF86Home` key-filter routing and the native
   main-operation handler independently; neither the 2022 Tizen 6.5
   Arn0 route nor the earlier Frame 2020 T-NKMDEUC implementation can be
   imported on assumption. Capture typed original values and a consistent
   `sqlite3 .backup` of any live Home database; transfer backups **off TV**,
   record SHA-256 values, and establish a separately accessible recovery
   route. The current bounded snapshot does not deliver this backup facility.
   No Home assignment until these gates are fulfilled.

7. **Perform one guarded, reversible Home trial**, only with a model-specific
   apply and tested restore procedure. Verify physical Home, Back, Live TV,
   HDMI and app return paths. Restore the saved baseline immediately after
   the trial before considering permanent routing. A successful API return
   alone does not prove correct physical Home handling.

8. **Only after Home succeeds**, evaluate cold-boot behavior separately.
   Defer persistent firmware/rootfs changes without an exact matching image,
   original block backups and credible hardware recovery. Debloat only
   individually measured, proven-safe Q80T services with reversible
   original-state flags; do not copy Tizen 9 or Android disable lists.

## Explicit stop conditions

Stop without changing the TV if the saved device/firmware differs, snapshot
is incomplete, original state is unknown, off-TV backups are absent, restore
cannot be independently invoked, the native operation is unmeasured, or a
second Home method is already active.

**Acceptance target:** DansTV opens with the physical Home button after
normal TV use, survives standby and cold boot, leaves the TV controls intact,
and can be restored to Samsung Home without relying on an unverified root
mechanism. This target is not yet demonstrated on the Q80T.
