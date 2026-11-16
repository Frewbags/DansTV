# DansTV Q80T default Home apps

Default Dock order (16 items; 16 maximum):

1. Live TV (Samsung TV viewer)
2. Netflix
3. Prime Video
4. YouTube
5. Jellyfin
6. Kayo
7. ABC iview
8. SBS On Demand
9. 7plus
10. 9Now
11. 10 (10 Play, subject to app branding on the device)
12. Apple TV
13. Apple Music
14. Nintendo Switch (HDMI port configured in DansTV Settings)
15. Nintendo Switch 2 (HDMI port configured in DansTV Settings)
16. PlayStation 4 (HDMI port configured in DansTV Settings)
14. Nintendo Switch
15. Nintendo Switch 2
16. PlayStation 4

Disney+ and Stremio are **not** part of the new default Home; they can still be added from installed apps. Only the stock nine-item upstream default is migrated automatically; user-customised Home layouts are preserved.

Live TV opens `org.tizen.tv-viewer` and does **not** tune a particular broadcast channel. Verify it on the Q80T before claiming terrestrial-TV support. Individual free-to-air channel tuning is deferred pending model-specific API checks.

Jellyfin, Kayo, 7plus, 9Now and 10 are resolved from the installed Tizen application list. A matching name or a documented historical app ID helps discover them; there is no blind launch against an assumed ID. If absent or ambiguous, a visible error is returned. Internet streaming apps still make their own network requests; the launcher does not disable Samsung firmware telemetry.

To see these defaults on an existing preview with a deliberately customised Home layout, use the app editor. Do not blindly clear all site data, because that also discards saved preferences. A previously saved unmodified stock default will migrate automatically. After updating the branch, restart the preview process and refresh the page.

Remote OK/Back and focus navigation are left intact. Source selection and TV installation remain separately verified steps.

## Six-wide dock and branded icons

The dock shows **six complete app tiles** simultaneously at 1920×1080, scaled uniformly at 1280×720. The remaining apps are reached by left/right remote navigation, scrolling by whole tiles rather than partially faded neighbours. The capacity is now 16, with the three console shortcuts appended to the existing 13-app order.

The existing streaming marks remain local SVG silhouettes. New bundled Jellyfin, Kayo, 7plus, 9Now and historical 10 Play marks are credited in `app/assets/icons/ADDITIONAL-SOURCES.json`. The Australian community-source marks are **CC BY-NC-SA 4.0**, separately licensed from the MIT code; see the icon licence file and THIRD_PARTY_NOTICES.md. The 10 Play historical fallback may differ from the current 10 app branding. If Tizen supplies an installed app's `iconPath` after discovery, DansTV prefers that authentic installed icon instead. Live TV uses an original generic pictogram, not Samsung artwork. No network request is made to fetch icons during runtime.

## Configurable console inputs

In **Settings → Consoles**, choose Nintendo Switch, Nintendo Switch 2 or PlayStation 4 and assign an input manually (HDMI 1–4); **Unassigned** removes a mapping without removing the icon. The assignments are saved in `consolePorts` within the existing TV-local preferences and survive restarts. No TV IP, DUID or signing certificate is stored in these mappings.

The console tiles use locally bundled, individually attributed logo silhouettes. Clicking an unassigned shortcut displays a clear message instead of guessing a port. The selected HDMI port is passed to Tizen's TV window source API; when device discovery is missing or denies access, a manually configured numeric HDMI source is attempted. This fallback may not be supported by every Q80T firmware; users can still select an input using the TV remote. It does not control which console is selected by an external HDMI switch.

## Console HDMI shortcut setup

Go to **Settings → Consoles**, select **Nintendo Switch**, **Nintendo Switch 2**, or **PlayStation 4**, then select **HDMI 1–4** or **Unassigned**. The assignment is saved in local Tizen web-app storage and survives an ordinary application restart. Console shortcuts use a locally bundled logo, even when Samsung does not identify the connected hardware. Device auto-detection may identify active HDMI ports, but cannot be relied on to distinguish two consoles on an external HDMI switch. The first console launch is never attempted without a saved port mapping. Manual mapping can ask Tizen to switch even if VIDEOSOURCE enumeration fails; an unsupported or blocked TV input results in an error, not silent success.

The three console logos are derived from attributed Sentry Platformicons (Nintendo Switch/Switch 2) and Simple Icons (PlayStation 4), with source locations and licences in `app/assets/icons/ADDITIONAL-SOURCES.json` and `THIRD_PARTY_NOTICES.md`. Logo names and shapes remain third-party trademarks.
