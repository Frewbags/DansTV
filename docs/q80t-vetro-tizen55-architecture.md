# DansTV Q80T — Tizen 5.5 root integration architecture review
Date: 21 November 2026. Status: **design and offline evidence only**.
Target: Samsung QA65Q80TAWXXY, T-NKMUABC-2743.0, ARMv7, Tizen 5.5.
DansTV branch: `feature/q80t-windows-setup`.

## Reviewed source and scope

- Curtisg890/vetro fork, branch `tizen55-tiz0wn-backend`, commit `8adf2c392a9f22749aa305c7c456501afb8a6ef7`, based on fork `main` plus two commits: [branch](https://github.com/Curtisg890/vetro/tree/tizen55-tiz0wn-backend) / [comparison](https://github.com/Curtisg890/vetro/compare/main...tizen55-tiz0wn-backend).
- Reviewed: `rooting/TIZ0WN-BACKEND.md`, `TIZEN55-STATUS.md`, `service/tiz0wn-platform.js`, `service/root-agent.js`, `payload/tiz0wn-broker.js`, `payload/tiz0wn-agent.js`.
- Curtis's verified hardware is **UE43TU7000KXXU / T-KTSU2DEUC-2743.0**, not the Australian Q80T; their [issue #95](https://github.com/andrearicci93/vetro/issues/95) documents modified Vetro working there. Other Tizen 5.5 firmware must not be assumed equivalent.
- DansTV checked: `app/main.js`, `app/device.js`, `scripts/tiz0wn/{snapshot.sh,root-bridge.py,root-bridge.ps1,assess-snapshot.py}`, existing Q80T handover and compatibility notes.

## Architectural conclusion

**Reuse the security and interface *design*, not the running implementation yet.** DansTV is a static Tizen web-widget UI using public Tizen JavaScript APIs; Curtis's implementation assumes a separate Tizen-side Node service, an **already privileged** root-owned broker, and a provisioned job queue. Dropping his modules into `app/main.js` would not provide those facilities and would be incompatible with a browser-only environment.

| Layer | Current DansTV | Curtis fork | Decision |
| --- | --- | --- | --- |
| UI | Static WGT / `app/main.js`, public `window.tizen` APIs | Dashboard, launcher and service | **Retain DansTV**; do not transplant Vetro UX |
| Ordinary app launch and HDMI | `app/device.js` | Vetro app controls | **Retain existing public API path** and its mock tests |
| Initial privilege | One Q80T UID-0 Remote PC/SMB proof; long snapshot not completed | Expects externally provisioned root | **Independent blocker**, not solved by fork |
| Broker/service boundary | No installed privileged service | Node 4-oriented adapter with private bootstrap, loopback session, HMAC results, sequence numbers | **Reference contract**, not ready-to-install Q80T code |
| Privileged process and shell queue | Not provisioned | Root-owned broker/agent and separately provisioned queue | **Require target-specific ownership, SMACK and startup evidence** |
| Home/remote remap | Guarded research, not deployed | Separate .NET 3.0 launcher on reported TU7000, **not published** in this branch | **Do not borrow foreign model mapping or binary** |
| Cold-boot persistence | Not attempted on Q80T | Intentionally excluded from public fork | **Hard blocked** until independent recovery plan |
| Updater | Normal signed DansTV widget flow | Root-specific Vetro self-updater disabled in tiz0wn mode | **Never auto-upgrade an unverified privileged adapter** |

### Useful concrete design lessons

1. **Keep root acquisition separate from the application.** Initial Remote PC/SMB diagnostics should not be made an install-time prerequisite in the widget.
2. **Authenticate every privileged interaction.** Curtis's code uses a private bootstrap and loopback HMAC authentication; the root broker verifies the expected UID and SMACK label. These must be proven on *this* firmware and against DansTV's signed application identity; copied identity constants are unsafe.
3. **Use explicit state and truthful capability reporting:** `unavailable`, `waiting-for-broker`, `authenticated`, `disconnected` and `error`. Do not mark a root agent connected on the basis of a filename, PID file, socket listener, previous proof or successful report marker.
4. **Define a typed command-result boundary before any code execution:** `exit_code`, `timed_out`, bounded `stdout` and `stderr`; timeouts have an *unknown outcome* and must not trigger blind retries.
5. **Keep privileged operations out of the web UI.** The app should never be able to request arbitrary shell commands through window globals, unauthenticated HTTP, or public local storage. Future privileged features should use deliberately narrow, reviewed capabilities rather than a generic command surface.
6. **Do not equate a Node CLI with a Node web-service runtime.** The fork's Node 4.4.3 evidence is from another model's installed service; the Q80T app/service runtime, package identity and launcher host remain unmeasured.
7. **No implicit boot persistence.** Curtis's source provides neither a safe TV-specific boot hook nor a recovery procedure for our firmware. Raw block patching is out of scope.

### Review cautions in Curtis's source

- The queue bridge depends on a separately installed and correctly permissioned root queue. Its presence and security are not established by the fork package itself.
- The agent's queue and process-spawn fallback are not evidence that either path works on the Q80T; the upstream issue explicitly notes a Node/libuv spawn assertion on the verified TU7000.
- The launcher adaptation, TV-specific remote mapping and signed launcher binary from the owner's installation are **not included**, so Home-button replacement remains separate R&D.
- Source is available under the upstream project's licence; review licence/attribution before any source copying. Prefer independently authored interfaces until compatibility is established.

## Offline implementation gates

A. **Now (no TV required):** preserve the current widget unchanged, review Curtis's protocol and runtime constraints, add conservative compatibility evidence to the read-only snapshot assessor, and run synthetic tests (including incomplete/misleading evidence cases). No package, credential, network or registry mutation.

B. **Next Q80T session:** get the TV's normal RDP/SMB baseline and a complete read-only snapshot; verify the actual runtime and process identity separately. Do not infer a running Node service from the presence of an executable. Re-check credential transport independently before any further long/mixed-character diagnostic.

C. **Only with proved runtime + identity:** design an optional, inert-by-default service adapter, using a single authenticated loopback session and no web-exposed arbitrary command endpoint. Unit-test disconnects, invalid MAC, replays, limits, timeout outcome, and error reporting on synthetic transport before TV deployment.

D. **Only with independent recovery:** inspect exact Home routing, preserve typed original values and an off-TV DB backup, test restore, then evaluate a reversible Home trial. Startup persistence must be a separately reviewed project; never use another model's firmware offsets or a raw-disk boot-script overwrite.

## Current acceptance state

- UID-0 proof: **one earlier Q80T observation**.
- Complete read-only snapshot: **not obtained**.
- Signed Q80T Node runtime/SMACK compatibility: **unknown**.
- Broker provisioning/agent authentication on Q80T: **not done**.
- Q80T native Home and launcher mapping: **not demonstrated**.
- Persistence and recovery: **not demonstrated**.
- TV modifications in this review: **none**.

The next *implementable* milestone is a validated read-only evidence report, not a persistent root installation.
