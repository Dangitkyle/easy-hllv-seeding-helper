##############################################################
# EASY Hell Let Loose seeding helper
# Seeds HLLV first, then HLL WW2 when its HLLV work is complete.
##############################################################
param (
    [string]$ConfigPath = "$PSScriptRoot\servers.json",
    [string]$BasePath = $PSScriptRoot,
    [switch]$Once,
    [switch]$DryRun,
    [switch]$Setup,
    [switch]$UiMode
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:StatusFilePath = Join-Path $BasePath "seeder-status.json"
$script:LogPath = Join-Path $BasePath "log.txt"
$script:LogRetentionHours = 24
$script:NextLogRetentionAt = Get-Date
$script:TranscriptRunning = $false
$script:StatusPlayerName = ""
$script:StatusServerStatuses = @()
$script:StatusMessage = "Starting seeder..."
$script:StatusNextCheckSeconds = -1
$script:LastLogMessage = "Starting seeder..."
$script:RecentStatusEvents = @()

function Write-JsonFileSafely {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 12,
        [int]$Attempts = 5
    )

    $directory = Split-Path -Parent $Path
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporaryPath = Join-Path $directory (".{0}.{1}.tmp" -f $fileName, [Guid]::NewGuid().ToString("N"))
    $backupPath = Join-Path $directory (".{0}.{1}.bak" -f $fileName, [Guid]::NewGuid().ToString("N"))
    $lastError = $null

    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))

        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                if ([System.IO.File]::Exists($Path)) {
                    [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
                } else {
                    [System.IO.File]::Move($temporaryPath, $Path)
                }
                return
            } catch {
                $lastError = $_.Exception
                if ($attempt -lt $Attempts) {
                    Start-Sleep -Milliseconds (100 * $attempt)
                }
            }
        }

        throw $lastError
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) {
            try { [System.IO.File]::Delete($temporaryPath) } catch { }
        }
        if ([System.IO.File]::Exists($backupPath)) {
            try { [System.IO.File]::Delete($backupPath) } catch { }
        }
    }
}

function Write-LogLinesSafely {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [int]$Attempts = 5
    )

    $directory = Split-Path -Parent $Path
    $fileName = [System.IO.Path]::GetFileName($Path)
    $temporaryPath = Join-Path $directory (".{0}.{1}.tmp" -f $fileName, [Guid]::NewGuid().ToString("N"))
    $backupPath = Join-Path $directory (".{0}.{1}.bak" -f $fileName, [Guid]::NewGuid().ToString("N"))
    $lastError = $null

    try {
        [System.IO.File]::WriteAllLines($temporaryPath, $Lines, [System.Text.UTF8Encoding]::new($false))
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                if ([System.IO.File]::Exists($Path)) {
                    [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
                } else {
                    [System.IO.File]::Move($temporaryPath, $Path)
                }
                return
            } catch {
                $lastError = $_.Exception
                if ($attempt -lt $Attempts) {
                    Start-Sleep -Milliseconds (100 * $attempt)
                }
            }
        }
        throw $lastError
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) {
            try { [System.IO.File]::Delete($temporaryPath) } catch { }
        }
        if ([System.IO.File]::Exists($backupPath)) {
            try { [System.IO.File]::Delete($backupPath) } catch { }
        }
    }
}

function Start-SeederTranscript {
    try {
        Start-Transcript -Path $script:LogPath -Append -ErrorAction Stop | Out-Null
        $script:TranscriptRunning = $true
    } catch {
        $script:TranscriptRunning = $false
    }
}

function Stop-SeederTranscript {
    if (!$script:TranscriptRunning) {
        return
    }

    try { Stop-Transcript -ErrorAction Stop | Out-Null } catch { }
    $script:TranscriptRunning = $false
}

