##############################################################
# Hell Let Loose: Vietnam seeding helper
# Recreated from the EASY HLL seeding workflow, but made
# configurable for HLLV community servers.
##############################################################
param (
    [string]$ConfigPath = "$PSScriptRoot\servers.json",
    [string]$BasePath = $PSScriptRoot,
    [switch]$Once,
    [switch]$DryRun,
    [switch]$Setup
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Start-Transcript -Path "$BasePath\log.txt" -Append | Out-Null

$ClickerSource = @'
using System;
using System.Runtime.InteropServices;

public class HllvClicker
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    const int MOUSEEVENTF_LEFTDOWN = 0x0002;
    const int MOUSEEVENTF_LEFTUP = 0x0004;

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public static void LeftClickAtPoint(int x, int y)
    {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(120);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
        System.Threading.Thread.Sleep(80);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    }
}
'@
Add-Type -TypeDefinition $ClickerSource -ReferencedAssemblies System.Windows.Forms,System.Drawing

function Set-GameForeground {
    param([object]$Config)

    $process = Get-GameProcesses -Config $Config | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (!$process) {
        Write-Log "HLLV window was not found for UI automation."
        return $false
    }

    $activated = $false
    try {
        $shell = New-Object -ComObject WScript.Shell
        $activated = [bool]$shell.AppActivate([int]$process.Id)
    } catch {
        $activated = $false
    }

    [HllvClicker]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
    [HllvClicker]::BringWindowToTop($process.MainWindowHandle) | Out-Null

    # Tapping Alt allows SetForegroundWindow after some foreground-lock scenarios.
    [HllvClicker]::keybd_event(0x12, 0, 0, 0)
    Start-Sleep -Milliseconds 50
    [HllvClicker]::keybd_event(0x12, 0, 2, 0)
    Start-Sleep -Milliseconds 100

    $foreground = [HllvClicker]::SetForegroundWindow($process.MainWindowHandle)
    Start-Sleep -Milliseconds 700
    return ($activated -or $foreground)
}

function Invoke-LeftClick {
    param(
        [int]$X,
        [int]$Y
    )

    [HllvClicker]::LeftClickAtPoint($X, $Y)
}

function Get-GameWindow {
    param([object]$Config)

    Get-GameProcesses -Config $Config |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
}

function Get-GameWindowBounds {
    param([object]$Config)

    $process = Get-GameWindow -Config $Config
    if (!$process) {
        return $null
    }

    $rect = New-Object HllvClicker+RECT
    if (![HllvClicker]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
        return $null
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        return $null
    }

    [pscustomobject]@{
        Left = $rect.Left
        Top = $rect.Top
        Width = $width
        Height = $height
        ProcessId = $process.Id
    }
}

function Convert-UiPointToScreenPoint {
    param(
        [object]$Config,
        [int]$X,
        [int]$Y
    )

    $bounds = Get-GameWindowBounds -Config $Config
    if (!$bounds) {
        return [pscustomobject]@{ X = $X; Y = $Y; AutoDetected = $false }
    }

    $referenceWidth = if ($Config.uiAutomation.referenceWidth) { [double]$Config.uiAutomation.referenceWidth } else { 1920.0 }
    $referenceHeight = if ($Config.uiAutomation.referenceHeight) { [double]$Config.uiAutomation.referenceHeight } else { 1080.0 }

    [pscustomobject]@{
        X = [int][Math]::Round($bounds.Left + ($X / $referenceWidth) * $bounds.Width)
        Y = [int][Math]::Round($bounds.Top + ($Y / $referenceHeight) * $bounds.Height)
        AutoDetected = $true
        Bounds = $bounds
    }
}

