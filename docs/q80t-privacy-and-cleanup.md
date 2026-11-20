# Q80T privacy, Home and cleanup notes

**Target:** Samsung QA65Q80TAWXXY, Tizen 5.5, T-NKMUABC-2743.0.
References are other-device case studies, not drop-in Samsung configuration.

## Privacy settings (no privileged access required)

CleanYourTV's Samsung guidance recommends checking the 2019–2021 menu
**Settings → Support → Terms & Privacy → Privacy Choices**.
Look for these choices if they actually appear on the Q80T:

| Setting | Privacy-oriented choice | Notes |
| --- | --- | --- |
| Viewing Information Services (ACR) | Decline / Off | May reduce personalised recommendations |
| Interest-Based Advertisements | Decline / Off | Does not remove all ads |
| Customization Service | Off, if present | Personalisation features may change |
| Improve personalised ads | Off, if present | Availability varies by firmware |
| Get news and special offers | Off, if present | Optional promotions |
| Do not track | On, if available | Preference, not enforcement |
| Reset PSID | Optional, after consent changes | Rotates the advertising identifier |

Capture the actual before/after settings privately. These toggles are reversible
from the TV itself. Do not claim any particular switch is present until seen.
Source: https://cleanyour.tv/not-android

## What can be learned from related projects

- **CleanYourTV** (Gathin23): Android-only ADB disablement, safe-Home
  detection, reversible per-device changes. Its scripts cannot manage Tizen.
  See https://github.com/Gathin23/cleanyourtv/blob/main/docs/devices/samsung-tizen.md
- **Quiet Tizen** (jss8649): tested on a Tizen 9 U8000F, with grouped
  advertising/voice/extra cleanup profiles and field-specific registry rollback.
  Neither its app IDs nor its .NET installation method is validated on Q80T.
  https://github.com/jss8649/quiet-tizen
- **Arn0 Launcher** (NelsonEU): a web launcher whose guarded C# helper
  redirected Home on a Tizen 6.5 Q70B by updating the main operation and
  `db/appfw/home_appid`, saving the original state and restoring on failure.
  It did not independently verify cold-boot startup or test Tizen 5.5.
  Investigate this as an alternative to DansTV's existing app-context SQL
  trial; do not combine the two Home methods without a live baseline.
  https://github.com/NelsonEU/arn0-tv/blob/main/docs/setup-tv.md

## Read-only Home-button compatibility gate

The Q80T already has an experimental app-context/SQLite Home-key trial. Arn0
demonstrates a different native operation + vconf preference approach on a
2022 Q70B (Tizen 6.5). Neither method has yet been verified on this 2020
Q80T (Tizen 5.5). **Do not run both methods or copy Arn0's firmware guard.**

The existing `scripts/tiz0wn/snapshot.sh` now records these values without
changing them: `db/appfw/home_appid`, `startup_appid`,
`booting_appid_backup`, `db/first_screen/type`, and
`db/menu/smart_hub/ontvsetting/auto_start`. It also retains the current
`XF86Home` key-filter query and prints the release Version if available.
No defaults are inferred from failed/absent reads.

Before any Home assignment, separately establish (a) exact target app ID
on the installed Q80T; (b) actual native main-operation handler, which
this shell survey **cannot measure**; (c) Home key-filter database schema
and the actual original row(s); (d) full, independently verified off-TV
original-state backups; and (e) working restore access with a concrete
recovery test. Changes must be reversible, read back, and limited to a
single researched method. A successful launcher API callback does not
prove the physical Home button or cold boot behaves as intended.

The snapshot helper is not a general interactive shell or installer.
A fresh private hardware report has not yet been supplied; none of the
Home/startup routes is currently confirmed for this specific TV.

## Offline Q80T inventory and cleanup plan

`scripts/tiz0wn/cleanup-plan.py` is offline-only. It does not connect
to a TV and does not execute its generated SQL. Its inputs must come from
a fresh, consistent, **private** SQLite backup of the actual Q80T
`/opt/dbspace/.pkgmgr_parser.db` (use SQLite `.backup`, never copy an
active WAL database as a backup). The existing UID-0 callback is not a
general-purpose shell and has not yet produced this database.

After a verified private snapshot exists, generate an inspection file:

```powershell
py scripts\tiz0wn\cleanup-plan.py inspect `
  --snapshot .local\tiz0wn-lab\pkgmgr-q80t.db `
  --output .local\tiz0wn-lab\inventory-01
```

Do not copy another model's package list. Create a private copy of
`scripts/tiz0wn/q80t-cleanup-profile.example.json` below `.local/`.
Each selected candidate requires its exact observed app ID, a reason,
and evidence it can be disabled without impacting essential features.
The example groups deliberately contain **zero selected apps**.

Generate a reviewed, per-group plan:

```powershell
py scripts\tiz0wn\cleanup-plan.py plan `
  --snapshot .local\tiz0wn-lab\pkgmgr-q80t.db `
  --profile .local\tiz0wn-lab\q80t-reviewed-profile.json `
  --groups advertising `
  --output .local\tiz0wn-lab\advertising-01
```

Output includes `before.json` (model, declared firmware, SHA-256 of snapshot
and original flag values), `apply.sql` and `restore.sql`. The latter only
reverses flags targeted by the plan. Both scripts guard the full expected
state inside one SQLite transaction; they refuse concurrent changes.

The planner refuses duplicate/missing rows, unknown boolean values or schema,
protected app IDs, wrong declared firmware, and overwriting previous output.
**Generation is not permission to apply.** Actual live firmware identity,
dependencies, service state, backups and a working recovery route must be
verified separately before any on-TV modification. The generated SQL
does not disable services already running and does not edit systemd units.

Run offline source tests:

```powershell
py scripts\tiz0wn\test_cleanup_plan.py
py scripts\tiz0wn\check.py
```

## Network filtering is optional

Router-level DNS filtering may reduce unwanted connections but is not
equivalent to disabling tracking in the OS or apps. Start from observed
query logs; keep allowlisting and restoration available. Do not block
streaming, licensing, firmware updates or TV control without testing.

## Unfinished Q80T milestones

DansTV web widget works. The owner reported one bounded UID-0 callback
through Samsung Remote PC/Shared Folder. No verified general root shell,
Home takeover, debloat configuration or persistent boot patch exists.
Keep the original Samsung Home route accessible during any future trial.