function Invoke-LogRetention {
    param([switch]$Force)

    $now = Get-Date
    if (!$Force -and $now -lt $script:NextLogRetentionAt) {
        return
    }
    $script:NextLogRetentionAt = $now.AddHours(1)

    $resumeTranscript = $script:TranscriptRunning
    if ($resumeTranscript) {
        Stop-SeederTranscript
    }

    try {
        if (![System.IO.File]::Exists($script:LogPath)) {
            return
        }

        $cutoff = $now.AddHours(-1 * $script:LogRetentionHours)
        $lines = [System.IO.File]::ReadAllLines($script:LogPath)
        $keepFromIndex = -1

        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            $entryTime = [DateTime]::MinValue

            if ($line -match '^Start time: (?<stamp>\d{14})$') {
                $hasEntryTime = [DateTime]::TryParseExact(
                    $Matches.stamp,
                    'yyyyMMddHHmmss',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeLocal,
                    [ref]$entryTime
                )
                if ($hasEntryTime -and $entryTime -ge $cutoff) {
                    $keepFromIndex = [Math]::Max(0, $index - 2)
                    break
                }
            } elseif ($line -match '^\[(?<stamp>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2})\]') {
                $hasEntryTime = [DateTime]::TryParseExact(
                    $Matches.stamp,
                    'MM/dd/yyyy HH:mm:ss',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeLocal,
                    [ref]$entryTime
                )
                if ($hasEntryTime -and $entryTime -ge $cutoff) {
                    $keepFromIndex = $index
                    break
                }
            }
        }

        if ($keepFromIndex -ge 0) {
            $retainedLines = if ($keepFromIndex -eq 0) { $lines } else { @($lines[$keepFromIndex..($lines.Count - 1)]) }
            Write-LogLinesSafely -Path $script:LogPath -Lines $retainedLines
        } elseif ([System.IO.File]::GetLastWriteTime($script:LogPath) -lt $cutoff) {
            Write-LogLinesSafely -Path $script:LogPath -Lines @()
        }
    } catch {
        # Log cleanup must never interrupt seeding.
    } finally {
        if ($resumeTranscript) {
            Start-SeederTranscript
        }
    }
}

Invoke-LogRetention -Force
Start-SeederTranscript

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
        Write-Log "$($Config.displayName) window was not found for UI automation."
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
        Write-Log "Auto-detected $($Config.displayName) display/window $($point.Bounds.Width)x$($point.Bounds.Height) at $($point.Bounds.Left),$($point.Bounds.Top). Clicking $Name at $($point.X),$($point.Y)."
    } else {
        Write-Log "Could not auto-detect $($Config.displayName) display/window. Clicking $Name at configured screen point $X,$Y."
    }

    Invoke-LeftClick -X $point.X -Y $point.Y
}

