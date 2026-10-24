# EASY Seeding Helper v3.0.1

## First-Time Setup

1. Double-click `SeedHLLVServers.bat`.
2. Enter your Steam name letter-for-letter exactly as it appears in EASY stats.
3. Leave the Desktop shortcut option checked.
4. Click **Get Started**.

## Start Seeding

1. Open **EASY Seeding Helper** from your Desktop.
2. Check the games you want to seed: **WARDOGS**, **HLLV**, and/or **HLL WW2**.
3. Click **Start Seeding**.
4. Leave the helper open while it checks and seeds EASY servers.
5. Click **Stop** when you are finished. The current game will remain open.

## Steam Name

- Your Steam name must match what EASY stats shows 100%.
- Capital letters, spaces, punctuation, and numbers matter.
- Use the **Edit** button before starting if you need to change it.

## What The Helper Shows

- Current player counts for EASY WARDOGS East, West, and Comp, five HLLV servers, and the EASY HLL WW2 server.
- Live server counts that continue refreshing once per minute while seeding is stopped.
- Which servers are under 50 players or already actively seeding.
- The game and server the helper is joining or seeding.
- A countdown until the next server check.
- Recent activity and errors.

## Important

- Do not click around while the helper is opening a game and joining a server.
- Keep Steam signed in.
- When multiple games are checked, the order is **WARDOGS -> HLLV -> HLL WW2**.
- WARDOGS checks East, then West. Comp / NA CENTRAL is optional and comes after West.
- HLLV servers are checked in #1 through #5 order. The first available enabled server below 50 players is selected.
- Every check starts at the top of the priority order. If a higher-priority server needs seeding again, the helper switches back to it.
- The helper stops seeding each server when it reaches 50 players.
- A server whose stats page is down is marked **DOWN**, skipped, and checked again during the next one-minute scan.
- If a game fails to open, join, or confirm your connection, that server is skipped for the current scan and the helper continues by priority.
- If you are kicked or disconnected, the helper starts a fresh priority scan.

## WARDOGS

- Keep WARDOGS in the foreground while seeding. Activity clicks pause when another app is in front or WARDOGS is minimized.
- The helper joins by server ID, quickly clicks all three faction choices, and confirms the match screen before clicking every five seconds.
- WARDOGS has no player roster available to the helper. An unrecognized screen is shown as unverified and does not close the game. Activity clicks pause until the match screen is recognized again.
- Use the game's English interface and have Windows English OCR support installed.
- To seed the competition server, open **Settings** and check **Include WARDOGS Comp / NA CENTRAL** while the seeder is stopped.
- Counts come from the [Wardog Servers community API](https://wardogservers.com/devs), which can be a few minutes behind the game. Unavailable or stale data is skipped.
- Click **Stop** before playing normally to stop the helper's activity clicks.

## Timing Settings

The recommended settings work for most PCs. Only change them when a game or server browser loads too slowly.

1. Open the **Settings** page.
2. Select the **WARDOGS**, **HLLV**, or **HLL WW2** tab.
3. Increase the timing value for the step that runs too early.
4. Click **Save Settings** before returning to the seeder.

Timing settings can only be changed while the seeder is stopped. Use **Recommended** to restore the recommended timing values for all games.

## Desktop Shortcut

Open **Settings** and click **Create Shortcut** or **Recreate Shortcut** whenever you need to restore the Desktop shortcut.

## Need Help?

Click **Open Log** and send `log.txt` to whoever is helping you troubleshoot.
The helper automatically keeps only the most recent 24 hours in `log.txt`.