function Invoke-GameClick {
    param(
        [object]$Config,
        [int]$X,
        [int]$Y,
        [string]$Name = "UI"
    )

    $point = Convert-UiPointToScreenPoint -Config $Config -X $X -Y $Y
    if ($point.AutoDetected -and $point.Bounds) {
        Write-Log "Auto-detected HLLV display/window $($point.Bounds.Width)x$($point.Bounds.Height) at $($point.Bounds.Left),$($point.Bounds.Top). Clicking $Name at $($point.X),$($point.Y)."
    } else {
        Write-Log "Could not auto-detect HLLV display/window. Clicking $Name at configured screen point $X,$Y."
    }

    Invoke-LeftClick -X $point.X -Y $point.Y
}

$DefaultConfig = [ordered]@{
    steamAppId = 3079210
    playerProfileFile = "player-profile.json"
    playerNameFile = "name.txt"
    seedBelowPlayers = 50
    seededAtPlayers = 70
    maxPlayers = 100
    launchWaitSeconds = 80
    postClickWaitSeconds = 120
    pollSeconds = 60
    reconnectWaitSeconds = 120
    closeGraceSeconds = 30
    uiAutomation = [ordered]@{
        enabled = $true
        referenceWidth = 1920
        referenceHeight = 1080
        focusX = 500
        focusY = 500
        enlistX = 135
        enlistY = 681
        searchX = 1605
        searchY = 150
        joinX = 1295
        joinY = 236
        menuReadyWaitSeconds = 15
        afterFocusClickWaitSeconds = 15
        browserWaitSeconds = 10
        searchWaitSeconds = 8
        joinWaitSeconds = 60
    }
    gameProcessNames = @(
        "HLLVietnam-Win64-Shipping",
        "HLLV-Win64-Shipping",
        "HellLetLooseVietnam-Win64-Shipping",
        "HellLetLooseVietnam",
        "HLL-Win64-Shipping"
    )
    servers = @(
        [ordered]@{
            name = "Example HLLV Community Server"
            easyStatsUrl = "https://stats5.easyhll.com"
            battleMetricsId = ""
            searchText = "Example HLLV Community Server"
            enabled = $false
        }
    )
}

function Write-Log {
    param([string]$Message)
    $time = Get-Date
    Write-Host "[$time] $Message"
}

function Get-ServerNumber {
    param([object]$Server)

    $label = "$($Server.searchText) $($Server.name)"
    if ($label -match "#(\d+)") {
        return $Matches[1]
    }

    return $Server.name
}

function New-DefaultConfig {
    $DefaultConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Host "Created config at $ConfigPath"
    Write-Host "Edit servers.json with EASY stats URLs and server search names, then run again."
}

function Get-Config {
    if (!(Test-Path -Path $ConfigPath)) {
        New-DefaultConfig
        exit 0
    }

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    if (!$config.steamAppId) { $config | Add-Member -NotePropertyName steamAppId -NotePropertyValue 3079210 }
    if (!$config.playerProfileFile) { $config | Add-Member -NotePropertyName playerProfileFile -NotePropertyValue "player-profile.json" }
    if (!$config.gameProcessNames) { $config | Add-Member -NotePropertyName gameProcessNames -NotePropertyValue $DefaultConfig.gameProcessNames }
    if (!$config.servers -or $config.servers.Count -eq 0) {
        throw "No servers are configured. Add at least one server to $ConfigPath."
    }
    return $config
}

function Get-SteamPath {
    $steamProcess = Get-Process "Steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($steamProcess -and $steamProcess.Path -and (Test-Path -Path $steamProcess.Path)) {
        return $steamProcess.Path
    }

    $knownPaths = @(
        "$env:ProgramFiles(x86)\Steam\steam.exe",
        "$env:ProgramFiles\Steam\steam.exe"
    )
    foreach ($knownPath in $knownPaths) {
        if ($knownPath -and (Test-Path -Path $knownPath)) {
            return $knownPath
        }
    }

    throw "Could not find steam.exe. Start Steam once, or install Steam in the default location."
}

function Get-GameProcesses {
    param([object]$Config)
    foreach ($processName in $Config.gameProcessNames) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue
    }
}

