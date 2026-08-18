# Changelog

## v1.0.0

- Initial public EASY HLLV seeding helper release.
- Checks EASY HLLV servers once per minute.
- Joins the best EASY server under 50 players.
- Stops seeding a server once it reaches 50 players.
- Rechecks all servers if the player is kicked or disconnected.
- Retries temporary EASY stats errors instead of stopping.
- Uses Steam name only; SteamID is not collected.
- Server IPs are not included.