$DefaultConfig = [ordered]@{
    version = "2.3.4"
    enabledGames = [ordered]@{ hllv = $true; hllWw2 = $true }
    steamAppId = 3079210
    playerProfileFile = "player-profile.json"
    playerNameFile = "name.txt"
    seedBelowPlayers = 50
    activeSeedPlayers = 3
    seededAtPlayers = 50
    maxPlayers = 100
    launchWaitSeconds = 80
    postClickWaitSeconds = 120
    pollSeconds = 60
    reconnectWaitSeconds = 120
    connectionMissesBeforeRestart = 3
    closeGraceSeconds = 30
    uiAutomation = [ordered]@{
        enabled = $true
        referenceWidth = 1920
        referenceHeight = 1080
        focusX = 500
        focusY = 500
        enlistX = 135
        enlistY = 681
        enlistClickCount = 2
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
        "HellLetLooseVietnam"
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

$DefaultWw2Config = [ordered]@{
    displayName = "HLL WW2"
    steamAppId = 686810
    seedBelowPlayers = 50
    activeSeedPlayers = 3
    seededAtPlayers = 50
    maxPlayers = 100
    launchWaitSeconds = 45
    postClickWaitSeconds = 60
    pollSeconds = 60
    reconnectWaitSeconds = 60
    connectionMissesBeforeRestart = 3
    closeGraceSeconds = 30
    uiAutomation = [ordered]@{
        enabled = $true
        referenceWidth = 1920
        referenceHeight = 1080
        focusX = 500
        focusY = 500
        enlistX = 120
        enlistY = 580
        enlistClickCount = 1
        searchX = 1000
        searchY = 199
        joinX = 1480
        joinY = 390
        menuReadyWaitSeconds = 10
        afterFocusClickWaitSeconds = 15
        browserWaitSeconds = 10
        searchWaitSeconds = 8
        joinWaitSeconds = 45
    }
    gameProcessNames = @("HLL-Win64-Shipping", "Launch_HLL")
    servers = @(
        [ordered]@{
            number = "WW2"
            name = "EASY Company | New Players Welcome | DISCORD.GG/EASYCOMPANY | QONZER"
            easyStatsUrl = "https://stats6.easyhll.com"
            battleMetricsId = ""
            searchText = "EASY Company | New Players Welcome"
            enabled = $true
        }
    )
}

function Publish-SeederStatus {
    param([bool]$Running = $true)

    $serverRows = @()
    foreach ($status in @($script:StatusServerStatuses)) {
        if (!$status) {
            continue
        }

        $state = if (!$status.GameEnabled) {
            "DISABLED"
        } elseif ($status.IsAvailable -eq $false) {
            "DOWN"
        } elseif ($status.IsActiveSeed) {
            "ACTIVE SEED"
        } elseif ($status.IsUnderSeedThreshold) {
            "UNDER 50"
        } else {
            "NOT SEEDING"
        }

        $serverRows += [ordered]@{
            key = "$($status.GameId):$($status.ServerNumber)"
            gameId = "$($status.GameId)"
            gameName = "$($status.GameName)"
            number = "$($status.ServerNumber)"
            players = if ($status.IsAvailable -eq $false) { -1 } else { [int]$status.Players }
            maxPlayers = [int]$status.MaxPlayers
            state = $state
        }
    }

    $payload = [ordered]@{
        version = "2.3.4"
        running = $Running
        playerName = $script:StatusPlayerName
        message = $script:StatusMessage
        lastLog = $script:LastLogMessage
        nextCheckSeconds = $script:StatusNextCheckSeconds
        updatedAt = (Get-Date).ToString("o")
        servers = $serverRows
        events = @($script:RecentStatusEvents)
    }

    try {
        Write-JsonFileSafely -Value $payload -Path $script:StatusFilePath -Depth 6
    } catch {
        # A status-file failure must never interrupt the seeding loop.
    }
}

function Write-Log {
    param([string]$Message)
    Invoke-LogRetention
    $time = Get-Date
    $script:LastLogMessage = $Message
    $script:StatusMessage = $Message
    $script:RecentStatusEvents += [ordered]@{
        timestamp = $time.ToString("o")
        message = $Message
    }
    if ($script:RecentStatusEvents.Count -gt 40) {
        $script:RecentStatusEvents = @($script:RecentStatusEvents | Select-Object -Last 40)
    }
    Publish-SeederStatus
    Write-Host "[$time] $Message"
}

function Format-ServerStatusLine {
    param([object]$Status)

    if (!$Status) {
        return ""
    }

    $statusText = if (!$Status.GameEnabled) {
        "DISABLED"
    } elseif ($Status.IsAvailable -eq $false) {
        "DOWN"
    } elseif ($Status.IsActiveSeed) {
        "ACTIVE SEED"
    } elseif ($Status.IsUnderSeedThreshold) {
        "UNDER 50"
    } else {
        "NOT SEEDING"
    }

    $populationText = if ($Status.IsAvailable -eq $false) { "--/$($Status.MaxPlayers)" } else { "$($Status.Players)/$($Status.MaxPlayers)" }
    "$($Status.GameName) $($Status.ServerNumber): $populationText - $statusText"
}

function Show-SeedingDashboard {
    param(
        [string]$PlayerName,
        [object[]]$ServerStatuses = @(),
        [string]$Message = "Checking servers...",
        [int]$NextCheckSeconds = -1
    )

    $script:StatusPlayerName = $PlayerName
    $script:StatusServerStatuses = @($ServerStatuses)
    $script:StatusMessage = $Message
    $script:StatusNextCheckSeconds = $NextCheckSeconds
    Publish-SeederStatus

    if ($UiMode) {
        return
    }

    Clear-Host
    Write-Host "EASY Seeding Helper v2.3.4"
    Write-Host ""
    Write-Host "Player: $PlayerName"
    Write-Host "Status: $Message"
    Write-Host ""

    if ($ServerStatuses.Count -gt 0) {
        foreach ($status in ($ServerStatuses | Sort-Object @{ Expression = "GamePriority"; Descending = $false }, @{ Expression = "Order"; Descending = $false })) {
            Write-Host (Format-ServerStatusLine -Status $status)
        }
    } else {
        Write-Host "HLLV and HLL WW2 servers: waiting for check"
    }

    Write-Host ""
    if ($NextCheckSeconds -ge 0) {
        Write-Host "Next check in $NextCheckSeconds seconds"
    } else {
        Write-Host "Next check: working..."
    }
}

function Wait-WithDashboardCountdown {
    param(
        [int]$Seconds,
        [string]$PlayerName,
        [object[]]$ServerStatuses = @(),
        [string]$Message = "Waiting..."
    )

    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Show-SeedingDashboard -PlayerName $PlayerName -ServerStatuses $ServerStatuses -Message $Message -NextCheckSeconds $remaining
        Start-Sleep -Seconds 1
    }
}

function Get-ServerNumber {
    param([object]$Server)

    if (![string]::IsNullOrWhiteSpace("$($Server.number)")) {
        return "$($Server.number)"
    }

    $label = "$($Server.searchText) $($Server.name)"
    if ($label -match "#(\d+)") {
        return $Matches[1]
    }

    return $Server.name
}

function Get-ServerStatuses {
    param(
        [object]$Config,
        [object[]]$Servers,
        [int]$GamePriority = 0,
        [switch]$LogResults
    )

    $statuses = @()
    for ($index = 0; $index -lt $Servers.Count; $index++) {
        $server = $Servers[$index]
        $serverNumber = Get-ServerNumber -Server $server

        try {
            $players = Get-PlayerCount -Server $server
        } catch {
            if ($LogResults) {
                Write-Log "$($Config.displayName) server $serverNumber is DOWN because its stats page is unavailable. Skipping it until the next check."
            }

            $statuses += [pscustomobject]@{
                Game = $Config
                GameId = "$($Config.gameId)"
                GameName = "$($Config.displayName)"
                GameEnabled = [bool]$Config.gameEnabled
                GamePriority = $GamePriority
                Server = $server
                ServerNumber = $serverNumber
                Players = 0
                MaxPlayers = [int]$Config.maxPlayers
                Order = $index
                IsAvailable = $false
                IsUnderSeedThreshold = $false
                IsActiveSeed = $false
            }
            continue
        }

        $isUnderSeedThreshold = $players -lt [int]$Config.seedBelowPlayers
        $isActiveSeed = $players -gt [int]$Config.activeSeedPlayers -and $isUnderSeedThreshold
        if ($LogResults) {
            if (!$Config.gameEnabled) {
                Write-Log "$($Config.displayName) server $serverNumber is $players/$($Config.maxPlayers) - disabled."
            } elseif ($isActiveSeed) {
                Write-Log "$($Config.displayName) server $serverNumber is $players/$($Config.maxPlayers) - active seed."
            } elseif ($isUnderSeedThreshold) {
                Write-Log "$($Config.displayName) server $serverNumber is $players/$($Config.maxPlayers) - under 50, available by server order."
            } else {
                Write-Log "$($Config.displayName) server $serverNumber is $players/$($Config.maxPlayers) - not seeding right now."
            }
        }

        $statuses += [pscustomobject]@{
            Game = $Config
            GameId = "$($Config.gameId)"
            GameName = "$($Config.displayName)"
            GameEnabled = [bool]$Config.gameEnabled
            GamePriority = $GamePriority
            Server = $server
            ServerNumber = $serverNumber
            Players = $players
            MaxPlayers = [int]$Config.maxPlayers
            Order = $index
            IsAvailable = $true
            IsUnderSeedThreshold = $isUnderSeedThreshold
            IsActiveSeed = $isActiveSeed
        }
    }

    return @($statuses)
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
    if (!$config.version) { $config | Add-Member -NotePropertyName version -NotePropertyValue "2.3.4" }
    if (!$config.enabledGames) {
        $config | Add-Member -NotePropertyName enabledGames -NotePropertyValue ([pscustomobject]@{ hllv = $true; hllWw2 = $true })
    }
    if (!$config.steamAppId) { $config | Add-Member -NotePropertyName steamAppId -NotePropertyValue 3079210 }
    if (!$config.playerProfileFile) { $config | Add-Member -NotePropertyName playerProfileFile -NotePropertyValue "player-profile.json" }
    if (!$config.activeSeedPlayers) { $config | Add-Member -NotePropertyName activeSeedPlayers -NotePropertyValue 3 }
    if (!$config.gameProcessNames) { $config | Add-Member -NotePropertyName gameProcessNames -NotePropertyValue $DefaultConfig.gameProcessNames }
    if (!$config.hllWw2) { $config | Add-Member -NotePropertyName hllWw2 -NotePropertyValue ([pscustomobject]$DefaultWw2Config) }
    if (!$config.servers -or $config.servers.Count -eq 0) {
        throw "No servers are configured. Add at least one server to $ConfigPath."
    }
    return $config
}

function Get-GameConfigurations {
    param([object]$Config)

    $sharedProperties = @("seedBelowPlayers", "activeSeedPlayers", "seededAtPlayers", "maxPlayers", "pollSeconds", "reconnectWaitSeconds", "connectionMissesBeforeRestart", "closeGraceSeconds")
    if (!$Config.gameId) { $Config | Add-Member -NotePropertyName gameId -NotePropertyValue "hllv" -Force }
    if (!$Config.displayName) { $Config | Add-Member -NotePropertyName displayName -NotePropertyValue "HLLV" -Force }
    $Config | Add-Member -NotePropertyName gameEnabled -NotePropertyValue ([bool]$Config.enabledGames.hllv) -Force

    $ww2 = $Config.hllWw2
    if (!$ww2.gameId) { $ww2 | Add-Member -NotePropertyName gameId -NotePropertyValue "hllWw2" -Force }
    if (!$ww2.displayName) { $ww2 | Add-Member -NotePropertyName displayName -NotePropertyValue "HLL WW2" -Force }
    $ww2 | Add-Member -NotePropertyName gameEnabled -NotePropertyValue ([bool]$Config.enabledGames.hllWw2) -Force
    foreach ($property in $sharedProperties) {
        if ($null -eq $ww2.$property) {
            $ww2 | Add-Member -NotePropertyName $property -NotePropertyValue $Config.$property -Force
        }
    }

    return @($Config, $ww2)
}

function Get-AllServerStatuses {
    param(
        [object[]]$Games,
        [switch]$LogResults
    )

    $statuses = @()
    for ($gameIndex = 0; $gameIndex -lt $Games.Count; $gameIndex++) {
        $game = $Games[$gameIndex]
        $servers = @($game.servers | Where-Object { $_.enabled -ne $false })
        if ($servers.Count -eq 0) {
            continue
        }

        $statuses += @(Get-ServerStatuses -Config $game -Servers $servers -GamePriority $gameIndex -LogResults:$LogResults)
    }
    return @($statuses)
}

function Get-ServerStatusKey {
    param([object]$Status)

    "$($Status.GameId):$($Status.ServerNumber)"
}

function Get-PrioritySeedingTarget {
    param(
        [object[]]$Statuses,
        [object[]]$Games,
        [hashtable]$SkipUntil = @{},
        [datetime]$Now = (Get-Date)
    )

    foreach ($key in @($SkipUntil.Keys)) {
        if ($SkipUntil[$key] -le $Now) {
            [void]$SkipUntil.Remove($key)
        }
    }

    foreach ($game in @($Games)) {
        $target = @($Statuses |
            Where-Object {
                $statusKey = Get-ServerStatusKey -Status $_
                $_.GameId -eq $game.gameId -and
                    $_.IsAvailable -ne $false -and
                    $_.IsUnderSeedThreshold -and
                    !$SkipUntil.ContainsKey($statusKey)
            } |
            Sort-Object @{ Expression = {
                if ($_.GameId -eq "hllv" -and "$($_.ServerNumber)" -match '^\d+$') {
                    [int]$_.ServerNumber
                } else {
                    [int]$_.Order
                }
            }; Descending = $false } |
            Select-Object -First 1)

        if ($target.Count -gt 0) {
            return $target[0]
        }
    }

    return
}

function Get-SteamPath {
    param([int]$AppId)

    $steamProcess = Get-Process "Steam" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($steamProcess -and $steamProcess.Path -and (Test-Path -Path $steamProcess.Path)) {
        return $steamProcess.Path
    }

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    )
    foreach ($registryPath in $registryPaths) {
        $steamKey = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
        foreach ($value in @($steamKey.SteamExe, $steamKey.InstallPath, $steamKey.SteamPath)) {
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            $candidate = $value
            if ((Split-Path -Leaf $candidate) -ne "steam.exe") {
                $candidate = Join-Path $candidate "steam.exe"
            }

            if (Test-Path -Path $candidate) {
                return $candidate
            }
        }
    }

    $knownPaths = @(
        "$env:ProgramFiles(x86)\Steam\steam.exe",
        "$env:ProgramFiles\Steam\steam.exe",
        "$env:LOCALAPPDATA\Steam\steam.exe"
    )
    foreach ($knownPath in $knownPaths) {
        if ($knownPath -and (Test-Path -Path $knownPath)) {
            return $knownPath
        }
    }

    Write-Log "Could not find steam.exe. Falling back to Steam URL launch."
    return "steam://rungameid/$AppId"
}

