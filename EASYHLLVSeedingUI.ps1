param(
    [string]$BasePath = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()

$windowSource = @'
using System;
using System.Runtime.InteropServices;

public static class EasyHllvUiWindow
{
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int message, IntPtr wParam, IntPtr lParam);
}
'@
Add-Type -TypeDefinition $windowSource

$enginePath = Join-Path $BasePath "HLLVSeeding.ps1"
$configPath = Join-Path $BasePath "servers.json"
$profilePath = Join-Path $BasePath "player-profile.json"
$statusPath = Join-Path $BasePath "seeder-status.json"
$logPath = Join-Path $BasePath "log.txt"
$launcherPath = Join-Path $BasePath "SeedHLLVServers.bat"
$shortcutIconPath = Join-Path $BasePath "EASY-Seeding-Helper.ico"
$appLogoPath = Join-Path $BasePath "EASY-Seeding-Helper.png"
$script:AppIcon = $null
$script:AppIconBitmap = $null
if (Test-Path -LiteralPath $shortcutIconPath) {
    try { $script:AppIcon = [System.Drawing.Icon]::new($shortcutIconPath) } catch { }
}
if (Test-Path -LiteralPath $appLogoPath) {
    try {
        $sourceLogo = [System.Drawing.Image]::FromFile($appLogoPath)
        $script:AppIconBitmap = [System.Drawing.Bitmap]::new($sourceLogo)
        $sourceLogo.Dispose()
    }
    catch { }
}

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

