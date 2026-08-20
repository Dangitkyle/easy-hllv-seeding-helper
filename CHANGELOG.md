# Changelog

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