function Get-GameProcesses {
    param([object]$Config)
    foreach ($processName in $Config.gameProcessNames) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue
    }
}

function Stop-Game {
    param(
        [object]$Config,
        [switch]$QuietIfStopped
    )

    $processes = @(Get-GameProcesses -Config $Config)
    if ($processes.Count -eq 0) {
        if (!$QuietIfStopped) {
            Write-Log "$($Config.displayName) is not currently running."
        }
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
            $statusCode = $null
            try {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            } catch {
            }

            $isServerError = ($statusCode -ge 500 -and $statusCode -lt 600) -or
                $_.Exception.Message -match '(?i)(?:\(|\b)5\d\d(?:\)|\b).*server error'
            if ($isServerError) {
                throw
            }

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
        $players = 0
        $playerCountValue = $json.result.player_count
        if ($null -eq $playerCountValue -or
            ![int]::TryParse("$playerCountValue", [ref]$players) -or
            $players -lt 0) {
            throw "The stats page returned no valid player count."
        }
        return $players
    }

    $uri = "https://api.battlemetrics.com/servers/$($Server.battleMetricsId)"
    $json = Invoke-RestMethod -Uri $uri
    return [int]$json.data.attributes.players
}

function ConvertTo-ComparablePlayerName {
    param([string]$PlayerName)

    if ([string]::IsNullOrWhiteSpace($PlayerName)) {
        return ""
    }

    $normalized = $PlayerName.Normalize([Text.NormalizationForm]::FormKC)
    $normalized = [Regex]::Replace($normalized, "\p{Cf}", "")
    $normalized = [Regex]::Replace($normalized, "\s+", " ").Trim()
    return $normalized.ToUpperInvariant()
}

