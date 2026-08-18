# EASY HLLV Seeding Helper v1.0.0

## How To Use

1. Extract the ZIP folder somewhere easy to find.
2. Open the extracted folder.
3. Double-click `SeedHLLVServers.bat`.
4. The first time it runs, type your Steam name letter-for-letter.
5. Keep the seeder window open.
6. Let the script open Hell Let Loose: Vietnam and join a server for you.

## What It Does

- Checks EASY HLLV servers once per minute.
- Joins the best EASY server under 50 players.
- Stops seeding that server after it reaches 50 players.
- If you get kicked or disconnected, it closes HLLV and checks all servers again.
- If EASY stats has a temporary error, it waits and tries again.

## Important

- Your Steam name must match what HLLV/EASY stats shows 100%.
- Do not include the `[EASY]` tag, even if it appears beside your name in-game or in stats.
- Capital letters, spaces, punctuation, and numbers matter.
- Do not click around while the script is opening HLLV and joining a server.
- Do not close the seeder window unless you want the seeder to stop.
- `player-profile.json` and `log.txt` are created for you after running. You do not need to edit them.

## Change Your Player Name

If you typed your name wrong, open PowerShell in this folder and run:

```powershell
Powershell.exe -STA -ExecutionPolicy Bypass -File ".\HLLVSeeding.ps1" -Setup
```

Then enter your correct Steam name letter-for-letter. Do not include the `[EASY]` tag.

## Need Help?

Send `log.txt` to whoever is helping you troubleshoot.
