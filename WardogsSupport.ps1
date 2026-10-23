function Initialize-WardogsConfig {
    param([object]$Config)

    if (!$Config.enabledGames.PSObject.Properties['wardogs']) {
        $Config.enabledGames | Add-Member -NotePropertyName wardogs -NotePropertyValue $false
    }
    if (!$Config.PSObject.Properties['wardogs']) {
        $Config | Add-Member -NotePropertyName wardogs -NotePropertyValue ([pscustomobject]@{
            displayName = 'WARDOGS'
            steamAppId = 1867240
            seedBelowPlayers = 50
            activeSeedPlayers = 3
            seededAtPlayers = 50
            maxPlayers = 100
            launchWaitSeconds = 90
            postClickWaitSeconds = 60
            pollSeconds = 60
            reconnectWaitSeconds = 60
            connectionMissesBeforeRestart = 3
            closeGraceSeconds = 15
            activityClickSeconds = 5
            gameProcessNames = @('WardogsClient-Win64-Shipping', 'WardogsLauncher-Shipping')
            uiAutomation = [pscustomobject]@{
                enabled = $true
                referenceWidth = 1920
                referenceHeight = 1080
                focusX = 960
                focusY = 865
                enlistX = 225
                enlistY = 799
                enlistClickCount = 1
                searchX = 300
                searchY = 150
                joinX = 1600
                joinY = 1000
                menuReadyWaitSeconds = 15
                afterFocusClickWaitSeconds = 5
                browserWaitSeconds = 15
                searchWaitSeconds = 8
                joinWaitSeconds = 120
            }
            servers = @(
                [pscustomobject]@{
                    number = 'EAST'
                    name = 'EASY Company | NA EAST | discord.gg/easycompany'
                    searchText = 'EASY Company | NA EAST'
                    joinCode = '797c7a1a-5a3a-48c8-a39b-88f392730d05'
                    enabled = $true
                },
                [pscustomobject]@{
                    number = 'WEST'
                    name = 'EASY Company | NA WEST | discord.gg/easycompany'
                    searchText = 'EASY Company | NA WEST'
                    joinCode = 'c3bb6255-fe3b-44e9-a993-5605efc4eb2d'
                    enabled = $true
                },
                [pscustomobject]@{
                    number = 'COMP'
                    name = 'EASY Company | Comp | NA CENTRAL | discord.gg/easycompany'
                    searchText = 'EASY Company | Comp | NA CENTRAL'
                    joinCode = '1aab33d8-a44b-4c62-8d5c-f51281e413f6'
                    enabled = $false
                }
            )
        })
    }
}

function Get-WardogsStatsUri {
    'https://api.wardogservers.com/v1/servers?q=EASY%20Company&type=community&limit=20'
}

function ConvertFrom-WardogsSnapshot {
    param([object]$Snapshot, [object]$Server, [datetimeoffset]$Now = [datetimeoffset]::UtcNow)

    if (!$Snapshot.meta -or $Snapshot.meta.stale -eq $true) {
        throw 'WARDOGS server data is unavailable or stale.'
    }
    $fetchedAt = [datetimeoffset]::MinValue
    if (![datetimeoffset]::TryParse("$($Snapshot.meta.fetchedAt)", [ref]$fetchedAt) -or
        ($Now - $fetchedAt).TotalSeconds -gt 600 -or ($fetchedAt - $Now).TotalSeconds -gt 60) {
        throw 'WARDOGS server snapshot is too old to use.'
    }
    $matchesByCode = @($Snapshot.data | Where-Object { "$($_.serverId)" -eq "$($Server.joinCode)" })
    if ($matchesByCode.Count -ne 1) {
        throw "WARDOGS server $($Server.number) is not in the current server list."
    }
    $entry = $matchesByCode[0]
    $observedAt = [datetimeoffset]::MinValue
    $players = 0
    $maximum = 0
    if (![datetimeoffset]::TryParse("$($entry.observedAt)", [ref]$observedAt) -or
        ($Now - $observedAt).TotalSeconds -gt 600 -or ($observedAt - $Now).TotalSeconds -gt 60 -or
        ![int]::TryParse("$($entry.players)", [ref]$players) -or
        ![int]::TryParse("$($entry.maxPlayers)", [ref]$maximum) -or
        $players -lt 0 -or $maximum -le 0 -or $players -gt $maximum) {
        throw "WARDOGS server $($Server.number) returned stale or invalid population data."
    }
    if ($entry.passwordProtected) {
        throw "WARDOGS server $($Server.number) is password protected."
    }
    [pscustomobject]@{
        Players = $players
        MaxPlayers = $maximum
        ObservedAt = $observedAt
        Name = "$($entry.name)"
        InstanceId = "$($entry.id)"
        JoinCode = "$($entry.serverId)"
        RefreshSeconds = [int]$Snapshot.meta.refreshSeconds
    }
}

