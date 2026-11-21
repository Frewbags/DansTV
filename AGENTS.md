# CleanFrame

`app/` is the current packaged UI. Read `docs/development.md` and `docs/interaction-behaviour.md` before app changes. For a new contributor or a separate TV installation, also read `docs/for-agents.md`.

Use simple HTML, CSS and ES5-compatible JavaScript for the TV. Node tooling can use modern JavaScript. Preserve remote focus/navigation, preference migrations and cached rendering. Read `docs/assets.md` before changing images, glass geometry or icon sizing; keep live blur and pixel analysis off the TV animation path.

Run `npm run check` for app changes and `npm run check:tools` for signing or validation-tool changes. For interaction changes, run the browser preview and `CLEANFRAME_PUBLIC_FONTS=1 npm run check:browser`; public contributors must not need proprietary fonts. Run `npm run check:public` and `npm run export:public` before preparing a public download. Follow `CONTRIBUTING.md` and retain third-party notices.

Browser/repository tasks do not authorise device access. Read `docs/tv-status.md` before compatibility claims and `docs/agent-tv-setup-guide.md` before a new TV setup. An explicit device task is required even for queries that stage a helper. Announce any installation, app launch or restart; confirm visible results with the owner. Treat native Home/startup writes as a separate task with explicit authority and an exact-value recovery baseline.

On the maintainer's TV, preserve the stable package/application identity, author certificate and existing native Home assignment. For an independent user's signed build, create their own SDK-generated identity and certificates, then select them in ignored `.local/signing.json` using `signing.example.json`; read the signing section in `docs/development.md`. The generated manifest and install/launch tools use that identity; the runtime reads its own ID. Keep the source identity guards intact. Native Home targets and firmware guards need separate review and authority. The TV tools and native helper retain reference-machine assumptions; they are not an unattended installer.

Keep proprietary fonts, signing keys, passwords, device identifiers, addresses, SDKs, recovery values and generated packages in ignored `.local/` or `dist/`. Never commit paid font binaries or publish a private-font widget. Public-code licensing does not replace the terms in `THIRD_PARTY_NOTICES.md`.

On Nathan's Mac, use `/Users/nathan/.local/bin/gh-for-repo` for GitHub CLI work. On another machine, use the contributor's own authenticated GitHub account. Preserve shared or uncommitted work. Use reversible deletion; never reset, force-push or rewrite history without explicit authority. Publication/visibility changes require a separate instruction.

## Owner's Australian Q80T / DansTV workstream

This is separate from the reference Frame native-Home procedures above.
For the **QA65Q80TAWXXY / T-NKMUABC-2743.0** branch work, read
[`docs/q80t-root-handover.md`](docs/q80t-root-handover.md),
[`docs/q80t-nov21-snapshot-success.md`](docs/q80t-nov21-snapshot-success.md)
and [`docs/q80t-finish-checklist.md`](docs/q80t-finish-checklist.md)
before suggesting any device action.

**21 Nov 2026 milestone:** the owner successfully obtained **one**
checksum-gated, framed, read-only UID-0 report using
`root-bridge.ps1 -Action PrepareStaged` followed by `-Action ListenStaged`,
with SDB **push** of two files, one Remote PC/Shared Folder action,
`STAGE-HASH-VERIFIED`, `SNAPSHOT-RECEIVED`, a successful local assessor,
and automatic restoration of dedicated host/XRDP credentials.
**SDB pull was rejected on the TV and is not used in the working method.**
The full report is **private under ignored `.local/tiz0wn-lab/`**;
do not commit, share or print it or token-bearing paths.
Do not rerun the trial just to analyse the saved snapshot.

The older long-password `-Action Prepare` and separate
`staged-snapshot.ps1` prototype are not the successful procedure.
Evidence of Node in the shell PATH or a reported Home preference
**does not** establish a native Home mapping, web-service runtime,
authenticated broker, persistence, or independent recovery.
No Home/startup/firmware write is approved. Obtain independently
verified off-TV Home DB backups, exact original values, native
main-operation evidence and an independent restore route before
even a reversible Home trial. TV-saved Remote PC credentials
may need updating after host Restore.