function Stop-Game {
    param([object]$Config)

    $processes = @(Get-GameProcesses -Config $Config)
    if ($processes.Count -eq 0) {
        Write-Log "Hell Let Loose: Vietnam is not currently running."
        return
    }

    foreach ($process in $processes) {
        Write-Log "Attempting to close $($process.ProcessName)."
        if (!$DryRun) {
            $process.CloseMainWindow() | Out-Null
        }
    }

    Start-Sleep -Seconds ([int]$Config.closeGraceSeconds)
    $remaining = @(Get-GameProcesses -Config $Config)
    foreach ($process in $remaining) {
        if (!$DryRun) {
            Write-Log "$($process.ProcessName) did not close cleanly. Forcing it closed."
            $process | Stop-Process -Force
        } else {
            Write-Log "$($process.ProcessName) is still running. Dry run will not force it closed."
        }
    }
}

function Invoke-EasyRestMethod {
    param(
        [string]$Uri,
        [int]$Retries = 3,
        [int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri
        } catch {
            if ($attempt -ge $Retries) {
                throw
            }

            Write-Log "Stats API request failed ($attempt/$Retries): $($_.Exception.Message). Retrying in $DelaySeconds seconds."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-PlayerCount {
    param([object]$Server)

    if (![string]::IsNullOrWhiteSpace($Server.easyStatsUrl)) {
        $uri = "$($Server.easyStatsUrl.TrimEnd('/'))/api/get_public_info"
        $json = Invoke-EasyRestMethod -Uri $uri
        return [int]$json.result.player_count
    }

    $uri = "https://api.battlemetrics.com/servers/$($Server.battleMetricsId)"
    $json = Invoke-RestMethod -Uri $uri
    return [int]$json.data.attributes.players
}

function Test-PlayerConnected {
    param(
        [object]$Server,
        [object]$PlayerProfile
    )

    $escapedPlayerName = [Regex]::Escape($PlayerProfile.playerName)

    if (![string]::IsNullOrWhiteSpace($Server.easyStatsUrl)) {
        $uri = "$($Server.easyStatsUrl.TrimEnd('/'))/api/get_live_game_stats"
        $json = Invoke-EasyRestMethod -Uri $uri
        foreach ($player in @($json.result.stats | Where-Object { $_.status -eq "online" })) {
            if ($player.player -match $escapedPlayerName) {
                return $true
            }
        }

        return $false
    }

    $uri = "https://api.battlemetrics.com/servers/$($Server.battleMetricsId)`?include=identifier"
    $response = Invoke-WebRequest -Uri $uri
    return ($response.Content -match $escapedPlayerName)
}

function Start-Server {
    param(
        [object]$Config,
        [object]$Server,
        [string]$SteamPath
    )

    $arguments = "-applaunch $($Config.steamAppId)"
    Write-Log "Launching $($Server.name) with Steam App ID $($Config.steamAppId)."

    if ($DryRun) {
        Write-Host "DRY RUN: Start-Process `"$SteamPath`" -ArgumentList `"$arguments`""
        return
    }

    Start-Process $SteamPath -ArgumentList $arguments
    Start-Sleep -Seconds ([int]$Config.launchWaitSeconds)

    if ($Config.uiAutomation -and $Config.uiAutomation.enabled -ne $false) {
        $searchText = if (![string]::IsNullOrWhiteSpace($Server.searchText)) { $Server.searchText } else { $Server.name }
        Write-Log "Using HLLV server browser UI to join $searchText."

        if ($Config.uiAutomation.menuReadyWaitSeconds) {
            Write-Log "Waiting $($Config.uiAutomation.menuReadyWaitSeconds) seconds for the main menu to become clickable."
            Start-Sleep -Seconds ([int]$Config.uiAutomation.menuReadyWaitSeconds)
        }

        Set-GameForeground -Config $Config | Out-Null
        Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.focusX) -Y ([int]$Config.uiAutomation.focusY) -Name "game focus"
        if ($Config.uiAutomation.afterFocusClickWaitSeconds) {
            Write-Log "Waiting $($Config.uiAutomation.afterFocusClickWaitSeconds) seconds after focusing the game window."
            Start-Sleep -Seconds ([int]$Config.uiAutomation.afterFocusClickWaitSeconds)
        } else {
            Start-Sleep -Milliseconds 500
        }
        Set-GameForeground -Config $Config | Out-Null
        Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.enlistX) -Y ([int]$Config.uiAutomation.enlistY) -Name "Enlist"
        Start-Sleep -Milliseconds 900
        Set-GameForeground -Config $Config | Out-Null
        Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.enlistX) -Y ([int]$Config.uiAutomation.enlistY) -Name "Enlist"
        Start-Sleep -Seconds ([int]$Config.uiAutomation.browserWaitSeconds)

        Set-GameForeground -Config $Config | Out-Null
        Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.searchX) -Y ([int]$Config.uiAutomation.searchY) -Name "server search"
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.Clipboard]::SetText($searchText)
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Seconds ([int]$Config.uiAutomation.searchWaitSeconds)

        $serverNumber = Get-ServerNumber -Server $Server
        Write-Log "Joining server #$serverNumber now."
        Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.joinX) -Y ([int]$Config.uiAutomation.joinY) -Name "Join"
        Start-Sleep -Seconds ([int]$Config.uiAutomation.joinWaitSeconds)
        return
    }

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    Invoke-LeftClick -X ([int]($bounds.Width / 2)) -Y ([int]($bounds.Height / 2))
    Start-Sleep -Seconds ([int]$Config.postClickWaitSeconds)
}