function Get-WardogsServerData {
    param([object]$Server)

    if (!$script:WardogsFetchedAt -or ((Get-Date) - $script:WardogsFetchedAt).TotalSeconds -ge 30) {
        $script:WardogsSnapshot = $null
        $script:WardogsFetchError = $null
        $script:WardogsFetchedAt = Get-Date
        try {
            $script:WardogsSnapshot = Invoke-RestMethod -Uri (Get-WardogsStatsUri) -TimeoutSec 15 -ErrorAction Stop
        } catch {
            $script:WardogsFetchError = $_.Exception.Message
        }
    }
    if ($script:WardogsFetchError) { throw $script:WardogsFetchError }
    ConvertFrom-WardogsSnapshot -Snapshot $script:WardogsSnapshot -Server $Server
}

function Initialize-WardogsScreenReader {
    if ($script:WardogsOcrEngine) { return }
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    if (!('WardogsNative' -as [type])) {
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class WardogsNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref POINT point);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    public static Bitmap Capture(IntPtr window) {
        if (GetForegroundWindow() != window || IsIconic(window)) return null;
        RECT rect; POINT origin = new POINT();
        if (!GetClientRect(window, out rect) || !ClientToScreen(window, ref origin)) return null;
        int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
        if (width < 640 || height < 360 || width > 10000 || height > 10000) return null;
        var bitmap = new Bitmap(width, height);
        using (var graphics = Graphics.FromImage(bitmap)) {
            graphics.CopyFromScreen(origin.X, origin.Y, 0, 0, bitmap.Size);
        }
        if (GetForegroundWindow() != window) { bitmap.Dispose(); return null; }
        return bitmap;
    }
    public static bool HasMatchHud(Bitmap bitmap) {
        // The three faction score strips are anchored below the minimap.
        double scale = Math.Min(bitmap.Width / 1920.0, bitmap.Height / 1080.0);
        int left = (int)(30 * scale), right = (int)(288 * scale);
        int top = bitmap.Height - (int)(104 * scale), bottom = bitmap.Height - (int)(48 * scale);
        int blue = 0, red = 0, green = 0;
        for (int y = Math.Max(0, top); y < bottom; y += 2)
            for (int x = left; x < right; x += 2) {
                var pixel = bitmap.GetPixel(x, y);
                if (pixel.B > 110 && pixel.G > 90 && pixel.R < 105 && pixel.B > pixel.R * 1.4) blue++;
                if (pixel.R > 105 && pixel.G < 100 && pixel.B < 110 && pixel.R > pixel.G * 1.4) red++;
                if (pixel.G > 100 && pixel.R < 110 && pixel.B < 150 && pixel.G > pixel.R * 1.4) green++;
            }
        return blue >= 5 && red >= 5 && green >= 20;
    }
    public static bool ActivityClick(IntPtr window) {
        if (GetForegroundWindow() != window || IsIconic(window)) return false;
        RECT rect; POINT origin = new POINT(); POINT cursor;
        if (!GetClientRect(window, out rect) || !ClientToScreen(window, ref origin)) return false;
        GetCursorPos(out cursor);
        POINT target = new POINT { X = origin.X + (rect.Right - rect.Left) / 2, Y = origin.Y + (rect.Bottom - rect.Top) / 2 };
        if (WindowFromPoint(target) != window) return false;
        SetCursorPos(target.X, target.Y);
        System.Threading.Thread.Sleep(80);
        if (GetForegroundWindow() != window) return false;
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        if (GetForegroundWindow() == window) SetCursorPos(cursor.X, cursor.Y);
        return true;
    }
}
'@
    }
    $null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation,ContentType=WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
    $script:WardogsOcrEngine = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]::TryCreateFromLanguage(
        [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new('en-US'))
    if (!$script:WardogsOcrEngine) { throw 'Install Windows English OCR support before enabling WARDOGS.' }
    $script:WardogsAsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and
        $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
}

