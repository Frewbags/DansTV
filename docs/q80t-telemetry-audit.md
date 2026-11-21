# Q80T telemetry audit — read-only, source-specific

Updated: 21 November 2026. Samsung QA65Q80TAWXXY,
T-NKMUABC-2743.0, Tizen 5.5 / ARMv7.
Evidence: the owner's successfully received 21 November read-only
snapshot, kept **privately** under ignored `.local/tiz0wn-lab/`.
This document contains only service identifiers and observations,
**not** the raw snapshot, personal values, token or addresses.

## What the existing snapshot proves

The following exact systemd units were **loaded and active/running**
at the snapshot instant:

| Candidate unit | Why investigate | Safe-disablement proven? |
| --- | --- | --- |
| `acr.service` | Description says automatic content recognition | **No** |
| `adagent-service.service` | Ad-agent daemon | **No** |
| `media-analytics-service.service` | Media analytics | **No** |
| `contents-recognition-service.service` | Content recognition | **No** |
| `vision-data-recognition-service.service` | Vision data analysis | **No** |
| `canalysis-service.service` | Named analysis component; purpose unclear | **No** |
| `kpi-logging.service` | Logging/performance metrics; not necessarily advertising | **No** |
| `issue_report_agent.service` | Issue-reporting agent; not necessarily tracking | **No** |

The installed-package summary also recorded
`org.tizen.acr-service-app`. The report does **not** contain
service dependency edges, per-service network traffic, remote
telemetry endpoints or a service-function audit. A running process is
not evidence that it sends viewing history to Samsung.

**Preserve these regardless of telemetry preferences until proven
otherwise:** `org.tizen.tv-viewer`, tuner/PVR/source/TV services,
`hdmicec-service`, `connman`, DNS/networking, audio, package/app
lifecycle, DRM, security/SMACK, updates and the Remote PC path used for
recovery. Do not use a generic Tizen 9 disablement list.

## Already prepared for the next *optional* read-only trial

`scripts/tiz0wn/snapshot.sh` now contains two additional bounded
sections incorporated automatically into the existing
checksum-gated `root-bridge.ps1` staged survey when it is next
generated:

- **Telemetry candidate unit inventory:** systemd unit state,
  main PID, unit definition path and dependency/relationship fields
  (`Requires`, `Wants`, `RequiredBy`, `WantedBy`, `PartOf`,
  `BindsTo`, `Conflicts`). It does **not** read `Environment`,
  `ExecStart`, the full unit file or secret-bearing command lines.
- **Candidate network socket counts:** if supported by the firmware,
  one process-associated `ss` snapshot for each unit's main PID;
  **counts only**, never endpoints, IP addresses or ports. If `ss`
  fails, the survey explicitly reports `not measured`. A count of
  zero is **not** proof of no activity: sockets can be transient,
  inherited from children or hidden from the snapshot. This is not a
  bandwidth measurement or traffic capture.

These new sections are **source changes only** until a fresh survey
is run. They have **not been hardware-tested** on the Q80T.
No root-trigger, receiver, TV app, system service or setting has been
changed as part of preparing them.

## What to do next

1. **No TV action required now.** Run offline validation of the
   updated `snapshot.sh` and existing transport before scheduling
   another diagnostic session.
2. If dependency evidence is needed later, generate a fresh
   staged survey via the **already hardware-tested**
   `root-bridge.ps1 -Action PrepareStaged` /
   `-Action ListenStaged` procedure with the owner present.
   Check `STAGE-HASH-VERIFIED` and `SNAPSHOT-RECEIVED` again,
   plus restoration of disposable credentials. Do not reuse any old
   session or the separate `staged-snapshot.ps1` prototype.
3. Analyse each candidate's actual dependency edges, binary
   behaviour and necessity. For evidence of telemetry transmission,
   prefer reversible router-side DNS/network monitoring with timestamps
   and attribution where possible. A socket count alone is insufficient.
4. Establish verified off-TV backups, original state and a genuinely
   independent recovery route before **any** stop/mask/disable operation.
   Test changes **one component at a time** against tuner, HDMI,
   streaming, DRM, connectivity, app updates and cold-boot behaviour.
   Return to baseline between candidate tests.

## Current decision

**No units are authorised for disabling yet.** First candidates for
dependency/traffic review: `acr.service` and
`adagent-service.service`. This shortlisting is evidence-based,
not a claim that disabling them is safe or effective.
