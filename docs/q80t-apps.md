# DansTV Q80T default Home apps

Default Dock order (13 items; 14 maximum):

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

Disney+ and Stremio are **not** part of the new default Home; they can still be added from installed apps. Only the stock nine-item upstream default is migrated automatically; user-customised Home layouts are preserved.

Live TV opens `org.tizen.tv-viewer` and does **not** tune a particular broadcast channel. Verify it on the Q80T before claiming terrestrial-TV support. Individual free-to-air channel tuning is deferred pending model-specific API checks.

Jellyfin, Kayo, 7plus, 9Now and 10 are resolved from the installed Tizen application list. A matching name or a documented historical app ID helps discover them; there is no blind launch against an assumed ID. If absent or ambiguous, a visible error is returned. Internet streaming apps still make their own network requests; the launcher does not disable Samsung firmware telemetry.

To see these defaults on an existing preview with a deliberately customised Home layout, use the app editor. Do not blindly clear all site data, because that also discards saved preferences. A previously saved unmodified stock default will migrate automatically. After updating the branch, restart the preview process and refresh the page.

Remote OK/Back and focus navigation are left intact. Source selection and TV installation remain separately verified steps.