function Wait-WardogsWinRt {
    param($Operation, [type]$ResultType)
    $task = $script:WardogsAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    if (!$task.Wait(5000)) { throw 'WARDOGS screen reading timed out.' }
    $task.GetAwaiter().GetResult()
}

function Get-WardogsScreen {
    Initialize-WardogsScreenReader
    $process = Get-Process -Name 'WardogsClient-Win64-Shipping' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (!$process) { return [pscustomobject]@{ State = 'Closed'; Text = ''; Lines = @(); Handle = [IntPtr]::Zero } }
    $bitmap = [WardogsNative]::Capture($process.MainWindowHandle)
    if (!$bitmap) { return [pscustomobject]@{ State = 'Background'; Text = ''; Lines = @(); Handle = $process.MainWindowHandle } }
    if ([WardogsNative]::HasMatchHud($bitmap)) {
        $width = $bitmap.Width
        $height = $bitmap.Height
        $bitmap.Dispose()
        return [pscustomobject]@{ State = 'Match'; Text = 'Three-faction match HUD'; Lines = @(); Handle = $process.MainWindowHandle; Width = $width; Height = $height }
    }
    $scaled = $null
    $memory = $null
    $randomAccess = $null
    $software = $null
    try {
        $ratio = [Math]::Min(1.0, 1920.0 / $bitmap.Width)
        $scaled = [System.Drawing.Bitmap]::new($bitmap, [int]($bitmap.Width * $ratio), [int]($bitmap.Height * $ratio))
        $memory = [System.IO.MemoryStream]::new()
        $scaled.Save($memory, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $memory.Position = 0
        $randomAccess = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memory)
        $decoder = Wait-WardogsWinRt -Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($randomAccess)) -ResultType ([Windows.Graphics.Imaging.BitmapDecoder])
        $software = Wait-WardogsWinRt -Operation ($decoder.GetSoftwareBitmapAsync()) -ResultType ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result = Wait-WardogsWinRt -Operation ($script:WardogsOcrEngine.RecognizeAsync($software)) -ResultType ([Windows.Media.Ocr.OcrResult])
        $lines = @($result.Lines | ForEach-Object {
            $words = @($_.Words)
            $first = $words[0].BoundingRect
            $last = $words[-1].BoundingRect
            [pscustomobject]@{
                Text = "$($_.Text)"
                X = ($first.X + $last.X + $last.Width) / 2 / $ratio
                Y = ($first.Y + $first.Height / 2) / $ratio
            }
        })
        $text = ($lines.Text -join "`n")
        $kind = Get-WardogsScreenKind -Text $text
        [pscustomobject]@{ State = $kind; Text = $text; Lines = $lines; Handle = $process.MainWindowHandle; Width = $bitmap.Width; Height = $bitmap.Height }
    } finally {
        if ($software) { $software.Dispose() }
        if ($randomAccess) { $randomAccess.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($scaled) { $scaled.Dispose() }
        $bitmap.Dispose()
    }
}

