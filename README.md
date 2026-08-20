# EASY HLLV Seeding Helper v1.1.1

## How To Use

1. Extract the ZIP folder somewhere easy to find.
2. Open the extracted folder.
3. Double-click `SeedHLLVServers.bat`.
4. The first time it runs, type your Steam name letter-for-letter.
5. Keep the seeder window open.
6. Let the script open Hell Let Loose: Vietnam and join a server for you.

## What It Does

- Checks EASY HLLV servers once per minute.
- Checks servers in #1 to #4 order.
- Joins an active seed first if a server under 50 already has more than 3 players.
- If no server has more than 3 players, joins the first server under 50 in #1 to #4 order.
- Stops seeding that server after it reaches 50 players.
- If you get kicked or disconnected, it closes HLLV and checks all servers again.
- If EASY stats has a temporary error, it waits and tries again.

## Important

- Your Steam name must match what HLLV/EASY stats shows 100%.
- Capital letters, spaces, punctuation, and numbers matter.
- Do not click around while the script is opening HLLV and joining a server.
- Do not close the seeder window unless you want the seeder to stop.
- `player-profile.json` and `log.txt` are created for you after running. You do not need to edit them.

## Change Your Player Name

If you typed your name wrong, open PowerShell in this folder and run:

```powershell
Powershell.exe -STA -ExecutionPolicy Bypass -File ".\HLLVSeeding.ps1" -Setup
```

Then enter your correct Steam name letter-for-letter.

## Need Help?

Send `log.txt` to whoever is helping you troubleshoot.

If the seeder cannot open HLLV, open Steam once, then run `SeedHLLVServers.bat` again.