if (!(Test-Path -LiteralPath $enginePath) -or !(Test-Path -LiteralPath $configPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "The seeding engine or servers.json is missing from this folder.",
        "EASY HLLV Seeding Helper",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$hllvServers = @($config.servers | Where-Object { $_.enabled -ne $false })
$ww2Servers = @($config.hllWw2.servers | Where-Object { $_.enabled -ne $false })
$serverDefinitions = @()
for ($index = 0; $index -lt $hllvServers.Count; $index++) {
    $server = $hllvServers[$index]
    $number = if ("$($server.searchText) $($server.name)" -match "#(\d+)") { $Matches[1] } else { "$($index + 1)" }
    $parts = @("$($server.name)" -split "\s*\|\s*")
    $details = if ($parts.Count -ge 3) { "$($parts[1])  /  $($parts[2])" } else { "$($server.name)" }
    $serverDefinitions += [pscustomobject]@{
        Key = "hllv:$number"
        Number = "$number"
        Label = "HLLV #$number"
        Details = $details
        Server = $server
        GameConfig = $config
        GameId = "hllv"
    }
}
for ($index = 0; $index -lt $ww2Servers.Count; $index++) {
    $server = $ww2Servers[$index]
    $number = if (![string]::IsNullOrWhiteSpace("$($server.number)")) { "$($server.number)" } else { "$($index + 1)" }
    $serverDefinitions += [pscustomobject]@{
        Key = "hllWw2:$number"
        Number = "$number"
        Label = "HLL WW2"
        Details = "NEW PLAYERS WELCOME  /  WARFARE"
        Server = $server
        GameConfig = $config.hllWw2
        GameId = "hllWw2"
    }
}

$colors = @{
    Background = [System.Drawing.Color]::FromArgb(13, 17, 20)
    Surface = [System.Drawing.Color]::FromArgb(24, 30, 34)
    SurfaceAlt = [System.Drawing.Color]::FromArgb(31, 39, 44)
    Border = [System.Drawing.Color]::FromArgb(55, 70, 78)
    Text = [System.Drawing.Color]::FromArgb(241, 247, 249)
    Muted = [System.Drawing.Color]::FromArgb(139, 157, 166)
    Blue = [System.Drawing.Color]::FromArgb(34, 197, 221)
    Cyan = [System.Drawing.Color]::FromArgb(34, 197, 221)
    Green = [System.Drawing.Color]::FromArgb(57, 217, 138)
    Amber = [System.Drawing.Color]::FromArgb(242, 184, 75)
    Red = [System.Drawing.Color]::FromArgb(255, 92, 103)
    ActiveSurface = [System.Drawing.Color]::FromArgb(20, 48, 42)
    WarningSurface = [System.Drawing.Color]::FromArgb(48, 40, 24)
    DangerSurface = [System.Drawing.Color]::FromArgb(49, 27, 31)
    Terminal = [System.Drawing.Color]::FromArgb(8, 12, 14)
}

function New-UiFont {
    param(
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return [System.Drawing.Font]::new("Segoe UI", $Size, $Style)
}

function New-FlatButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [int]$Width = 110
    )

    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.Size = [System.Drawing.Size]::new($Width, 38)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $colors.Border
    $button.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($BackColor, 0.08)
    $button.FlatAppearance.MouseDownBackColor = [System.Windows.Forms.ControlPaint]::Dark($BackColor, 0.08)
    $button.BackColor = $BackColor
    $button.ForeColor = $colors.Text
    $button.Font = New-UiFont -Size 9.5 -Style Bold
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    return $button
}

function Add-TimingSetting {
    param(
        [System.Windows.Forms.Control]$Parent,
        [int]$X,
        [int]$Y,
        [string]$Label,
        [string]$Description,
        [int]$Minimum,
        [int]$Maximum,
        [int]$Value
    )

    $nameLabel = [System.Windows.Forms.Label]::new()
    $nameLabel.Text = $Label
    $nameLabel.Font = New-UiFont -Size 9.5 -Style Bold
    $nameLabel.ForeColor = $colors.Text
    $nameLabel.Location = [System.Drawing.Point]::new($X, $Y)
    $nameLabel.Size = [System.Drawing.Size]::new(275, 20)

    $descriptionLabel = [System.Windows.Forms.Label]::new()
    $descriptionLabel.Text = $Description
    $descriptionLabel.Font = New-UiFont -Size 8.5
    $descriptionLabel.ForeColor = $colors.Muted
    $descriptionLabel.Location = [System.Drawing.Point]::new($X, ($Y + 22))
    $descriptionLabel.Size = [System.Drawing.Size]::new(275, 34)

    $input = [System.Windows.Forms.NumericUpDown]::new()
    $input.Minimum = $Minimum
    $input.Maximum = $Maximum
    $input.Value = [Math]::Min($Maximum, [Math]::Max($Minimum, $Value))
    $input.Increment = 1
    $input.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
    $input.Font = New-UiFont -Size 10
    $input.BackColor = $colors.SurfaceAlt
    $input.ForeColor = $colors.Text
    $input.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $input.Location = [System.Drawing.Point]::new(($X + 282), ($Y + 7))
    $input.Size = [System.Drawing.Size]::new(62, 28)

    $secondsLabel = [System.Windows.Forms.Label]::new()
    $secondsLabel.Text = "sec"
    $secondsLabel.Font = New-UiFont -Size 8.5
    $secondsLabel.ForeColor = $colors.Muted
    $secondsLabel.Location = [System.Drawing.Point]::new(($X + 350), ($Y + 11))
    $secondsLabel.Size = [System.Drawing.Size]::new(32, 18)

    $Parent.Controls.Add($nameLabel)
    $Parent.Controls.Add($descriptionLabel)
    $Parent.Controls.Add($input)
    $Parent.Controls.Add($secondsLabel)
    return $input
}

function New-GameTimingPage {
    param(
        [object]$GameConfig,
        [string]$GameName
    )

    $page = [System.Windows.Forms.Panel]::new()
    $page.Location = [System.Drawing.Point]::new(20, 114)
    $page.Size = [System.Drawing.Size]::new(852, 336)
    $page.BackColor = $colors.Surface
    $page.ForeColor = $colors.Text

    $coreLabel = [System.Windows.Forms.Label]::new()
    $coreLabel.Text = "CORE TIMING"
    $coreLabel.Font = New-UiFont -Size 8.5 -Style Bold
    $coreLabel.ForeColor = $colors.Blue
    $coreLabel.Location = [System.Drawing.Point]::new(18, 12)
    $coreLabel.Size = [System.Drawing.Size]::new(190, 20)

    $joinLabel = [System.Windows.Forms.Label]::new()
    $joinLabel.Text = "JOIN SEQUENCE"
    $joinLabel.Font = New-UiFont -Size 8.5 -Style Bold
    $joinLabel.ForeColor = $colors.Blue
    $joinLabel.Location = [System.Drawing.Point]::new(420, 12)
    $joinLabel.Size = [System.Drawing.Size]::new(190, 20)

    $page.Controls.Add($coreLabel)
    $page.Controls.Add($joinLabel)

    $poll = Add-TimingSetting -Parent $page -X 18 -Y 38 -Label "Server check interval" -Description "How often player counts and your connection are checked." -Minimum 30 -Maximum 300 -Value ([int]$GameConfig.pollSeconds)
    $launch = Add-TimingSetting -Parent $page -X 18 -Y 106 -Label "Game launch wait" -Description "Time allowed for $GameName to finish opening." -Minimum 30 -Maximum 240 -Value ([int]$GameConfig.launchWaitSeconds)
    $close = Add-TimingSetting -Parent $page -X 18 -Y 174 -Label "Game close grace" -Description "Time allowed for $GameName to close normally." -Minimum 5 -Maximum 120 -Value ([int]$GameConfig.closeGraceSeconds)
    $join = Add-TimingSetting -Parent $page -X 18 -Y 242 -Label "Join confirmation wait" -Description "Time allowed after Join before checking the server." -Minimum 15 -Maximum 180 -Value ([int]$GameConfig.uiAutomation.joinWaitSeconds)
    $menu = Add-TimingSetting -Parent $page -X 420 -Y 38 -Label "Main menu ready wait" -Description "Pause before the first click on the $GameName window." -Minimum 5 -Maximum 90 -Value ([int]$GameConfig.uiAutomation.menuReadyWaitSeconds)
    $focus = Add-TimingSetting -Parent $page -X 420 -Y 106 -Label "After focus click wait" -Description "Pause before clicking Enlist after focusing $GameName." -Minimum 5 -Maximum 90 -Value ([int]$GameConfig.uiAutomation.afterFocusClickWaitSeconds)
    $browser = Add-TimingSetting -Parent $page -X 420 -Y 174 -Label "Server browser wait" -Description "Time allowed for the Enlist server list to load." -Minimum 3 -Maximum 90 -Value ([int]$GameConfig.uiAutomation.browserWaitSeconds)
    $search = Add-TimingSetting -Parent $page -X 420 -Y 242 -Label "Search results wait" -Description "Pause after entering the EASY server name." -Minimum 2 -Maximum 60 -Value ([int]$GameConfig.uiAutomation.searchWaitSeconds)

    return [pscustomobject]@{
        Panel = $page
        Poll = $poll
        Launch = $launch
        Close = $close
        Join = $join
        Menu = $menu
        Focus = $focus
        Browser = $browser
        Search = $search
        Inputs = @($poll, $launch, $close, $join, $menu, $focus, $browser, $search)
    }
}

function Read-PlayerName {
    if (!(Test-Path -LiteralPath $profilePath)) {
        return ""
    }

    try {
        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        return "$($profile.playerName)".Trim()
    } catch {
        return ""
    }
}

function Save-PlayerProfile {
    param([string]$PlayerName)

    $created = (Get-Date).ToString("s")
    if (Test-Path -LiteralPath $profilePath) {
        try {
            $existingProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
            if ($existingProfile.created) {
                $created = "$($existingProfile.created)"
            }
        } catch {
        }
    }

    $profile = [ordered]@{
        playerName = $PlayerName
        created = $created
        updated = (Get-Date).ToString("s")
    }
    Write-JsonFileSafely -Value $profile -Path $profilePath -Depth 4
}

function Get-DesktopShortcutPath {
    Join-Path ([Environment]::GetFolderPath("Desktop")) "EASY Seeding Helper.lnk"
}

function New-DesktopShortcut {
    if (!(Test-Path -LiteralPath $launcherPath)) {
        throw "The seeding helper launcher is missing from $BasePath."
    }

    $shortcutPath = Get-DesktopShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcherPath
    $shortcut.WorkingDirectory = $BasePath
    if (Test-Path -LiteralPath $shortcutIconPath) {
        $shortcut.IconLocation = "$shortcutIconPath,0"
    }
    $shortcut.Description = "Seed EASY HLLV and HLL WW2 servers"
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    return $shortcutPath
}

function Show-PlayerNameDialog {
    param([string]$CurrentName = "")

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = "Steam name setup"
    $dialog.ClientSize = [System.Drawing.Size]::new(470, 220)
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.BackColor = $colors.Background
    $dialog.ForeColor = $colors.Text
    if ($script:AppIcon) { $dialog.Icon = $script:AppIcon }

    $dialogAccent = [System.Windows.Forms.Panel]::new()
    $dialogAccent.Location = [System.Drawing.Point]::new(0, 0)
    $dialogAccent.Size = [System.Drawing.Size]::new(470, 3)
    $dialogAccent.BackColor = $colors.Cyan

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = "Enter your Steam name"
    $title.Font = New-UiFont -Size 15 -Style Bold
    $title.ForeColor = $colors.Cyan
    $title.Location = [System.Drawing.Point]::new(24, 20)
    $title.Size = [System.Drawing.Size]::new(420, 28)

    $instructions = [System.Windows.Forms.Label]::new()
    $instructions.Text = "Type it letter-for-letter exactly as it appears in EASY stats. Capital letters, spaces, punctuation, and numbers must match."
    $instructions.Font = New-UiFont -Size 9.5
    $instructions.ForeColor = $colors.Muted
    $instructions.Location = [System.Drawing.Point]::new(24, 55)
    $instructions.Size = [System.Drawing.Size]::new(420, 42)

    $nameBox = [System.Windows.Forms.TextBox]::new()
    $nameBox.Text = $CurrentName
    $nameBox.Font = New-UiFont -Size 11
    $nameBox.Location = [System.Drawing.Point]::new(24, 108)
    $nameBox.Size = [System.Drawing.Size]::new(420, 28)
    $nameBox.MaxLength = 64
    $nameBox.BackColor = $colors.SurfaceAlt
    $nameBox.ForeColor = $colors.Text
    $nameBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $saveButton = New-FlatButton -Text "Save" -BackColor $colors.Green -Width 100
    $saveButton.Location = [System.Drawing.Point]::new(344, 160)

    $cancelButton = New-FlatButton -Text "Cancel" -BackColor $colors.SurfaceAlt -Width 100
    $cancelButton.Location = [System.Drawing.Point]::new(234, 160)

    $saveButton.Add_Click({
        $value = $nameBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            [System.Windows.Forms.MessageBox]::Show(
                $dialog,
                "Your Steam name is required so the helper can confirm that you joined the server.",
                "Steam name required",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $nameBox.Focus()
            return
        }

        try {
            Save-PlayerProfile -PlayerName $value
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $dialog,
                "Your Steam name could not be saved.`r`n`r`n$($_.Exception.Message)",
                "Steam name could not be saved",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        $dialog.Tag = $value
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $cancelButton.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialog.AcceptButton = $saveButton
    $dialog.CancelButton = $cancelButton
    $dialog.Controls.Add($title)
    $dialog.Controls.Add($instructions)
    $dialog.Controls.Add($nameBox)
    $dialog.Controls.Add($saveButton)
    $dialog.Controls.Add($cancelButton)
    $dialog.Controls.Add($dialogAccent)
    $dialog.Add_Shown({
        $nameBox.Focus()
        $nameBox.SelectAll()
    })

    $result = $dialog.ShowDialog($form)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return "$($dialog.Tag)"
    }

    return ""
}

function Show-WelcomeDialog {
    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = "Welcome to EASY Seeding Helper"
    $dialog.ClientSize = [System.Drawing.Size]::new(600, 390)
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.BackColor = $colors.Background
    $dialog.ForeColor = $colors.Text
    if ($script:AppIcon) { $dialog.Icon = $script:AppIcon }

    $header = [System.Windows.Forms.Panel]::new()
    $header.Location = [System.Drawing.Point]::new(0, 0)
    $header.Size = [System.Drawing.Size]::new(600, 94)
    $header.BackColor = $colors.Surface

    $headerAccent = [System.Windows.Forms.Panel]::new()
    $headerAccent.Location = [System.Drawing.Point]::new(0, 92)
    $headerAccent.Size = [System.Drawing.Size]::new(600, 2)
    $headerAccent.BackColor = $colors.Cyan

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = "Welcome to EASY Seeding Helper"
    $title.Font = New-UiFont -Size 19 -Style Bold
    $title.ForeColor = $colors.Text
    $title.Location = [System.Drawing.Point]::new(28, 16)
    $title.Size = [System.Drawing.Size]::new(540, 36)

    $subtitle = [System.Windows.Forms.Label]::new()
    $subtitle.Text = "Complete this one-time setup before your first seeding run."
    $subtitle.Font = New-UiFont -Size 9.5
    $subtitle.ForeColor = $colors.Muted
    $subtitle.Location = [System.Drawing.Point]::new(31, 56)
    $subtitle.Size = [System.Drawing.Size]::new(530, 22)

    $header.Controls.Add($title)
    $header.Controls.Add($subtitle)
    $header.Controls.Add($headerAccent)

    $nameLabel = [System.Windows.Forms.Label]::new()
    $nameLabel.Text = "STEAM NAME"
    $nameLabel.Font = New-UiFont -Size 8.5 -Style Bold
    $nameLabel.ForeColor = $colors.Blue
    $nameLabel.Location = [System.Drawing.Point]::new(30, 116)
    $nameLabel.Size = [System.Drawing.Size]::new(180, 20)

    $nameBox = [System.Windows.Forms.TextBox]::new()
    $nameBox.Font = New-UiFont -Size 11
    $nameBox.Location = [System.Drawing.Point]::new(30, 140)
    $nameBox.Size = [System.Drawing.Size]::new(540, 29)
    $nameBox.MaxLength = 64
    $nameBox.BackColor = $colors.SurfaceAlt
    $nameBox.ForeColor = $colors.Text
    $nameBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $nameHelp = [System.Windows.Forms.Label]::new()
    $nameHelp.Text = "Enter it letter-for-letter exactly as it appears in EASY stats. Capital letters, spaces, punctuation, and numbers must match."
    $nameHelp.Font = New-UiFont -Size 9
    $nameHelp.ForeColor = $colors.Muted
    $nameHelp.Location = [System.Drawing.Point]::new(31, 179)
    $nameHelp.Size = [System.Drawing.Size]::new(535, 42)

    $shortcutCheckBox = [System.Windows.Forms.CheckBox]::new()
    $shortcutCheckBox.Text = "Create an EASY Seeding Helper shortcut on my Desktop"
    $shortcutCheckBox.Checked = $true
    $shortcutCheckBox.Font = New-UiFont -Size 10 -Style Bold
    $shortcutCheckBox.ForeColor = $colors.Text
    $shortcutCheckBox.BackColor = $colors.Background
    $shortcutCheckBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $shortcutCheckBox.Location = [System.Drawing.Point]::new(30, 240)
    $shortcutCheckBox.Size = [System.Drawing.Size]::new(520, 28)

    $shortcutHelp = [System.Windows.Forms.Label]::new()
    $shortcutHelp.Text = "The shortcut opens this helper directly. You can create it later from Settings."
    $shortcutHelp.Font = New-UiFont -Size 9
    $shortcutHelp.ForeColor = $colors.Muted
    $shortcutHelp.Location = [System.Drawing.Point]::new(53, 272)
    $shortcutHelp.Size = [System.Drawing.Size]::new(500, 22)

    $exitButton = New-FlatButton -Text "Exit" -BackColor $colors.SurfaceAlt -Width 100
    $exitButton.Location = [System.Drawing.Point]::new(330, 324)

    $continueButton = New-FlatButton -Text "Get Started" -BackColor $colors.Green -Width 130
    $continueButton.Location = [System.Drawing.Point]::new(440, 324)

    $continueButton.Add_Click({
        $value = $nameBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            [System.Windows.Forms.MessageBox]::Show(
                $dialog,
                "Enter your Steam name letter-for-letter before continuing.",
                "Steam name required",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $nameBox.Focus()
            return
        }

        try {
            Save-PlayerProfile -PlayerName $value
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $dialog,
                "Your Steam name could not be saved.`r`n`r`n$($_.Exception.Message)",
                "Setup could not be completed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        if ($shortcutCheckBox.Checked) {
            try {
                New-DesktopShortcut | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    $dialog,
                    "Your Steam name was saved, but the Desktop shortcut could not be created.`r`n`r`n$($_.Exception.Message)",
                    "Shortcut could not be created",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        }

        $dialog.Tag = $value
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $exitButton.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialog.AcceptButton = $continueButton
    $dialog.CancelButton = $exitButton
    $dialog.Controls.Add($header)
    $dialog.Controls.Add($nameLabel)
    $dialog.Controls.Add($nameBox)
    $dialog.Controls.Add($nameHelp)
    $dialog.Controls.Add($shortcutCheckBox)
    $dialog.Controls.Add($shortcutHelp)
    $dialog.Controls.Add($exitButton)
    $dialog.Controls.Add($continueButton)
    $dialog.Add_Shown({ $nameBox.Focus() })

    $result = $dialog.ShowDialog($form)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return "$($dialog.Tag)"
    }
    return ""
}

function Find-SeederProcess {
    try {
        $match = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -match "powershell|pwsh" -and
            $_.CommandLine -match '[\\/]HLLVSeeding\.ps1(?:"|\s)' -and
            $_.CommandLine -notmatch "-Setup"
        } | Select-Object -First 1

        if ($match) {
            return [System.Diagnostics.Process]::GetProcessById([int]$match.ProcessId)
        }
    } catch {
    }

    return $null
}

function Add-Activity {
    param(
        [string]$Message,
        [string]$Timestamp = ""
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $displayTime = Get-Date
    if (![string]::IsNullOrWhiteSpace($Timestamp)) {
        try { $displayTime = [DateTime]::Parse($Timestamp).ToLocalTime() } catch { }
    }

    $line = "[{0}] {1}" -f $displayTime.ToString("HH:mm:ss"), $Message
    $activityBox.AppendText("$line`r`n")

    $lines = $activityBox.Lines
    if ($lines.Count -gt 80) {
        $activityBox.Lines = @($lines | Select-Object -Last 80)
    }

    $activityBox.SelectionStart = $activityBox.TextLength
    $activityBox.ScrollToCaret()
}

function Set-UiRunningState {
    param([bool]$Running)

    $hasSelectedGame = $hllvGameCheckBox.Checked -or $ww2GameCheckBox.Checked
    $startButton.Enabled = !$Running -and $hasSelectedGame
    $stopButton.Enabled = $Running
    $editPlayerButton.Enabled = !$Running
    if ($hllvGameCheckBox) { $hllvGameCheckBox.Enabled = !$Running }
    if ($ww2GameCheckBox) { $ww2GameCheckBox.Enabled = !$Running }
    if ($script:TimingInputs) {
        foreach ($input in $script:TimingInputs) {
            $input.Enabled = !$Running
        }
    }
    if ($saveSettingsButton) { $saveSettingsButton.Enabled = !$Running }
    if ($restoreTimingButton) { $restoreTimingButton.Enabled = !$Running }
    if ($settingsLockLabel) { $settingsLockLabel.Visible = $Running }

    if ($Running) {
        $runStateLabel.Text = "SYSTEM // RUNNING"
        $runStateLabel.ForeColor = $colors.Green
        $statusAccentPanel.BackColor = $colors.Green
        $statusTopRail.BackColor = $colors.Green
        $startButton.BackColor = $colors.SurfaceAlt
        $startButton.ForeColor = $colors.Muted
        $stopButton.BackColor = $colors.Red
        $stopButton.ForeColor = $colors.Text
    } else {
        $runStateLabel.Text = "SYSTEM // STOPPED"
        $runStateLabel.ForeColor = $colors.Red
        $statusAccentPanel.BackColor = $colors.Red
        $statusTopRail.BackColor = $colors.Red
        $startButton.BackColor = if ($hasSelectedGame) { $colors.Green } else { $colors.SurfaceAlt }
        $startButton.ForeColor = if ($hasSelectedGame) { $colors.Text } else { $colors.Muted }
        $stopButton.BackColor = $colors.SurfaceAlt
        $stopButton.ForeColor = $colors.Muted
    }
}

function Update-SystemIndicators {
    param([switch]$Force)

    $now = Get-Date
    if (!$Force -and $script:NextSystemIndicatorUpdate -and $now -lt $script:NextSystemIndicatorUpdate) {
        return
    }
    $script:NextSystemIndicatorUpdate = $now.AddSeconds(5)

    $steamOnline = [bool](Get-Process -Name "Steam" -ErrorAction SilentlyContinue | Select-Object -First 1)
    $steamIndicatorLabel.Text = if ($steamOnline) { "STEAM // ONLINE" } else { "STEAM // OFFLINE" }
    $steamIndicatorLabel.ForeColor = if ($steamOnline) { $colors.Green } else { $colors.Red }

    if ($script:LiveRefreshRequests.Count -gt 0) {
        $statsIndicatorLabel.Text = "STATS // SYNCING"
        $statsIndicatorLabel.ForeColor = $colors.Cyan
    } elseif ($script:LastStatsUpdate -and ($now - $script:LastStatsUpdate).TotalSeconds -le [Math]::Max(120, ([int]$config.pollSeconds * 2))) {
        $statsIndicatorLabel.Text = "STATS // LIVE"
        $statsIndicatorLabel.ForeColor = $colors.Green
    } else {
        $statsIndicatorLabel.Text = "STATS // WAITING"
        $statsIndicatorLabel.ForeColor = $colors.Muted
    }
}

function Set-ServerRowVisual {
    param(
        [object]$Row,
        [string]$State,
        [int]$Players = 0,
        [int]$MaxPlayers = 100
    )

    $safeMaximum = [Math]::Max(1, $MaxPlayers)
    $fillWidth = [Math]::Min($Row.ProgressTrack.Width, [Math]::Max(0, [int][Math]::Round(($Players / $safeMaximum) * $Row.ProgressTrack.Width)))
    $Row.ProgressFill.Width = $fillWidth
    $Row.RowPanel.BackColor = $Row.BaseBackColor

    switch ($State) {
        "ACTIVE SEED" {
            $accent = $colors.Green
            $Row.RowPanel.BackColor = $colors.ActiveSurface
        }
        "UNDER 50" {
            $accent = $colors.Amber
            $Row.RowPanel.BackColor = $colors.WarningSurface
        }
        "DOWN" {
            $accent = $colors.Red
            $Row.RowPanel.BackColor = $colors.DangerSurface
        }
        "UNAVAILABLE" {
            $accent = $colors.Red
            $Row.RowPanel.BackColor = $colors.DangerSurface
        }
        "DISABLED" { $accent = $colors.Muted }
        "NOT SEEDING" { $accent = $colors.Cyan }
        default { $accent = $colors.Muted }
    }

    $Row.StatusRail.BackColor = $accent
    $Row.ProgressFill.BackColor = $accent
    $Row.State.ForeColor = $accent
}

function Update-GameSelectionPresentation {
    param([switch]$UpdateReadyMessage)

    $selectedGames = @()
    if ($hllvGameCheckBox.Checked) { $selectedGames += "HLLV" }
    if ($ww2GameCheckBox.Checked) { $selectedGames += "HLL WW2" }

    $selectionText = if ($selectedGames.Count -gt 0) { $selectedGames -join " -> " } else { "No games selected" }
    $behaviorLabel.Text = "Selected: $selectionText  |  Stops at $($config.seededAtPlayers)/$($config.maxPlayers)"
    $serversTitle.Text = if ($hllvGameCheckBox.Checked -and $ww2GameCheckBox.Checked) {
        "EASY SERVERS  |  HLLV PRIORITY"
    } elseif ($hllvGameCheckBox.Checked) {
        "EASY SERVERS  |  HLLV"
    } elseif ($ww2GameCheckBox.Checked) {
        "EASY SERVERS  |  HLL WW2"
    } else {
        "EASY SERVERS"
    }

    if ($script:ServerRows) {
        foreach ($key in @($script:ServerRows.Keys)) {
            $gameDisabled = ($key -like "hllv:*" -and !$hllvGameCheckBox.Checked) -or
                ($key -like "hllWw2:*" -and !$ww2GameCheckBox.Checked)
            $row = $script:ServerRows[$key]
            if ($gameDisabled) {
                $row.State.Text = "DISABLED"
                $players = if ($row.Players.Text -match '^(\d+)/') { [int]$Matches[1] } else { 0 }
                Set-ServerRowVisual -Row $row -State "DISABLED" -Players $players
            } elseif ($row.State.Text -eq "DISABLED") {
                $row.State.Text = "WAITING"
                Set-ServerRowVisual -Row $row -State "WAITING"
            }
        }
    }

    if (!(Test-SeederRunning)) {
        $startButton.Enabled = $selectedGames.Count -gt 0
        $startButton.BackColor = if ($selectedGames.Count -gt 0) { $colors.Green } else { $colors.SurfaceAlt }
        $startButton.ForeColor = if ($selectedGames.Count -gt 0) { $colors.Text } else { $colors.Muted }
        if ($selectedGames.Count -eq 0) {
            $mainStatusLabel.Text = "Choose a game to seed"
            $statusDetailLabel.Text = "Select HLLV, HLL WW2, or both"
        } elseif ($UpdateReadyMessage) {
            $mainStatusLabel.Text = "Ready to seed"
            $statusDetailLabel.Text = "Selected: $selectionText"
        }
    }
}

function Reset-ServerRows {
    foreach ($row in $script:ServerRows.Values) {
        $row.Players.Text = "--/100"
        $row.State.Text = "WAITING"
        Set-ServerRowVisual -Row $row -State "WAITING"
    }
}

function Update-ServerRows {
    param([object[]]$Statuses)

    foreach ($status in @($Statuses)) {
        $key = if (![string]::IsNullOrWhiteSpace("$($status.key)")) { "$($status.key)" } else { "hllv:$($status.number)" }
        if (!$script:ServerRows.Contains($key)) {
            continue
        }

        $row = $script:ServerRows[$key]
        $gameDisabled = ($key -like "hllv:*" -and !$hllvGameCheckBox.Checked) -or
            ($key -like "hllWw2:*" -and !$ww2GameCheckBox.Checked)
        $stateText = if ($gameDisabled) { "DISABLED" } else { "$($status.state)" }
        $row.Players.Text = if ($stateText -in @("DOWN", "UNAVAILABLE")) { "--/$($status.maxPlayers)" } else { "$($status.players)/$($status.maxPlayers)" }
        $row.State.Text = $stateText
        Set-ServerRowVisual -Row $row -State $stateText -Players ([int]$status.players) -MaxPlayers ([int]$status.maxPlayers)
    }
}

function Test-SeederRunning {
    if (!$script:SeederProcess) {
        return $false
    }

    try {
        return !$script:SeederProcess.HasExited
    } catch {
        return $false
    }
}

function Start-LiveServerRefresh {
    if ((Test-SeederRunning) -or $script:LiveRefreshRequests.Count -gt 0) {
        return
    }

    $requests = @()
    for ($index = 0; $index -lt $serverDefinitions.Count; $index++) {
        $definition = $serverDefinitions[$index]
        $server = $definition.Server
        if ([string]::IsNullOrWhiteSpace("$($server.easyStatsUrl)")) {
            continue
        }

        $uri = "$($server.easyStatsUrl.TrimEnd('/'))/api/get_public_info"
        $requests += [pscustomobject]@{
            Key = "$($definition.Key)"
            Label = "$($definition.Label)"
            GameId = "$($definition.GameId)"
            GameConfig = $definition.GameConfig
            Task = $script:StatsHttpClient.GetStringAsync($uri)
        }
    }

    $script:LiveRefreshRequests = @($requests)
    $script:NextLiveRefresh = (Get-Date).AddSeconds([int]$config.pollSeconds)
    $countdownLabel.Text = "Refreshing live server data..."
}

function Complete-LiveServerRefresh {
    if ($script:LiveRefreshRequests.Count -eq 0) {
        return
    }

    $unfinished = @($script:LiveRefreshRequests | Where-Object { !$_.Task.IsCompleted })
    if ($unfinished.Count -gt 0) {
        return
    }

    if (Test-SeederRunning) {
        $script:LiveRefreshRequests = @()
        return
    }

    $statuses = @()
    $failedNumbers = @()
    foreach ($request in @($script:LiveRefreshRequests)) {
        try {
            $responseText = $request.Task.GetAwaiter().GetResult()
            $response = $responseText | ConvertFrom-Json
            $players = 0
            $playerCountValue = $response.result.player_count
            if ($null -eq $playerCountValue -or
                ![int]::TryParse("$playerCountValue", [ref]$players) -or
                $players -lt 0) {
                throw "The stats page returned no valid player count."
            }
            $gameConfig = $request.GameConfig
            $gameEnabled = if ($request.GameId -eq "hllv") { [bool]$hllvGameCheckBox.Checked } else { [bool]$ww2GameCheckBox.Checked }
            $isUnderThreshold = $players -lt [int]$gameConfig.seedBelowPlayers
            $state = if (!$gameEnabled) {
                "DISABLED"
            } elseif ($players -gt [int]$gameConfig.activeSeedPlayers -and $isUnderThreshold) {
                "ACTIVE SEED"
            } elseif ($isUnderThreshold) {
                "UNDER 50"
            } else {
                "NOT SEEDING"
            }

            $statuses += [pscustomobject]@{
                key = "$($request.Key)"
                players = $players
                maxPlayers = [int]$gameConfig.maxPlayers
                state = $state
            }
        } catch {
            $gameEnabled = if ($request.GameId -eq "hllv") { [bool]$hllvGameCheckBox.Checked } else { [bool]$ww2GameCheckBox.Checked }
            if ($gameEnabled) {
                $failedNumbers += "$($request.Label)"
            }
            $key = "$($request.Key)"
            if ($script:ServerRows.Contains($key)) {
                $row = $script:ServerRows[$key]
                $row.Players.Text = "--/$($request.GameConfig.maxPlayers)"
                $row.State.Text = if ($gameEnabled) { "DOWN" } else { "DISABLED" }
                Set-ServerRowVisual -Row $row -State $row.State.Text -MaxPlayers ([int]$request.GameConfig.maxPlayers)
            }
        }
    }

    Update-ServerRows -Statuses $statuses
    $script:LiveRefreshRequests = @()
    $script:LastLiveRefresh = Get-Date
    if ($statuses.Count -gt 0) { $script:LastStatsUpdate = $script:LastLiveRefresh }
    $mainStatusLabel.Text = "Ready to seed"
    $statusDetailLabel.Text = "Live server data updated $($script:LastLiveRefresh.ToString('h:mm:ss tt'))"

    if ($failedNumbers.Count -eq 0) {
        Add-Activity -Message "Live server list refreshed."
    } else {
        $mainStatusLabel.Text = "Some servers are down"
        $statusDetailLabel.Text = "$($failedNumbers -join ', ') will be skipped and checked again"
        Add-Activity -Message "Live refresh completed. $($failedNumbers -join ', ') DOWN and skipped."
    }
    Update-GameSelectionPresentation
}

function Update-FromStatusFile {
    if (!(Test-Path -LiteralPath $statusPath)) {
        return
    }

    try {
        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    } catch {
        return
    }

    if ($status.updatedAt -and "$($status.updatedAt)" -eq $script:LastStatusStamp) {
        return
    }

    $script:LastStatusStamp = "$($status.updatedAt)"
    if ($status.message) {
        $mainStatusLabel.Text = "$($status.message)"
    }

    if ($status.playerName) {
        $playerValueLabel.Text = "$($status.playerName)"
    }

    if ($status.updatedAt) {
        try {
            $updated = [DateTime]::Parse("$($status.updatedAt)").ToLocalTime()
            $script:LastStatsUpdate = $updated
            $statusDetailLabel.Text = "Last update $($updated.ToString('h:mm:ss tt'))"
        } catch {
        }
    }

    Update-ServerRows -Statuses @($status.servers)

    if ($status.running -eq $false) {
        $countdownLabel.Text = "Not running"
    } elseif ([int]$status.nextCheckSeconds -ge 0) {
        $countdownLabel.Text = "Next server check in $($status.nextCheckSeconds) seconds"
    } else {
        $countdownLabel.Text = "Server check in progress"
    }

    if ($status.events) {
        foreach ($event in @($status.events)) {
            $eventKey = "$($event.timestamp)|$($event.message)"
            if (!$script:SeenStatusEvents.Contains($eventKey)) {
                $script:SeenStatusEvents[$eventKey] = $true
                Add-Activity -Message "$($event.message)" -Timestamp "$($event.timestamp)"
            }
        }
    } elseif ($status.lastLog -and "$($status.lastLog)" -ne $script:LastActivityMessage) {
        $script:LastActivityMessage = "$($status.lastLog)"
        Add-Activity -Message $script:LastActivityMessage
    }
}

function Save-GameSelection {
    $config.enabledGames.hllv = [bool]$hllvGameCheckBox.Checked
    $config.enabledGames.hllWw2 = [bool]$ww2GameCheckBox.Checked
    Write-JsonFileSafely -Value $config -Path $configPath -Depth 12
}

function Start-Seeder {
    if (!$hllvGameCheckBox.Checked -and !$ww2GameCheckBox.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Select at least one game to seed.",
            "No game selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    try {
        Save-GameSelection
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "The selected games could not be saved.`r`n`r`n$($_.Exception.Message)",
            "Could not save game selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $playerName = Read-PlayerName
    if ([string]::IsNullOrWhiteSpace($playerName)) {
        $playerName = Show-PlayerNameDialog
        if ([string]::IsNullOrWhiteSpace($playerName)) {
            return
        }
    }

    $playerValueLabel.Text = $playerName
    $existing = Find-SeederProcess
    if ($existing) {
        $script:SeederProcess = $existing
        Set-UiRunningState -Running $true
        Add-Activity -Message "Connected to the seeder that is already running."
        return
    }

    if (Test-Path -LiteralPath $statusPath) {
        Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = Join-Path $env:SystemRoot "System32\conhost.exe"
        $startInfo.Arguments = "--headless Powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File `"$enginePath`" -ConfigPath `"$configPath`" -BasePath `"$BasePath`" -UiMode"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $headlessHost = [System.Diagnostics.Process]::Start($startInfo)

        for ($attempt = 0; $attempt -lt 50; $attempt++) {
            Start-Sleep -Milliseconds 200
            $script:SeederProcess = Find-SeederProcess
            if ($script:SeederProcess) {
                break
            }
        }

        if (!$script:SeederProcess) {
            if ($headlessHost -and !$headlessHost.HasExited) {
                $headlessHost.Kill()
            }
            throw "The headless seeding engine did not start."
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "The seeder could not start.`r`n`r`n$($_.Exception.Message)",
            "Could not start seeder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $script:LastStatusStamp = ""
    $script:LiveRefreshRequests = @()
    $mainStatusLabel.Text = "Starting server checks..."
    $statusDetailLabel.Text = "Launching the seeding engine"
    $countdownLabel.Text = "Server check in progress"
    Set-UiRunningState -Running $true
    $selectedGames = @()
    if ($hllvGameCheckBox.Checked) { $selectedGames += "HLLV" }
    if ($ww2GameCheckBox.Checked) { $selectedGames += "HLL WW2" }
    Add-Activity -Message "Seeder started for ${playerName}: $($selectedGames -join ' -> ')."
}

function Stop-Seeder {
    if ($script:SeederProcess) {
        try {
            if (!$script:SeederProcess.HasExited) {
                Stop-Process -Id $script:SeederProcess.Id -Force -ErrorAction Stop
                $script:SeederProcess.WaitForExit(3000) | Out-Null
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "The seeder process could not be stopped.`r`n`r`n$($_.Exception.Message)",
                "Could not stop seeder",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
    }

    $script:SeederProcess = $null
    if (Test-Path -LiteralPath $statusPath) {
        Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    }

    $script:LastStatusStamp = ""
    $mainStatusLabel.Text = "Seeder stopped"
    $statusDetailLabel.Text = "Any running game was left open"
    $countdownLabel.Text = "Not running"
    Reset-ServerRows
    Set-UiRunningState -Running $false
    Add-Activity -Message "Seeder stopped. Any running game was left open."
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = "EASY Seeding Helper v2.3.4"
$form.Icon = $script:AppIcon
$form.ClientSize = [System.Drawing.Size]::new(900, 686)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.MaximizeBox = $false
$form.BackColor = $colors.Border
$form.ForeColor = $colors.Text
$form.Font = New-UiFont -Size 9.5
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$titleBarPanel = [System.Windows.Forms.Panel]::new()
$titleBarPanel.Location = [System.Drawing.Point]::new(1, 1)
$titleBarPanel.Size = [System.Drawing.Size]::new(898, 35)
$titleBarPanel.BackColor = $colors.Background

$titleIconBox = [System.Windows.Forms.PictureBox]::new()
$titleIconBox.Location = [System.Drawing.Point]::new(12, 8)
$titleIconBox.Size = [System.Drawing.Size]::new(18, 18)
$titleIconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
if ($script:AppIconBitmap) {
    $titleIconBox.Image = $script:AppIconBitmap
}

$titleTextLabel = [System.Windows.Forms.Label]::new()
$titleTextLabel.Text = "EASY SEEDING HELPER  //  v2.3.4"
$titleTextLabel.Font = New-UiFont -Size 8.5 -Style Bold
$titleTextLabel.ForeColor = $colors.Muted
$titleTextLabel.Location = [System.Drawing.Point]::new(40, 9)
$titleTextLabel.Size = [System.Drawing.Size]::new(360, 20)

$minimizeButton = New-FlatButton -Text "-" -BackColor $colors.Background -Width 42
$minimizeButton.Location = [System.Drawing.Point]::new(814, 0)
$minimizeButton.Size = [System.Drawing.Size]::new(42, 35)
$minimizeButton.FlatAppearance.BorderSize = 0
$minimizeButton.Font = New-UiFont -Size 12 -Style Bold

$closeButton = New-FlatButton -Text "X" -BackColor $colors.Background -Width 42
$closeButton.Location = [System.Drawing.Point]::new(856, 0)
$closeButton.Size = [System.Drawing.Size]::new(42, 35)
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.FlatAppearance.MouseOverBackColor = $colors.Red

$dragWindow = {
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [EasyHllvUiWindow]::ReleaseCapture() | Out-Null
        [EasyHllvUiWindow]::SendMessage($form.Handle, 0x00A1, [IntPtr]2, [IntPtr]::Zero) | Out-Null
    }
}
$titleBarPanel.Add_MouseDown($dragWindow)
$titleTextLabel.Add_MouseDown($dragWindow)
$titleIconBox.Add_MouseDown($dragWindow)
$minimizeButton.Add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$closeButton.Add_Click({ $form.Close() })

$titleBarPanel.Controls.Add($titleIconBox)
$titleBarPanel.Controls.Add($titleTextLabel)
$titleBarPanel.Controls.Add($minimizeButton)
$titleBarPanel.Controls.Add($closeButton)

$headerPanel = [System.Windows.Forms.Panel]::new()
$headerPanel.Location = [System.Drawing.Point]::new(1, 36)
$headerPanel.Size = [System.Drawing.Size]::new(898, 86)
$headerPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.BackColor = $colors.Surface

$brandLabel = [System.Windows.Forms.Label]::new()
$brandLabel.Text = "EASY SEEDING CONTROL"
$brandLabel.Font = New-UiFont -Size 18 -Style Bold
$brandLabel.ForeColor = $colors.Text
$brandLabel.Location = [System.Drawing.Point]::new(24, 14)
$brandLabel.Size = [System.Drawing.Size]::new(305, 36)

$versionLabel = [System.Windows.Forms.Label]::new()
$versionLabel.Text = "AUTOMATED SERVER OPERATIONS"
$versionLabel.Font = New-UiFont -Size 8.5 -Style Bold
$versionLabel.ForeColor = $colors.Muted
$versionLabel.Location = [System.Drawing.Point]::new(27, 53)
$versionLabel.Size = [System.Drawing.Size]::new(300, 22)

$systemCaptionLabel = [System.Windows.Forms.Label]::new()
$systemCaptionLabel.Text = "SYSTEM STATUS"
$systemCaptionLabel.Font = New-UiFont -Size 7.5 -Style Bold
$systemCaptionLabel.ForeColor = $colors.Muted
$systemCaptionLabel.Location = [System.Drawing.Point]::new(330, 13)
$systemCaptionLabel.Size = [System.Drawing.Size]::new(180, 18)

$steamIndicatorLabel = [System.Windows.Forms.Label]::new()
$steamIndicatorLabel.Text = "STEAM // CHECKING"
$steamIndicatorLabel.Font = New-UiFont -Size 8 -Style Bold
$steamIndicatorLabel.ForeColor = $colors.Muted
$steamIndicatorLabel.Location = [System.Drawing.Point]::new(330, 37)
$steamIndicatorLabel.Size = [System.Drawing.Size]::new(118, 20)

$statsIndicatorLabel = [System.Windows.Forms.Label]::new()
$statsIndicatorLabel.Text = "STATS // WAITING"
$statsIndicatorLabel.Font = New-UiFont -Size 8 -Style Bold
$statsIndicatorLabel.ForeColor = $colors.Muted
$statsIndicatorLabel.Location = [System.Drawing.Point]::new(450, 37)
$statsIndicatorLabel.Size = [System.Drawing.Size]::new(120, 20)

$playerCaptionLabel = [System.Windows.Forms.Label]::new()
$playerCaptionLabel.Text = "STEAM NAME"
$playerCaptionLabel.Font = New-UiFont -Size 8 -Style Bold
$playerCaptionLabel.ForeColor = $colors.Muted
$playerCaptionLabel.Location = [System.Drawing.Point]::new(575, 14)
$playerCaptionLabel.Size = [System.Drawing.Size]::new(160, 18)
$playerCaptionLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$playerValueLabel = [System.Windows.Forms.Label]::new()
$playerValueLabel.Text = Read-PlayerName
$playerValueLabel.Font = New-UiFont -Size 11 -Style Bold
$playerValueLabel.ForeColor = $colors.Text
$playerValueLabel.Location = [System.Drawing.Point]::new(575, 35)
$playerValueLabel.Size = [System.Drawing.Size]::new(205, 28)
$playerValueLabel.AutoEllipsis = $true
$playerValueLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$editPlayerButton = New-FlatButton -Text "Edit" -BackColor $colors.SurfaceAlt -Width 76
$editPlayerButton.Location = [System.Drawing.Point]::new(800, 25)
$editPlayerButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$headerPanel.Controls.Add($brandLabel)
$headerPanel.Controls.Add($versionLabel)
$headerPanel.Controls.Add($systemCaptionLabel)
$headerPanel.Controls.Add($steamIndicatorLabel)
$headerPanel.Controls.Add($statsIndicatorLabel)
$headerPanel.Controls.Add($playerCaptionLabel)
$headerPanel.Controls.Add($playerValueLabel)
$headerPanel.Controls.Add($editPlayerButton)

$mainNavPanel = [System.Windows.Forms.Panel]::new()
$mainNavPanel.Location = [System.Drawing.Point]::new(1, 122)
$mainNavPanel.Size = [System.Drawing.Size]::new(898, 32)
$mainNavPanel.BackColor = $colors.Background

$hllvNavButton = New-FlatButton -Text "Seeder" -BackColor $colors.SurfaceAlt -Width 150
$hllvNavButton.Location = [System.Drawing.Point]::new(0, 0)
$hllvNavButton.Size = [System.Drawing.Size]::new(150, 32)
$hllvNavButton.ForeColor = $colors.Text

$settingsNavButton = New-FlatButton -Text "Settings" -BackColor $colors.Background -Width 150
$settingsNavButton.Location = [System.Drawing.Point]::new(150, 0)
$settingsNavButton.Size = [System.Drawing.Size]::new(150, 32)
$settingsNavButton.ForeColor = $colors.Muted

$mainNavPanel.Controls.Add($hllvNavButton)
$mainNavPanel.Controls.Add($settingsNavButton)

$mainNavAccentPanel = [System.Windows.Forms.Panel]::new()
$mainNavAccentPanel.Location = [System.Drawing.Point]::new(0, 30)
$mainNavAccentPanel.Size = [System.Drawing.Size]::new(150, 2)
$mainNavAccentPanel.BackColor = $colors.Cyan
$mainNavPanel.Controls.Add($mainNavAccentPanel)

$mainContentPanel = [System.Windows.Forms.Panel]::new()
$mainContentPanel.Location = [System.Drawing.Point]::new(1, 154)
$mainContentPanel.Size = [System.Drawing.Size]::new(898, 531)
$mainContentPanel.BackColor = $colors.Background

$hllvPage = [System.Windows.Forms.Panel]::new()
$hllvPage.Location = [System.Drawing.Point]::new(0, 0)
$hllvPage.Size = [System.Drawing.Size]::new(900, 532)
$hllvPage.BackColor = $colors.Background
$hllvPage.ForeColor = $colors.Text

$settingsPage = [System.Windows.Forms.Panel]::new()
$settingsPage.Location = [System.Drawing.Point]::new(0, 0)
$settingsPage.Size = [System.Drawing.Size]::new(900, 532)
$settingsPage.BackColor = $colors.Background
$settingsPage.ForeColor = $colors.Text
$settingsPage.Visible = $false

$mainContentPanel.Controls.Add($settingsPage)
$mainContentPanel.Controls.Add($hllvPage)

$statusPanel = [System.Windows.Forms.Panel]::new()
$statusPanel.Location = [System.Drawing.Point]::new(20, 14)
$statusPanel.Size = [System.Drawing.Size]::new(852, 92)
$statusPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$statusPanel.BackColor = $colors.Surface

$statusAccentPanel = [System.Windows.Forms.Panel]::new()
$statusAccentPanel.Location = [System.Drawing.Point]::new(0, 0)
$statusAccentPanel.Size = [System.Drawing.Size]::new(6, 92)
$statusAccentPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$statusAccentPanel.BackColor = $colors.Red

$statusTopRail = [System.Windows.Forms.Panel]::new()
$statusTopRail.Location = [System.Drawing.Point]::new(6, 0)
$statusTopRail.Size = [System.Drawing.Size]::new(846, 1)
$statusTopRail.BackColor = $colors.Red

$runStateLabel = [System.Windows.Forms.Label]::new()
$runStateLabel.Text = "SYSTEM // STOPPED"
$runStateLabel.Font = New-UiFont -Size 12 -Style Bold
$runStateLabel.ForeColor = $colors.Red
$runStateLabel.Location = [System.Drawing.Point]::new(26, 10)
$runStateLabel.Size = [System.Drawing.Size]::new(300, 25)

$mainStatusLabel = [System.Windows.Forms.Label]::new()
$mainStatusLabel.Text = "Ready to seed"
$mainStatusLabel.Font = New-UiFont -Size 10.5 -Style Bold
$mainStatusLabel.ForeColor = $colors.Text
$mainStatusLabel.Location = [System.Drawing.Point]::new(26, 38)
$mainStatusLabel.Size = [System.Drawing.Size]::new(490, 23)
$mainStatusLabel.AutoEllipsis = $true

$statusDetailLabel = [System.Windows.Forms.Label]::new()
$statusDetailLabel.Text = "Choose games, then click Start Seeding"
$statusDetailLabel.Font = New-UiFont -Size 9
$statusDetailLabel.ForeColor = $colors.Muted
$statusDetailLabel.Location = [System.Drawing.Point]::new(26, 65)
$statusDetailLabel.Size = [System.Drawing.Size]::new(490, 20)
$statusDetailLabel.AutoEllipsis = $true

$startButton = New-FlatButton -Text "Start Seeding" -BackColor $colors.Green -Width 120
$startButton.Location = [System.Drawing.Point]::new(538, 27)
$startButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$stopButton = New-FlatButton -Text "Stop" -BackColor $colors.Red -Width 76
$stopButton.Location = [System.Drawing.Point]::new(668, 27)
$stopButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$openLogButton = New-FlatButton -Text "Open Log" -BackColor $colors.SurfaceAlt -Width 82
$openLogButton.Location = [System.Drawing.Point]::new(754, 27)
$openLogButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$gamesCaptionLabel = [System.Windows.Forms.Label]::new()
$gamesCaptionLabel.Text = "SEED"
$gamesCaptionLabel.Font = New-UiFont -Size 8 -Style Bold
$gamesCaptionLabel.ForeColor = $colors.Muted
$gamesCaptionLabel.Location = [System.Drawing.Point]::new(538, 69)
$gamesCaptionLabel.Size = [System.Drawing.Size]::new(42, 18)

$hllvGameCheckBox = [System.Windows.Forms.CheckBox]::new()
$hllvGameCheckBox.Text = "HLLV"
$hllvGameCheckBox.Checked = [bool]$config.enabledGames.hllv
$hllvGameCheckBox.Font = New-UiFont -Size 8.5 -Style Bold
$hllvGameCheckBox.ForeColor = $colors.Text
$hllvGameCheckBox.BackColor = $colors.Surface
$hllvGameCheckBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$hllvGameCheckBox.Location = [System.Drawing.Point]::new(584, 65)
$hllvGameCheckBox.Size = [System.Drawing.Size]::new(70, 24)

$ww2GameCheckBox = [System.Windows.Forms.CheckBox]::new()
$ww2GameCheckBox.Text = "HLL WW2"
$ww2GameCheckBox.Checked = [bool]$config.enabledGames.hllWw2
$ww2GameCheckBox.Font = New-UiFont -Size 8.5 -Style Bold
$ww2GameCheckBox.ForeColor = $colors.Text
$ww2GameCheckBox.BackColor = $colors.Surface
$ww2GameCheckBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ww2GameCheckBox.Location = [System.Drawing.Point]::new(662, 65)
$ww2GameCheckBox.Size = [System.Drawing.Size]::new(98, 24)

$statusPanel.Controls.Add($statusAccentPanel)
$statusPanel.Controls.Add($statusTopRail)
$statusPanel.Controls.Add($runStateLabel)
$statusPanel.Controls.Add($mainStatusLabel)
$statusPanel.Controls.Add($statusDetailLabel)
$statusPanel.Controls.Add($startButton)
$statusPanel.Controls.Add($stopButton)
$statusPanel.Controls.Add($openLogButton)
$statusPanel.Controls.Add($gamesCaptionLabel)
$statusPanel.Controls.Add($hllvGameCheckBox)
$statusPanel.Controls.Add($ww2GameCheckBox)

$serversTitle = [System.Windows.Forms.Label]::new()
$serversTitle.Text = "EASY SERVERS  |  HLLV PRIORITY"
$serversTitle.Font = New-UiFont -Size 9 -Style Bold
$serversTitle.ForeColor = $colors.Cyan
$serversTitle.Location = [System.Drawing.Point]::new(20, 122)
$serversTitle.Size = [System.Drawing.Size]::new(200, 20)

$serversPanel = [System.Windows.Forms.Panel]::new()
$serversPanel.Location = [System.Drawing.Point]::new(20, 146)
$serversPanel.Size = [System.Drawing.Size]::new(852, 206)
$serversPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$serversPanel.BackColor = $colors.Surface

$headerServer = [System.Windows.Forms.Label]::new()
$headerServer.Text = "GAME / SERVER"
$headerServer.Font = New-UiFont -Size 8 -Style Bold
$headerServer.ForeColor = $colors.Muted
$headerServer.Location = [System.Drawing.Point]::new(14, 8)
$headerServer.Size = [System.Drawing.Size]::new(100, 18)

$headerDetails = [System.Windows.Forms.Label]::new()
$headerDetails.Text = "SERVER FOCUS / MODE"
$headerDetails.Font = New-UiFont -Size 8 -Style Bold
$headerDetails.ForeColor = $colors.Muted
$headerDetails.Location = [System.Drawing.Point]::new(110, 8)
$headerDetails.Size = [System.Drawing.Size]::new(260, 18)

$headerLoad = [System.Windows.Forms.Label]::new()
$headerLoad.Text = "LOAD"
$headerLoad.Font = New-UiFont -Size 8 -Style Bold
$headerLoad.ForeColor = $colors.Muted
$headerLoad.Location = [System.Drawing.Point]::new(500, 8)
$headerLoad.Size = [System.Drawing.Size]::new(74, 18)

$headerPlayers = [System.Windows.Forms.Label]::new()
$headerPlayers.Text = "PLAYERS"
$headerPlayers.Font = New-UiFont -Size 8 -Style Bold
$headerPlayers.ForeColor = $colors.Muted
$headerPlayers.Location = [System.Drawing.Point]::new(590, 8)
$headerPlayers.Size = [System.Drawing.Size]::new(80, 18)
$headerPlayers.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$headerState = [System.Windows.Forms.Label]::new()
$headerState.Text = "STATUS"
$headerState.Font = New-UiFont -Size 8 -Style Bold
$headerState.ForeColor = $colors.Muted
$headerState.Location = [System.Drawing.Point]::new(686, 8)
$headerState.Size = [System.Drawing.Size]::new(150, 18)
$headerState.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$serversPanel.Controls.Add($headerServer)
$serversPanel.Controls.Add($headerDetails)
$serversPanel.Controls.Add($headerLoad)
$serversPanel.Controls.Add($headerPlayers)
$serversPanel.Controls.Add($headerState)

$script:ServerRows = [ordered]@{}
for ($index = 0; $index -lt $serverDefinitions.Count; $index++) {
    $definition = $serverDefinitions[$index]
    $rowTop = 29 + ($index * 29)

    $rowPanel = [System.Windows.Forms.Panel]::new()
    $rowPanel.Location = [System.Drawing.Point]::new(0, $rowTop)
    $rowPanel.Size = [System.Drawing.Size]::new(852, 28)
    $rowPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rowPanel.BackColor = if (($index % 2) -eq 0) { $colors.SurfaceAlt } else { $colors.Surface }
    $baseRowColor = $rowPanel.BackColor

    $statusRail = [System.Windows.Forms.Panel]::new()
    $statusRail.Location = [System.Drawing.Point]::new(0, 0)
    $statusRail.Size = [System.Drawing.Size]::new(3, 28)
    $statusRail.BackColor = $colors.Muted

    $nameLabel = [System.Windows.Forms.Label]::new()
    $nameLabel.Text = "$($definition.Label)"
    $nameLabel.Font = New-UiFont -Size 9 -Style Bold
    $nameLabel.ForeColor = $colors.Blue
    $nameLabel.Location = [System.Drawing.Point]::new(14, 5)
    $nameLabel.Size = [System.Drawing.Size]::new(90, 20)

    $detailsLabel = [System.Windows.Forms.Label]::new()
    $detailsLabel.Text = "$($definition.Details)"
    $detailsLabel.Font = New-UiFont -Size 9
    $detailsLabel.ForeColor = $colors.Text
    $detailsLabel.Location = [System.Drawing.Point]::new(110, 5)
    $detailsLabel.Size = [System.Drawing.Size]::new(375, 20)
    $detailsLabel.AutoEllipsis = $true

    $progressTrack = [System.Windows.Forms.Panel]::new()
    $progressTrack.Location = [System.Drawing.Point]::new(500, 10)
    $progressTrack.Size = [System.Drawing.Size]::new(74, 7)
    $progressTrack.BackColor = $colors.Background

    $progressFill = [System.Windows.Forms.Panel]::new()
    $progressFill.Location = [System.Drawing.Point]::new(0, 0)
    $progressFill.Size = [System.Drawing.Size]::new(0, 7)
    $progressFill.BackColor = $colors.Muted
    $progressTrack.Controls.Add($progressFill)

    $playersLabel = [System.Windows.Forms.Label]::new()
    $playersLabel.Text = "--/100"
    $playersLabel.Font = New-UiFont -Size 9.5 -Style Bold
    $playersLabel.ForeColor = $colors.Text
    $playersLabel.Location = [System.Drawing.Point]::new(590, 5)
    $playersLabel.Size = [System.Drawing.Size]::new(80, 20)
    $playersLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

    $stateLabel = [System.Windows.Forms.Label]::new()
    $stateLabel.Text = "WAITING"
    $stateLabel.Font = New-UiFont -Size 8.5 -Style Bold
    $stateLabel.ForeColor = $colors.Muted
    $stateLabel.Location = [System.Drawing.Point]::new(686, 6)
    $stateLabel.Size = [System.Drawing.Size]::new(150, 18)
    $stateLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

    $rowPanel.Controls.Add($statusRail)
    $rowPanel.Controls.Add($nameLabel)
    $rowPanel.Controls.Add($detailsLabel)
    $rowPanel.Controls.Add($progressTrack)
    $rowPanel.Controls.Add($playersLabel)
    $rowPanel.Controls.Add($stateLabel)
    $serversPanel.Controls.Add($rowPanel)

    $script:ServerRows["$($definition.Key)"] = [pscustomobject]@{
        RowPanel = $rowPanel
        BaseBackColor = $baseRowColor
        StatusRail = $statusRail
        ProgressTrack = $progressTrack
        ProgressFill = $progressFill
        Players = $playersLabel
        State = $stateLabel
    }
}

$activityTitle = [System.Windows.Forms.Label]::new()
$activityTitle.Text = "EVENT STREAM"
$activityTitle.Font = New-UiFont -Size 9 -Style Bold
$activityTitle.ForeColor = $colors.Cyan
$activityTitle.Location = [System.Drawing.Point]::new(20, 366)
$activityTitle.Size = [System.Drawing.Size]::new(200, 20)

$activityBox = [System.Windows.Forms.RichTextBox]::new()
$activityBox.Location = [System.Drawing.Point]::new(20, 390)
$activityBox.Size = [System.Drawing.Size]::new(852, 102)
$activityBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$activityBox.BackColor = $colors.Terminal
$activityBox.ForeColor = [System.Drawing.Color]::FromArgb(194, 226, 232)
$activityBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$activityBox.Font = [System.Drawing.Font]::new("Consolas", 9)
$activityBox.ReadOnly = $true
$activityBox.DetectUrls = $false

$countdownLabel = [System.Windows.Forms.Label]::new()
$countdownLabel.Text = "Not running"
$countdownLabel.Font = New-UiFont -Size 9.5 -Style Bold
$countdownLabel.ForeColor = $colors.Cyan
$countdownLabel.Location = [System.Drawing.Point]::new(20, 505)
$countdownLabel.Size = [System.Drawing.Size]::new(430, 22)
$countdownLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$behaviorLabel = [System.Windows.Forms.Label]::new()
$behaviorLabel.Text = "Selected games stop at $($config.seededAtPlayers)/$($config.maxPlayers)"
$behaviorLabel.Font = New-UiFont -Size 9
$behaviorLabel.ForeColor = $colors.Muted
$behaviorLabel.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$behaviorLabel.Location = [System.Drawing.Point]::new(496, 505)
$behaviorLabel.Size = [System.Drawing.Size]::new(376, 22)
$behaviorLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$form.Controls.Add($titleBarPanel)
$form.Controls.Add($headerPanel)
$form.Controls.Add($mainNavPanel)
$form.Controls.Add($mainContentPanel)

$hllvPage.Controls.Add($statusPanel)
$hllvPage.Controls.Add($serversTitle)
$hllvPage.Controls.Add($serversPanel)
$hllvPage.Controls.Add($activityTitle)
$hllvPage.Controls.Add($activityBox)
$hllvPage.Controls.Add($countdownLabel)
$hllvPage.Controls.Add($behaviorLabel)

$settingsTitle = [System.Windows.Forms.Label]::new()
$settingsTitle.Text = "TIMING CONTROL"
$settingsTitle.Font = New-UiFont -Size 18 -Style Bold
$settingsTitle.ForeColor = $colors.Text
$settingsTitle.Location = [System.Drawing.Point]::new(22, 16)
$settingsTitle.Size = [System.Drawing.Size]::new(360, 34)

$settingsSubtitle = [System.Windows.Forms.Label]::new()
$settingsSubtitle.Text = "Recommended values work for most PCs. Only change timing if a game loads too slowly."
$settingsSubtitle.Font = New-UiFont -Size 9.5
$settingsSubtitle.ForeColor = $colors.Muted
$settingsSubtitle.Location = [System.Drawing.Point]::new(24, 52)
$settingsSubtitle.Size = [System.Drawing.Size]::new(820, 24)

$gameSettingsNavPanel = [System.Windows.Forms.Panel]::new()
$gameSettingsNavPanel.Location = [System.Drawing.Point]::new(20, 82)
$gameSettingsNavPanel.Size = [System.Drawing.Size]::new(852, 32)
$gameSettingsNavPanel.BackColor = $colors.Background

$hllvSettingsNavButton = New-FlatButton -Text "HLLV" -BackColor $colors.SurfaceAlt -Width 130
$hllvSettingsNavButton.Location = [System.Drawing.Point]::new(0, 0)
$hllvSettingsNavButton.Size = [System.Drawing.Size]::new(130, 32)
$hllvSettingsNavButton.ForeColor = $colors.Text
$gameSettingsNavPanel.Controls.Add($hllvSettingsNavButton)

$ww2SettingsNavButton = New-FlatButton -Text "HLL WW2" -BackColor $colors.Background -Width 130
$ww2SettingsNavButton.Location = [System.Drawing.Point]::new(130, 0)
$ww2SettingsNavButton.Size = [System.Drawing.Size]::new(130, 32)
$ww2SettingsNavButton.ForeColor = $colors.Muted
$gameSettingsNavPanel.Controls.Add($ww2SettingsNavButton)

$gameSettingsNavAccentPanel = [System.Windows.Forms.Panel]::new()
$gameSettingsNavAccentPanel.Location = [System.Drawing.Point]::new(0, 30)
$gameSettingsNavAccentPanel.Size = [System.Drawing.Size]::new(130, 2)
$gameSettingsNavAccentPanel.BackColor = $colors.Cyan
$gameSettingsNavPanel.Controls.Add($gameSettingsNavAccentPanel)

$hllvTiming = New-GameTimingPage -GameConfig $config -GameName "HLLV"
$ww2Timing = New-GameTimingPage -GameConfig $config.hllWw2 -GameName "HLL WW2"
$hllvSettingsPage = $hllvTiming.Panel
$ww2SettingsPage = $ww2Timing.Panel
$ww2SettingsPage.Visible = $false

$script:TimingInputs = @($hllvTiming.Inputs) + @($ww2Timing.Inputs)

$settingsLockLabel = [System.Windows.Forms.Label]::new()
$settingsLockLabel.Text = "Stop the seeder before changing timing settings."
$settingsLockLabel.Font = New-UiFont -Size 9 -Style Bold
$settingsLockLabel.ForeColor = $colors.Amber
$settingsLockLabel.Location = [System.Drawing.Point]::new(22, 472)
$settingsLockLabel.Size = [System.Drawing.Size]::new(390, 22)
$settingsLockLabel.Visible = $false

$settingsStatusLabel = [System.Windows.Forms.Label]::new()
$settingsStatusLabel.Text = "Changes apply the next time seeding starts."
$settingsStatusLabel.Font = New-UiFont -Size 9
$settingsStatusLabel.ForeColor = $colors.Muted
$settingsStatusLabel.Location = [System.Drawing.Point]::new(22, 498)
$settingsStatusLabel.Size = [System.Drawing.Size]::new(430, 22)

$shortcutButtonText = if (Test-Path -LiteralPath (Get-DesktopShortcutPath)) { "Recreate Shortcut" } else { "Create Shortcut" }
$createShortcutButton = New-FlatButton -Text $shortcutButtonText -BackColor $colors.SurfaceAlt -Width 136
$createShortcutButton.Location = [System.Drawing.Point]::new(452, 468)
$createShortcutButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$restoreTimingButton = New-FlatButton -Text "Recommended" -BackColor $colors.SurfaceAlt -Width 126
$restoreTimingButton.Location = [System.Drawing.Point]::new(598, 468)
$restoreTimingButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$saveSettingsButton = New-FlatButton -Text "Save Settings" -BackColor $colors.Green -Width 130
$saveSettingsButton.Location = [System.Drawing.Point]::new(734, 468)
$saveSettingsButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

$settingsPage.Controls.Add($settingsTitle)
$settingsPage.Controls.Add($settingsSubtitle)
$settingsPage.Controls.Add($gameSettingsNavPanel)
$settingsPage.Controls.Add($hllvSettingsPage)
$settingsPage.Controls.Add($ww2SettingsPage)
$settingsPage.Controls.Add($settingsLockLabel)
$settingsPage.Controls.Add($settingsStatusLabel)
$settingsPage.Controls.Add($createShortcutButton)
$settingsPage.Controls.Add($restoreTimingButton)
$settingsPage.Controls.Add($saveSettingsButton)

$hllvNavButton.Add_Click({
    $settingsPage.Visible = $false
    $hllvPage.Visible = $true
    $hllvPage.BringToFront()
    $hllvNavButton.BackColor = $colors.SurfaceAlt
    $hllvNavButton.ForeColor = $colors.Text
    $settingsNavButton.BackColor = $colors.Background
    $settingsNavButton.ForeColor = $colors.Muted
    $mainNavAccentPanel.Left = 0
})

$settingsNavButton.Add_Click({
    $hllvPage.Visible = $false
    $settingsPage.Visible = $true
    $settingsPage.BringToFront()
    $settingsNavButton.BackColor = $colors.SurfaceAlt
    $settingsNavButton.ForeColor = $colors.Text
    $hllvNavButton.BackColor = $colors.Background
    $hllvNavButton.ForeColor = $colors.Muted
    $mainNavAccentPanel.Left = 150
})

$hllvSettingsNavButton.Add_Click({
    $ww2SettingsPage.Visible = $false
    $hllvSettingsPage.Visible = $true
    $hllvSettingsPage.BringToFront()
    $hllvSettingsNavButton.BackColor = $colors.SurfaceAlt
    $hllvSettingsNavButton.ForeColor = $colors.Text
    $ww2SettingsNavButton.BackColor = $colors.Background
    $ww2SettingsNavButton.ForeColor = $colors.Muted
    $gameSettingsNavAccentPanel.Left = 0
})

$ww2SettingsNavButton.Add_Click({
    $hllvSettingsPage.Visible = $false
    $ww2SettingsPage.Visible = $true
    $ww2SettingsPage.BringToFront()
    $ww2SettingsNavButton.BackColor = $colors.SurfaceAlt
    $ww2SettingsNavButton.ForeColor = $colors.Text
    $hllvSettingsNavButton.BackColor = $colors.Background
    $hllvSettingsNavButton.ForeColor = $colors.Muted
    $gameSettingsNavAccentPanel.Left = 130
})

$createShortcutButton.Add_Click({
    try {
        $shortcutPath = New-DesktopShortcut
        $createShortcutButton.Text = "Recreate Shortcut"
        $settingsStatusLabel.Text = "Desktop shortcut created at $((Get-Date).ToString('h:mm:ss tt'))"
        $settingsStatusLabel.ForeColor = $colors.Green
        Add-Activity -Message "Desktop shortcut created: $shortcutPath"
    } catch {
        $settingsStatusLabel.Text = "Desktop shortcut could not be created."
        $settingsStatusLabel.ForeColor = $colors.Red
        Add-Activity -Message "Desktop shortcut failed: $($_.Exception.Message)"
    }
})

$restoreTimingButton.Add_Click({
    $hllvTiming.Poll.Value = 60
    $hllvTiming.Launch.Value = 80
    $hllvTiming.Close.Value = 30
    $hllvTiming.Join.Value = 60
    $hllvTiming.Menu.Value = 15
    $hllvTiming.Focus.Value = 15
    $hllvTiming.Browser.Value = 10
    $hllvTiming.Search.Value = 8
    $ww2Timing.Poll.Value = 60
    $ww2Timing.Launch.Value = 45
    $ww2Timing.Close.Value = 30
    $ww2Timing.Join.Value = 45
    $ww2Timing.Menu.Value = 10
    $ww2Timing.Focus.Value = 15
    $ww2Timing.Browser.Value = 10
    $ww2Timing.Search.Value = 8
    $settingsStatusLabel.Text = "Recommended HLLV and WW2 values loaded. Click Save Settings."
    $settingsStatusLabel.ForeColor = $colors.Amber
})

$saveSettingsButton.Add_Click({
    if (Test-SeederRunning) {
        $settingsLockLabel.Visible = $true
        return
    }

    try {
        $config.pollSeconds = [int]$hllvTiming.Poll.Value
        $config.launchWaitSeconds = [int]$hllvTiming.Launch.Value
        $config.closeGraceSeconds = [int]$hllvTiming.Close.Value
        $config.uiAutomation.joinWaitSeconds = [int]$hllvTiming.Join.Value
        $config.uiAutomation.menuReadyWaitSeconds = [int]$hllvTiming.Menu.Value
        $config.uiAutomation.afterFocusClickWaitSeconds = [int]$hllvTiming.Focus.Value
        $config.uiAutomation.browserWaitSeconds = [int]$hllvTiming.Browser.Value
        $config.uiAutomation.searchWaitSeconds = [int]$hllvTiming.Search.Value
        $config.hllWw2.pollSeconds = [int]$ww2Timing.Poll.Value
        $config.hllWw2.launchWaitSeconds = [int]$ww2Timing.Launch.Value
        $config.hllWw2.closeGraceSeconds = [int]$ww2Timing.Close.Value
        $config.hllWw2.uiAutomation.joinWaitSeconds = [int]$ww2Timing.Join.Value
        $config.hllWw2.uiAutomation.menuReadyWaitSeconds = [int]$ww2Timing.Menu.Value
        $config.hllWw2.uiAutomation.afterFocusClickWaitSeconds = [int]$ww2Timing.Focus.Value
        $config.hllWw2.uiAutomation.browserWaitSeconds = [int]$ww2Timing.Browser.Value
        $config.hllWw2.uiAutomation.searchWaitSeconds = [int]$ww2Timing.Search.Value

        Write-JsonFileSafely -Value $config -Path $configPath -Depth 12

        Update-GameSelectionPresentation
        $script:NextLiveRefresh = (Get-Date).AddSeconds([int]$config.pollSeconds)
        $settingsStatusLabel.Text = "HLLV and HLL WW2 timing saved at $((Get-Date).ToString('h:mm:ss tt'))"
        $settingsStatusLabel.ForeColor = $colors.Green
        Add-Activity -Message "HLLV and HLL WW2 timing settings saved."
    } catch {
        $settingsStatusLabel.Text = "Settings could not be saved. Open the log for details."
        $settingsStatusLabel.ForeColor = $colors.Red
        Add-Activity -Message "Settings save failed: $($_.Exception.Message)"
    }
})

$toolTip = [System.Windows.Forms.ToolTip]::new()
$toolTip.SetToolTip($startButton, "Start seeding the selected games in priority order.")
$toolTip.SetToolTip($stopButton, "Stop the helper. Any running game will remain open.")
$toolTip.SetToolTip($editPlayerButton, "Change the exact Steam name used for EASY stats.")
$toolTip.SetToolTip($openLogButton, "Open the full troubleshooting log in Notepad.")
$toolTip.SetToolTip($createShortcutButton, "Create or restore the EASY Seeding Helper shortcut on your Desktop.")
$toolTip.SetToolTip($restoreTimingButton, "Load the measured HLLV and HLL WW2 timing values without saving yet.")
$toolTip.SetToolTip($saveSettingsButton, "Save timing changes to this Desktop copy.")

$script:SeederProcess = Find-SeederProcess
$script:LastStatusStamp = ""
$script:LastActivityMessage = ""
$script:SeenStatusEvents = @{}
$script:StatsHttpClient = [System.Net.Http.HttpClient]::new()
$script:StatsHttpClient.Timeout = [TimeSpan]::FromSeconds(15)
$script:LiveRefreshRequests = @()
$script:NextLiveRefresh = Get-Date
$script:LastLiveRefresh = $null
$script:LastStatsUpdate = $null
$script:NextSystemIndicatorUpdate = Get-Date

$hllvGameCheckBox.Add_CheckedChanged({
    if (!(Test-SeederRunning)) {
        try {
            Save-GameSelection
            $script:NextLiveRefresh = Get-Date
            Update-GameSelectionPresentation -UpdateReadyMessage
            Add-Activity -Message "HLLV seeding $(@('disabled', 'enabled')[[int]$hllvGameCheckBox.Checked])."
        } catch {
            Add-Activity -Message "HLLV selection could not be saved: $($_.Exception.Message)"
        }
    }
})
$ww2GameCheckBox.Add_CheckedChanged({
    if (!(Test-SeederRunning)) {
        try {
            Save-GameSelection
            $script:NextLiveRefresh = Get-Date
            Update-GameSelectionPresentation -UpdateReadyMessage
            Add-Activity -Message "HLL WW2 seeding $(@('disabled', 'enabled')[[int]$ww2GameCheckBox.Checked])."
        } catch {
            Add-Activity -Message "HLL WW2 selection could not be saved: $($_.Exception.Message)"
        }
    }
})

$startButton.Add_Click({ Start-Seeder })
$stopButton.Add_Click({ Stop-Seeder })
$openLogButton.Add_Click({
    try {
        if (!(Test-Path -LiteralPath $logPath)) {
            [System.IO.File]::WriteAllText($logPath, "")
        }
        Start-Process "notepad.exe" -ArgumentList "`"$logPath`""
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "The log could not be opened.`r`n`r`n$($_.Exception.Message)",
            "Could not open log",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})
$editPlayerButton.Add_Click({
    $updatedName = Show-PlayerNameDialog -CurrentName (Read-PlayerName)
    if (![string]::IsNullOrWhiteSpace($updatedName)) {
        $playerValueLabel.Text = $updatedName
        Add-Activity -Message "Steam name updated."
    }
})

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 1000
$timer.Add_Tick({
    try {
        Update-SystemIndicators
        if ($script:SeederProcess) {
            try {
                if ($script:SeederProcess.HasExited) {
                    $exitCode = $script:SeederProcess.ExitCode
                    $script:SeederProcess = $null
                    Set-UiRunningState -Running $false
                    $countdownLabel.Text = "Not running"
                    if ($exitCode -ne 0) {
                        $mainStatusLabel.Text = "Seeder stopped with an error"
                        $statusDetailLabel.Text = "Open the log for details"
                        Add-Activity -Message "Seeder stopped with exit code $exitCode."
                    } else {
                        $mainStatusLabel.Text = "Seeder stopped"
                        $statusDetailLabel.Text = "Ready to start again"
                        Add-Activity -Message "Seeder process finished."
                    }
                }
            } catch {
                $script:SeederProcess = $null
                Set-UiRunningState -Running $false
            }
        }

        Update-FromStatusFile

        if (!(Test-SeederRunning)) {
            Complete-LiveServerRefresh
            if ($script:LiveRefreshRequests.Count -eq 0 -and (Get-Date) -ge $script:NextLiveRefresh) {
                Start-LiveServerRefresh
            }

            if ($script:LiveRefreshRequests.Count -eq 0) {
                $remaining = [Math]::Max(0, [int][Math]::Ceiling(($script:NextLiveRefresh - (Get-Date)).TotalSeconds))
                $countdownLabel.Text = "Live server refresh in $remaining seconds"
            }
        }
    } catch {
        $errorMessage = $_.Exception.Message
        $now = Get-Date
        $shouldReport = $errorMessage -ne $script:LastUiBackgroundError -or
            !$script:LastUiBackgroundErrorAt -or
            ($now - $script:LastUiBackgroundErrorAt).TotalSeconds -ge 60
        if ($shouldReport) {
            $script:LastUiBackgroundError = $errorMessage
            $script:LastUiBackgroundErrorAt = $now
            try { Add-Activity -Message "Background refresh recovered from an error: $errorMessage" } catch { }
        }
    }
})

$form.Add_Shown({
    [EasyHllvUiWindow]::ShowWindow($form.Handle, 5) | Out-Null
    [EasyHllvUiWindow]::SetForegroundWindow($form.Handle) | Out-Null

    $playerName = Read-PlayerName
    if ([string]::IsNullOrWhiteSpace($playerName)) {
        $playerName = Show-WelcomeDialog
        if ([string]::IsNullOrWhiteSpace($playerName)) {
            $form.Close()
            return
        }
        $playerValueLabel.Text = $playerName
    }

    if ($script:SeederProcess) {
        Set-UiRunningState -Running $true
        $mainStatusLabel.Text = "Seeder is already running"
        Add-Activity -Message "Connected to the running seeder."
    } else {
        Set-UiRunningState -Running $false
        Add-Activity -Message "UI ready. Click Start Seeding when you are ready."
    }

    Update-FromStatusFile
    Update-GameSelectionPresentation -UpdateReadyMessage
    Update-SystemIndicators -Force
    $script:NextLiveRefresh = Get-Date
    $timer.Start()
})

$form.Add_FormClosing({
    param($sender, $eventArgs)

    $isRunning = $false
    if ($script:SeederProcess) {
        try { $isRunning = !$script:SeederProcess.HasExited } catch { $isRunning = $false }
    }

    if ($isRunning) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "The seeder is still running.`r`n`r`nYes: stop the seeder and close`r`nNo: leave it running and close the UI`r`nCancel: keep the UI open",
            "Close seeding helper?",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            $eventArgs.Cancel = $true
            return
        }

        if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
            Stop-Seeder
        }
    }

    $timer.Stop()
    $script:StatsHttpClient.Dispose()
    if ($script:AppIcon) {
        $script:AppIcon.Dispose()
        $script:AppIcon = $null
    }
    if ($script:AppIconBitmap) {
        $script:AppIconBitmap.Dispose()
        $script:AppIconBitmap = $null
    }
})

[void]$form.ShowDialog()