function Read-RequiredValue {
    param([string]$Prompt)

    do {
        $value = (Read-Host -Prompt $Prompt).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "This is required so the script can tell when you are actually in the server."
        }
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value
}

function Get-PlayerProfile {
    param([object]$Config)

    $profilePath = Join-Path $BasePath $Config.playerProfileFile
    if ((Test-Path -Path $profilePath) -and !$Setup) {
        $profile = Get-Content -Path $profilePath -Raw | ConvertFrom-Json
        if (![string]::IsNullOrWhiteSpace($profile.playerName)) {
            return $profile
        }
    }

    $oldNamePath = Join-Path $BasePath $Config.playerNameFile
    if ((Test-Path -Path $oldNamePath) -and !$Setup) {
        $oldPlayerName = (Get-Content -Path $oldNamePath -Raw).Trim()
        if (![string]::IsNullOrWhiteSpace($oldPlayerName)) {
            $profile = [ordered]@{
                playerName = $oldPlayerName
                created = (Get-Date).ToString("s")
            }
            $profile | ConvertTo-Json -Depth 4 | Set-Content -Path $profilePath -Encoding UTF8
            return [pscustomobject]$profile
        }
    }

    Write-Host ""
    Write-Host "First-time EASY HLLV seeding setup"
    Write-Host "This saves your personal player info on this PC only."
    Write-Host ""

    $playerName = Read-RequiredValue -Prompt "Enter your Steam name letter-for-letter exactly as it appears in HLLV stats. Do not include the [EASY] tag"

    $profile = [ordered]@{
        playerName = $playerName
        created = (Get-Date).ToString("s")
    }
    $profile | ConvertTo-Json -Depth 4 | Set-Content -Path $profilePath -Encoding UTF8

    Write-Host ""
    Write-Host "Saved personal setup to $profilePath"
    Write-Host "Run with -Setup later if you need to change it."
    return [pscustomobject]$profile
}

$config = Get-Config
$enabledServers = @($config.servers | Where-Object { $_.enabled -ne $false })
if ($enabledServers.Count -eq 0) {
    Write-Host "No servers are enabled in $ConfigPath."
    Write-Host "Set enabled to true for at least one configured server."
    Stop-Transcript | Out-Null
    exit 0
}