function Get-PlayerConnectionState {
    param(
        [object]$Server,
        [object]$PlayerProfile
    )

    $expectedName = ConvertTo-ComparablePlayerName -PlayerName "$($PlayerProfile.playerName)"

    if (![string]::IsNullOrWhiteSpace($Server.easyStatsUrl)) {
        $uri = "$($Server.easyStatsUrl.TrimEnd('/'))/api/get_live_game_stats"
        $json = Invoke-EasyRestMethod -Uri $uri
        $allPlayers = @($json.result.stats)
        $onlinePlayers = @($allPlayers | Where-Object { "$($_.status)" -ieq "online" })
        $matchingPlayers = @($allPlayers | Where-Object {
            (ConvertTo-ComparablePlayerName -PlayerName "$($_.player)") -eq $expectedName
        })
        $matchingOnlinePlayers = @($matchingPlayers | Where-Object { "$($_.status)" -ieq "online" })

        return [pscustomobject]@{
            Connected = $matchingOnlinePlayers.Count -gt 0
            MatchFound = $matchingPlayers.Count -gt 0
            OnlinePlayerCount = $onlinePlayers.Count
            MatchingStatuses = @($matchingPlayers | ForEach-Object { "$($_.status)" } | Sort-Object -Unique)
            MatchingNames = @($matchingPlayers | ForEach-Object { "$($_.player)" } | Sort-Object -Unique)
        }
    }

    $uri = "https://api.battlemetrics.com/servers/$($Server.battleMetricsId)`?include=identifier"
    $response = Invoke-WebRequest -Uri $uri
    $escapedPlayerName = [Regex]::Escape("$($PlayerProfile.playerName)")
    $connected = $response.Content -match $escapedPlayerName
    return [pscustomobject]@{
        Connected = $connected
        MatchFound = $connected
        OnlinePlayerCount = if ($connected) { 1 } else { 0 }
        MatchingStatuses = @()
        MatchingNames = @()
    }
}