function Get-WardogsScreenKind {
    param([string]$Text)
    if ($Text -match '(?i)DISCONNECTED|CONNECTION (?:LOST|FAILED)|KICKED|NETWORK ERROR|SESSION (?:LOST|ENDED)') { return 'Disconnected' }
    if ($Text -match '(?i)SELECT\s+FACTION') { return 'Faction' }
    if ($Text -match '(?i)JOIN GAME SERVER') { return 'ConfirmServer' }
    if ($Text -match '(?i)FIND SERVER|ENTER SERVER ID') { return 'FindServer' }
    if ($Text -match (Get-WardogsJoinByIdPattern)) { return 'Browser' }
    if ($Text -match '(?i)OFFICIAL SERVERS' -and $Text -match '(?i)COMMUNITY SERVERS') { return 'BrowserType' }
    if ($Text -match '(?i)PRESS ANY BUTTON') { return 'Start' }
    if ($Text -match '(?i)OUTDATED GRAPHICS DRIVER') { return 'DriverNotice' }
    if ($Text -match '(?i)FIRING RANGE|LEARN TO PLAY') { return 'MainMenu' }
    if ($Text -match '(?i)SAFE\s*ZONE' -or ($Text -match '(?i)SCOREBOARD' -and $Text -match '(?i)LEAVE MATCH|REDEPLOY')) { return 'Match' }
    return 'Unknown'
}

function Get-WardogsJoinByIdPattern {
    '(?i)\bJ[O0]IN\s+BY\s+[I1L][D0O]\b'
}

function Test-WardogsServerIdentity {
    param([object]$Screen, [object]$Server)

    # OCR often reads the pipe separators as I; match each name component separately.
    $identityLines = @($Screen.Lines | Where-Object {
        $_.Y -ge $Screen.Height * 0.42 -and $_.Y -le $Screen.Height * 0.55
    })
    if ($identityLines.Count -eq 0) { return $false }
    $compactText = [regex]::Replace(($identityLines.Text -join ' ').ToUpperInvariant(), '[^A-Z0-9]', '')
    foreach ($part in @($Server.searchText -split '\s*\|\s*')) {
        $compactPart = [regex]::Replace($part.ToUpperInvariant(), '[^A-Z0-9]', '')
        if (!$compactPart -or !$compactText.Contains($compactPart)) { return $false }
    }
    return $true
}

function Invoke-WardogsTextClick {
    param([object]$Screen, [string]$Pattern)
    $line = @($Screen.Lines | Where-Object { $_.Text -match $Pattern } | Select-Object -First 1)
    if ($line.Count -eq 0) { throw "WARDOGS control was not found: $Pattern" }
    $bounds = Get-GameWindowBounds -Config $script:WardogsConfig
    if (!$bounds -or [WardogsNative]::GetForegroundWindow() -ne $Screen.Handle) {
        throw 'WARDOGS lost focus before a menu click.'
    }
    Invoke-LeftClick -X ([int]($bounds.Left + $line[0].X)) -Y ([int]($bounds.Top + $line[0].Y))
}

function Get-WardogsDriverNoticeButton {
    param([object]$Screen)

    if ($Screen.State -ne 'DriverNotice') {
        throw 'The WARDOGS graphics-driver notice is not visible.'
    }

    $button = @($Screen.Lines | Where-Object {
        ([regex]::Replace("$($_.Text)", '[^A-Za-z0-9]', '')) -match '^[O0]K$'
    } | Select-Object -First 1)
    if ($button.Count -gt 0) {
        return [pscustomobject]@{ X = [int]$button[0].X; Y = [int]$button[0].Y; Source = 'button text' }
    }

    # OCR can miss the short OK label; the recognized dialog has one centered button.
    if ($Screen.Width -lt 640 -or $Screen.Height -lt 360) {
        throw 'WARDOGS window size is unavailable for the graphics-driver notice.'
    }
    $scale = [Math]::Min($Screen.Width / 1920.0, $Screen.Height / 1080.0)
    [pscustomobject]@{
        X = [int][Math]::Round($Screen.Width / 2.0)
        Y = [int][Math]::Round(($Screen.Height - 1080 * $scale) / 2.0 + 682 * $scale)
        Source = 'recognized dialog layout'
    }
}

function Test-WardogsGameFocused {
    param([object]$Screen)
    $Screen.Handle -ne [IntPtr]::Zero -and [WardogsNative]::GetForegroundWindow() -eq $Screen.Handle
}

