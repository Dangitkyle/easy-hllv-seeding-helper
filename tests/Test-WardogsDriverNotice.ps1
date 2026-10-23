$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WardogsSupport.ps1')
$script:Checks = 0

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'." }
    $script:Checks++
}

function New-NoticeScreen([int]$Width = 1920, [int]$Height = 1080, [object[]]$Lines = @()) {
    [pscustomobject]@{ State = 'DriverNotice'; Width = $Width; Height = $Height; Lines = $Lines; Handle = [IntPtr]123 }
}

foreach ($label in @('OK', 'O K', '0K', '(0 K)')) {
    $screen = New-NoticeScreen -Lines @([pscustomobject]@{ Text = $label; X = 950; Y = 680 })
    $button = Get-WardogsDriverNoticeButton -Screen $screen
    Assert-Equal $button.Source 'button text' "OCR variant $label"
    Assert-Equal $button.X 950 "OCR location $label"
}

foreach ($case in @(
    @{ Width = 1920; Height = 1080; X = 960; Y = 682 },
    @{ Width = 2560; Height = 1080; X = 1280; Y = 682 },
    @{ Width = 1280; Height = 720; X = 640; Y = 455 },
    @{ Width = 1920; Height = 1200; X = 960; Y = 742 }
)) {
    $screen = New-NoticeScreen -Width $case.Width -Height $case.Height
    $button = Get-WardogsDriverNoticeButton -Screen $screen
    Assert-Equal $button.X $case.X 'Fallback horizontal position'
    Assert-Equal $button.Y $case.Y 'Fallback vertical position'
}

$screen = New-NoticeScreen
$screen.State = 'MainMenu'
$rejected = $false
try { Get-WardogsDriverNoticeButton -Screen $screen | Out-Null } catch { $rejected = $true }
Assert-Equal $rejected $true 'No dialog fallback on another screen'

$script:Clicks = @()
$script:Focused = $true
function Get-GameWindowBounds { param($Config) [pscustomobject]@{ Left = 100; Top = 50 } }
function Test-WardogsGameFocused { param($Screen) $script:Focused }
function Write-Log { param($Message) }
function Invoke-LeftClick { param($X, $Y) $script:Clicks += [pscustomobject]@{ X = $X; Y = $Y } }

Dismiss-WardogsDriverNotice -Config ([pscustomobject]@{}) -Screen (New-NoticeScreen)
Assert-Equal $script:Clicks.Count 1 'Missing OCR label dismisses notice'
Assert-Equal $script:Clicks[0].X 1060 'Window horizontal offset'
Assert-Equal $script:Clicks[0].Y 732 'Window vertical offset'
$script:Focused = $false
Dismiss-WardogsDriverNotice -Config ([pscustomobject]@{}) -Screen (New-NoticeScreen)
Assert-Equal $script:Clicks.Count 1 'No clicks when game loses focus'

"PASS: $script:Checks driver-notice checks."
