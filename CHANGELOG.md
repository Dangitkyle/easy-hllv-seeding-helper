# Changelog

## v3.0.0

- Adds WARDOGS seeding for EASY NA EAST and NA WEST, with optional Comp / NA CENTRAL.
- Seeds selected games in WARDOGS, HLLV, then HLL WW2 priority order.
- Uses the Wardog Servers community API for player counts and stable server IDs for joining.
- Confirms the server lookup, quickly clicks all three faction choices, and recognizes the joined match screen.
- Clicks every five seconds after joining a team, pausing when WARDOGS is not in the foreground or the match screen is not confirmed.
- Adds WARDOGS game selection, timing settings, Comp selection, and live server rows.
- Handles the graphics-driver notice and OCR reading JOIN BY ID as JOIN BY IO.
- Corrects the expanded dashboard layout and preserves the 50-player threshold and 24-hour log retention.

## v2.3.5

- Fixes Enlist, search, and Join click positions on ultrawide and non-16:9 displays.
- Uses the game client area instead of the outer window frame when calculating clicks.
- Preserves and centers the 1920x1080 game UI viewport instead of stretching it across the full window.

## v2.3.4

- Adds the native Windows seeding dashboard, first-run setup, Desktop shortcut creation, live server data, and timing settings.
- Adds optional HLL WW2 seeding while keeping HLLV as the first priority.
- Checks HLLV servers strictly in #1 through #5 order and returns to the highest-priority eligible HLLV server on each scan.
- Marks unavailable stats servers DOWN, skips them safely, and checks them again once per minute without retrying HTTP 5xx errors.
- Falls through after launch, join, or player-confirmation failures without producing an invalid Steam launch.
- Stops seeding at 50 players and retains only the latest 24 hours in `log.txt`.
- Adds the EASY Seeding Helper application icon and modern desktop UI.

## v1.1.1

- Fixes stale dashboard server counts while actively seeding.
- Refreshes all server rows before each countdown and each seeding status check.
- Fixes the dashboard version label.

## v1.1.0

- Adds a clean live status dashboard in the PowerShell window.
- Adds countdown display for the next server check.
- Keeps detailed troubleshooting history in `log.txt`.

## v1.0.2

- Checks all servers under 50 players.
- Prioritizes active seeds with more than 3 players.
- Uses #1 to #4 server order when no active seed has more than 3 players.

## v1.0.1

- Finds Steam from Windows registry entries, not only the default install folder.
- Falls back to Steam URL launching if `steam.exe` cannot be found directly.
- Adds a user-facing note to open Steam once if HLLV does not launch.

## v1.0.0

- Initial public EASY HLLV seeding helper release.
- Checks EASY HLLV servers once per minute.
- Joins the best EASY server under 50 players.
- Stops seeding a server once it reaches 50 players.
- Rechecks all servers if the player is kicked or disconnected.
- Retries temporary EASY stats errors instead of stopping.
- Uses Steam name only; SteamID is not collected.
- Server IPs are not included.