$configuredServers = @($enabledServers | Where-Object {
    (
        (![string]::IsNullOrWhiteSpace($_.easyStatsUrl) -and $_.easyStatsUrl -notmatch "^REPLACE_WITH_") -or
        (![string]::IsNullOrWhiteSpace($_.battleMetricsId) -and $_.battleMetricsId -notmatch "^REPLACE_WITH_")
    )
})
if ($configuredServers.Count -eq 0) {
    Write-Host "Enabled servers still have placeholder values in $ConfigPath."
    Write-Host "Replace easyStatsUrl or battleMetricsId before running the seeding loop."
    Stop-Transcript | Out-Null
    exit 0
}

$steamPath = if ($DryRun) { "steam.exe" } else { Get-SteamPath }
$playerProfile = Get-PlayerProfile -Config $config
$steamName = $playerProfile.playerName

Write-Host ""
Write-Host "Hell Let Loose: Vietnam seeding helper"
Write-Host "Player: $steamName"
Write-Host "Config: $ConfigPath"
Write-Host ""

do {
    Stop-Game -Config $config

    $serverStatuses = @()
    for ($index = 0; $index -lt $configuredServers.Count; $index++) {
        $server = $configuredServers[$index]
        $serverNumber = Get-ServerNumber -Server $server

        try {
            $players = Get-PlayerCount -Server $server
        } catch {
            Write-Log "Could not read population for server #$serverNumber ($($server.name)): $($_.Exception.Message)"
            continue
        }

        $isBeingSeeded = $players -lt [int]$config.seedBelowPlayers
        if ($isBeingSeeded) {
            Write-Log "Server #$serverNumber is $players/$($config.maxPlayers) - being seeded."
        } else {
            Write-Log "Server #$serverNumber is $players/$($config.maxPlayers) - not seeding right now."
        }

        $serverStatuses += [pscustomobject]@{
            Server = $server
            ServerNumber = $serverNumber
            Players = $players
            Order = $index
            IsBeingSeeded = $isBeingSeeded
        }
    }

    $targetStatus = @($serverStatuses |
        Where-Object { $_.IsBeingSeeded } |
        Sort-Object @{ Expression = "Players"; Descending = $true }, @{ Expression = "Order"; Descending = $false } |
        Select-Object -First 1)

    if ($targetStatus.Count -eq 0) {
        Write-Log "No EASY HLLV servers are under $($config.seedBelowPlayers) players. Checking again in $($config.pollSeconds) seconds."
        if ($Once) { break }
        Start-Sleep -Seconds ([int]$config.pollSeconds)
        continue
    }

    $server = $targetStatus[0].Server
    Write-Log "Best seeding target is server #$($targetStatus[0].ServerNumber) at $($targetStatus[0].Players)/$($config.maxPlayers). Connecting now."
    Start-Server -Config $config -Server $server -SteamPath $steamPath

    $players = [int]$targetStatus[0].Players
    $restartScan = $false
    do {
        Start-Sleep -Seconds ([int]$config.pollSeconds)
        try {
            $players = Get-PlayerCount -Server $server
            $connected = Test-PlayerConnected -Server $server -PlayerProfile $playerProfile
        } catch {
            Write-Log "Could not check EASY stats for $($server.name): $($_.Exception.Message). Staying connected and trying again next check."
            continue
        }

        if (!$connected) {
            Write-Log "$steamName is not detected on $($server.name). Closing HLLV and checking all servers again."
            Stop-Game -Config $config
            $restartScan = $true
            break
        } else {
            $serverNumber = Get-ServerNumber -Server $server
            Write-Log "You are seeding server #$serverNumber. Population is $players/$($config.maxPlayers)."
        }
    } until ($restartScan -or $players -gt [int]$config.seededAtPlayers)

    if ($restartScan) {
        continue
    }

    Write-Log "$($server.name) reached $players/$($config.maxPlayers). Closing game and checking all servers again."
    Stop-Game -Config $config
} while (!$Once)

Stop-Transcript | Out-Null