function Dismiss-WardogsDriverNotice {
    param([object]$Config, [object]$Screen)

    $button = Get-WardogsDriverNoticeButton -Screen $Screen
    $bounds = Get-GameWindowBounds -Config $Config
    if (!$bounds -or !(Test-WardogsGameFocused -Screen $Screen)) {
        Write-Log 'WARDOGS graphics-driver notice is waiting for game focus.'
        return
    }
    Write-Log "Dismissing the WARDOGS graphics-driver notice using $($button.Source)."
    Invoke-LeftClick -X ([int]($bounds.Left + $button.X)) -Y ([int]($bounds.Top + $button.Y))
}

function Select-WardogsFaction {
    param([object]$Config)
    Write-Log 'Choosing a WARDOGS faction: quickly clicking all three teams.'
    foreach ($teamX in @(810, 960, 1110)) {
        Invoke-GameClick -Config $Config -X $teamX -Y 545 -Name 'faction'
        Start-Sleep -Milliseconds 120
    }
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
}

function Start-WardogsServer {
    param([object]$Config, [object]$Server)
    Stop-WardogsActivity
    Initialize-WardogsScreenReader
    $script:WardogsConfig = $Config
    $script:WardogsSession = $null
    $joinVerified = $false
    $factionPicked = $false
    $lastState = ''
    $deadline = (Get-Date).AddSeconds([int]$Config.uiAutomation.joinWaitSeconds + [int]$Config.uiAutomation.menuReadyWaitSeconds)
    do {
        $screen = Get-WardogsScreen
        if ($screen.State -ne $lastState) {
            Write-Log "WARDOGS join step: $($screen.State)."
            $lastState = $screen.State
        }
        switch ($screen.State) {
            'Closed' { throw 'WARDOGS closed before joining the server.' }
            'Background' { Set-GameForeground -Config $Config | Out-Null }
            'Start' { [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep -Seconds ([int]$Config.uiAutomation.afterFocusClickWaitSeconds) }
            'DriverNotice' { Dismiss-WardogsDriverNotice -Config $Config -Screen $screen }
            'MainMenu' { Invoke-WardogsTextClick -Screen $screen -Pattern '^DEPLOY$'; Start-Sleep -Seconds 2 }
            'BrowserType' { Invoke-WardogsTextClick -Screen $screen -Pattern '^COMMUNITY$'; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Seconds ([int]$Config.uiAutomation.browserWaitSeconds) }
            'Browser' { Invoke-WardogsTextClick -Screen $screen -Pattern (Get-WardogsJoinByIdPattern) }
            'FindServer' {
                Invoke-GameClick -Config $Config -X 920 -Y 547 -Name 'server ID input'
                [System.Windows.Forms.SendKeys]::SendWait('^a')
                [System.Windows.Forms.Clipboard]::SetText("$($Server.joinCode)")
                [System.Windows.Forms.SendKeys]::SendWait('^v')
                Start-Sleep -Milliseconds 300
                Invoke-WardogsTextClick -Screen $screen -Pattern '^LOOKUP$'
                Start-Sleep -Seconds ([int]$Config.uiAutomation.searchWaitSeconds)
            }
            'ConfirmServer' {
                if (!(Test-WardogsServerIdentity -Screen $screen -Server $Server)) { throw 'WARDOGS lookup returned an unexpected server. Join cancelled.' }
                Write-Log "Joining WARDOGS server $($Server.number) now, using its verified server ID."
                $joinVerified = $true
                Invoke-WardogsTextClick -Screen $screen -Pattern '^JOIN MATCH$'
            }
            'Faction' {
                if (!$joinVerified) { throw 'WARDOGS reached faction selection without confirming the target server.' }
                Select-WardogsFaction -Config $Config
                $factionPicked = $true
                Start-Sleep -Seconds 5
            }
            'Match' {
                if (!$joinVerified -or !$factionPicked) { throw 'WARDOGS match appeared without a verified server and team selection.' }
                $process = Get-Process -Name 'WardogsClient-Win64-Shipping' -ErrorAction Stop | Select-Object -First 1
                $script:WardogsSession = [pscustomobject]@{
                    JoinCode = "$($Server.joinCode)"
                    ProcessId = $process.Id
                    LastMatchedAt = Get-Date
                }
                Start-WardogsActivity -Config $Config
                Write-Log "WARDOGS server $($Server.number) and joined-team match screen confirmed. Activity click every 5 seconds while WARDOGS is in front."
                return
            }
            'Disconnected' { throw 'WARDOGS reported a connection failure.' }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "WARDOGS did not reach a confirmed match before the join timeout. Last screen: $lastState."
}

function Start-WardogsActivity {
    param([object]$Config)
    Stop-WardogsActivity
    $script:WardogsActivityState = [hashtable]::Synchronized(@{
        Active = $true
        LastClick = $null
        LastScreen = 'Match'
        CheckedAt = Get-Date
        Error = ''
    })
    $script:WardogsActivityWorker = [PowerShell]::Create()
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.Open()
    $script:WardogsActivityWorker.Runspace = $runspace
    $null = $script:WardogsActivityWorker.AddScript({
        param($ModulePath, $SharedState)
        . $ModulePath
        while ($SharedState.Active) {
            $nextClickAt = (Get-Date).AddSeconds(5)
            try {
                $screen = Get-WardogsScreen
                $SharedState.LastScreen = $screen.State
                $SharedState.CheckedAt = Get-Date
                if ($screen.State -eq 'Match' -and $SharedState.Active -and [WardogsNative]::ActivityClick($screen.Handle)) {
                    $SharedState.LastClick = Get-Date
                }
            } catch { $SharedState.Error = $_.Exception.Message }
            while ($SharedState.Active -and (Get-Date) -lt $nextClickAt) { Start-Sleep -Milliseconds 100 }
        }
    }).AddArgument((Join-Path $PSScriptRoot 'WardogsSupport.ps1')).AddArgument($script:WardogsActivityState)
    $script:WardogsActivityAsync = $script:WardogsActivityWorker.BeginInvoke()
}

function Stop-WardogsActivity {
    if ($script:WardogsActivityState) { $script:WardogsActivityState.Active = $false }
    if ($script:WardogsActivityWorker) {
        try { $script:WardogsActivityWorker.Stop() } catch { }
        $runspace = $script:WardogsActivityWorker.Runspace
        $script:WardogsActivityWorker.Dispose()
        $runspace.Dispose()
        $script:WardogsActivityWorker = $null
    }
}

function Get-WardogsConnectionState {
    param([object]$Config, [object]$Server)
    $screen = Get-WardogsScreen
    $process = Get-Process -Name 'WardogsClient-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
    $sessionMatches = $script:WardogsSession -and $process -and
        $script:WardogsSession.ProcessId -eq $process.Id -and $script:WardogsSession.JoinCode -eq $Server.joinCode
    $connected = $null
    if (!$sessionMatches -or $screen.State -in @('Closed', 'Disconnected', 'MainMenu', 'Browser', 'BrowserType', 'Start', 'FindServer')) {
        $connected = $false
    } elseif ($screen.State -eq 'Match') {
        $connected = $true
        $script:WardogsSession.LastMatchedAt = Get-Date
    } elseif ($screen.State -eq 'Faction') {
        Select-WardogsFaction -Config $Config
    } elseif ($screen.State -ne 'Background' -and
        ((Get-Date) - $script:WardogsSession.LastMatchedAt).TotalSeconds -gt 180) {
        $connected = $false
    }
    [pscustomobject]@{
        Connected = $connected
        Known = $null -ne $connected
        MatchFound = $sessionMatches
        OnlinePlayerCount = 0
        MatchingStatuses = @($screen.State)
        MatchingNames = @()
        Detail = if ($screen.State -eq 'Background') { 'Activity paused: bring WARDOGS to the front.' } else { "Waiting for WARDOGS match screen ($($screen.State))." }
    }
}