function Start-Server {
    param(
        [object]$Config,
        [object]$Server,
        [string]$SteamPath
    )

    $arguments = "-applaunch $($Config.steamAppId)"
    Write-Log "Launching $($Config.displayName) for $($Server.name) with Steam App ID $($Config.steamAppId)."

    if ($DryRun) {
        if ($SteamPath -like "steam://*") {
            Write-Host "DRY RUN: Start-Process `"$SteamPath`""
        } else {
            Write-Host "DRY RUN: Start-Process `"$SteamPath`" -ArgumentList `"$arguments`""
        }
        return
    }

    if ($SteamPath -like "steam://*") {
        Start-Process $SteamPath
    } else {
        Start-Process $SteamPath -ArgumentList $arguments
    }
    Start-Sleep -Seconds ([int]$Config.launchWaitSeconds)

    if ($Config.uiAutomation -and $Config.uiAutomation.enabled -ne $false) {
        $searchText = if (![string]::IsNullOrWhiteSpace($Server.searchText)) { $Server.searchText } else { $Server.name }
        Write-Log "Using the $($Config.displayName) server browser to join $searchText."

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
        $enlistClickCount = if ($Config.uiAutomation.enlistClickCount) { [int]$Config.uiAutomation.enlistClickCount } else { 2 }
        for ($click = 1; $click -le $enlistClickCount; $click++) {
            Set-GameForeground -Config $Config | Out-Null
            Invoke-GameClick -Config $Config -X ([int]$Config.uiAutomation.enlistX) -Y ([int]$Config.uiAutomation.enlistY) -Name "Enlist"
            if ($click -lt $enlistClickCount) {
                Start-Sleep -Milliseconds 900
            }
        }
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
        Write-Log "Joining $($Config.displayName) server $serverNumber now."
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
    Write-Host "First-time EASY seeding setup"
    Write-Host "This saves your personal player info on this PC only."
    Write-Host ""

    $playerName = Read-RequiredValue -Prompt "Enter your Steam name letter-for-letter exactly as it appears in EASY stats"

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
$allGames = @(Get-GameConfigurations -Config $config)
$enabledGames = @($allGames | Where-Object { $_.gameEnabled })
if ($enabledGames.Count -eq 0) {
    Write-Host "No games are enabled. Select HLLV, HLL WW2, or both in the helper."
    Stop-SeederTranscript
    exit 0
}

foreach ($game in $enabledGames) {
    $configuredServers = @($game.servers | Where-Object {
        $_.enabled -ne $false -and (
            (![string]::IsNullOrWhiteSpace($_.easyStatsUrl) -and $_.easyStatsUrl -notmatch "^REPLACE_WITH_") -or
            (![string]::IsNullOrWhiteSpace($_.battleMetricsId) -and $_.battleMetricsId -notmatch "^REPLACE_WITH_")
        )
    })
    if ($configuredServers.Count -eq 0) {
        throw "$($game.displayName) is enabled but has no configured server stats endpoint."
    }
}

$playerProfile = Get-PlayerProfile -Config $config
$steamName = $playerProfile.playerName

Write-Host ""
Write-Host "EASY Hell Let Loose seeding helper"
Write-Host "Player: $steamName"
Write-Host "Config: $ConfigPath"
Write-Host "Games: $(@($enabledGames.displayName) -join ' -> ')"
Write-Host ""

Show-SeedingDashboard -PlayerName $steamName -Message "Starting server checks..."

$skippedServerUntil = @{}
do {
    foreach ($game in $enabledGames) {
        Stop-Game -Config $game -QuietIfStopped
    }

    $serverStatuses = @(Get-AllServerStatuses -Games $allGames -LogResults)
    Show-SeedingDashboard -PlayerName $steamName -ServerStatuses $serverStatuses -Message "Finished checking HLLV and HLL WW2 servers."

    $targetStatus = @(Get-PrioritySeedingTarget -Statuses $serverStatuses -Games $enabledGames -SkipUntil $skippedServerUntil)
    if ($targetStatus.Count -gt 0 -and
        (!$targetStatus[0].Game -or !$targetStatus[0].Server -or [string]::IsNullOrWhiteSpace("$($targetStatus[0].ServerNumber)"))) {
        Write-Log "The priority scan returned an invalid server target. Ignoring it and checking again on the next scan."
        $targetStatus = @()
    }
    if ($targetStatus.Count -gt 0 -and $targetStatus[0].GameId -ne "hllv" -and
        @($enabledGames | Where-Object { $_.gameId -eq "hllv" }).Count -gt 0) {
        Write-Log "No available HLLV server currently needs seeding. Checking HLL WW2 next."
    }

    if ($targetStatus.Count -eq 0) {
        $downStatuses = @($serverStatuses | Where-Object { $_.GameEnabled -and $_.IsAvailable -eq $false })
        $waitMessage = "All selected games are seeded. Waiting to check again."
        if ($downStatuses.Count -gt 0) {
            $downLabels = @($downStatuses | ForEach-Object { "$($_.GameName) server $($_.ServerNumber)" }) -join ", "
            Write-Log "$downLabels DOWN and skipped. Checking again in $($config.pollSeconds) seconds."
            $waitMessage = "Down servers are skipped. Waiting to check again."
        } else {
            Write-Log "All enabled EASY servers are at 50 players or higher. Checking again in $($config.pollSeconds) seconds."
        }
        if ($Once) { break }
        Wait-WithDashboardCountdown -Seconds ([int]$config.pollSeconds) -PlayerName $steamName -ServerStatuses $serverStatuses -Message $waitMessage
        continue
    }

    $gameConfig = $targetStatus[0].Game
    $server = $targetStatus[0].Server
    $serverNumber = $targetStatus[0].ServerNumber
    Write-Log "Best target is $($gameConfig.displayName) server $serverNumber at $($targetStatus[0].Players)/$($gameConfig.maxPlayers). Connecting now."
    Show-SeedingDashboard -PlayerName $steamName -ServerStatuses $serverStatuses -Message "Joining $($gameConfig.displayName) server $serverNumber now."
    try {
        $steamPath = if ($DryRun) { "steam.exe" } else { Get-SteamPath -AppId ([int]$gameConfig.steamAppId) }
        Start-Server -Config $gameConfig -Server $server -SteamPath $steamPath
    } catch {
        $failedKey = Get-ServerStatusKey -Status $targetStatus[0]
        $skippedServerUntil[$failedKey] = (Get-Date).AddSeconds([int]$gameConfig.pollSeconds)
        Write-Log "Could not launch or join $($gameConfig.displayName) server $serverNumber. Skipping it for this scan and continuing by priority."
        Stop-Game -Config $gameConfig -QuietIfStopped
        continue
    }
    if ($DryRun) {
        Write-Log "Dry run selected $($gameConfig.displayName) server $serverNumber. No game was launched."
        break
    }

    $players = [int]$targetStatus[0].Players
    $restartScan = $false
    do {
        $latestServerStatuses = @(Get-AllServerStatuses -Games $allGames)
        if ($latestServerStatuses.Count -gt 0) {
            $serverStatuses = $latestServerStatuses
        }

        $currentStatus = @($latestServerStatuses | Where-Object {
            $_.GameId -eq $gameConfig.gameId -and "$($_.ServerNumber)" -eq "$serverNumber"
        } | Select-Object -First 1)
        if ($currentStatus.Count -eq 0 -or $currentStatus[0].IsAvailable -eq $false) {
            Write-Log "$($gameConfig.displayName) server $serverNumber is DOWN. Closing $($gameConfig.displayName) and checking the other servers."
            Stop-Game -Config $gameConfig
            $restartScan = $true
            break
        }

        $players = [int]$currentStatus[0].Players
        if (!$currentStatus[0].IsUnderSeedThreshold) {
            break
        }

        $preferredTarget = @(Get-PrioritySeedingTarget -Statuses $latestServerStatuses -Games $enabledGames -SkipUntil $skippedServerUntil)
        if ($preferredTarget.Count -gt 0 -and
            ($preferredTarget[0].GameId -ne $gameConfig.gameId -or "$($preferredTarget[0].ServerNumber)" -ne "$serverNumber")) {
            Write-Log "Priority scan now selects $($preferredTarget[0].GameName) server $($preferredTarget[0].ServerNumber). Closing $($gameConfig.displayName) server $serverNumber and switching."
            Stop-Game -Config $gameConfig
            $restartScan = $true
            break
        }

        $gameProcesses = @(Get-GameProcesses -Config $gameConfig)
        if ($gameProcesses.Count -eq 0) {
            $failedKey = Get-ServerStatusKey -Status $currentStatus[0]
            $skippedServerUntil[$failedKey] = (Get-Date).AddSeconds([int]$gameConfig.pollSeconds)
            Write-Log "$($gameConfig.displayName) failed to stay open for server $serverNumber. Skipping that server for this scan and continuing by priority."
            $restartScan = $true
            break
        }

        try {
            $connectionState = Get-PlayerConnectionState -Server $server -PlayerProfile $playerProfile
        } catch {
            Write-Log "$($gameConfig.displayName) server $serverNumber is DOWN because its stats page is unavailable. Closing the game and checking the other servers."
            Stop-Game -Config $gameConfig
            $restartScan = $true
            break
        }

        if (!$connectionState.Connected) {
            $detectionDetail = if ($connectionState.MatchFound) {
                "matching stats row status: $(@($connectionState.MatchingStatuses) -join ', ')"
            } else {
                "name absent from $($connectionState.OnlinePlayerCount) online stats row(s)"
            }

            $failedKey = Get-ServerStatusKey -Status $currentStatus[0]
            $skippedServerUntil[$failedKey] = (Get-Date).AddSeconds([int]$gameConfig.pollSeconds)
            Write-Log "$steamName was not confirmed on $($server.name) ($detectionDetail). Treating the connection as failed, skipping this server for the current scan, and continuing by priority."
            Stop-Game -Config $gameConfig
            $restartScan = $true
            break
        } else {
            Write-Log "You are seeding $($gameConfig.displayName) server $serverNumber. Population is $players/$($gameConfig.maxPlayers)."
            Show-SeedingDashboard -PlayerName $steamName -ServerStatuses $serverStatuses -Message "You are seeding $($gameConfig.displayName) server $serverNumber. Population is $players/$($gameConfig.maxPlayers)."
        }

        Wait-WithDashboardCountdown -Seconds ([int]$gameConfig.pollSeconds) -PlayerName $steamName -ServerStatuses $serverStatuses -Message "You are seeding $($gameConfig.displayName) server $serverNumber."
    } while (!$restartScan)

    if ($restartScan) {
        continue
    }

    Write-Log "$($server.name) reached $players/$($gameConfig.maxPlayers). Closing $($gameConfig.displayName) and checking the selected games again."
    Stop-Game -Config $gameConfig
} while (!$Once)

$script:StatusMessage = "Seeder stopped."
$script:StatusNextCheckSeconds = -1
Publish-SeederStatus -Running $false
Stop-SeederTranscript
