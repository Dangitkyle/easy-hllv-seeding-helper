$ErrorActionPreference = 'Stop'
$basePath = Split-Path -Parent $PSScriptRoot
. (Join-Path $basePath 'WardogsSupport.ps1')
$script:Checks = 0
$script:ActivityStarts = 0
$script:FactionPicks = 0
$script:MockScreen = 'Unknown'
$script:MockProcess = [pscustomobject]@{ Id = 1234 }
$script:WardogsActivityWorker = [pscustomobject]@{ Running = $true }
$config = [pscustomobject]@{ gameId = 'wardogs' }
$server = [pscustomobject]@{ joinCode = 'test-west'; number = 'WEST' }

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'." }
    $script:Checks++
}
function Get-WardogsScreen { [pscustomobject]@{ State = $script:MockScreen } }
function Get-Process { param($Name, $ErrorAction) $script:MockProcess }
function Select-WardogsFaction { param($Config) $script:FactionPicks++ }
function Start-WardogsActivity {
    param($Config)
    $script:ActivityStarts++
    $script:WardogsActivityWorker = [pscustomobject]@{ Running = $true }
}
function Reset-Session {
    $script:WardogsSession = [pscustomobject]@{
        JoinCode = 'test-west'
        ProcessId = 1234
        LastMatchedAt = (Get-Date).AddDays(-30)
    }
    $script:MockProcess = [pscustomobject]@{ Id = 1234 }
}

Reset-Session
foreach ($state in @('Unknown', 'Background', 'ConfirmServer', 'DriverNotice')) {
    $script:MockScreen = $state
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Known $false "$state remains unverified even after 30 days"
    Assert-Equal ($null -eq $result.Connected) $true "$state is not a failed connection"
    Assert-Equal $result.MatchFound $true "$state preserves the joined session"
}
for ($i = 0; $i -lt 5; $i++) {
    $script:MockScreen = 'Unknown'
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Known $false "Repeated uncertain scan $i does not become a disconnect"
}
Assert-Equal $script:ActivityStarts 0 'Uncertain screens do not start blind activity clicks'

foreach ($state in @('Closed', 'Disconnected', 'MainMenu', 'Browser', 'BrowserType', 'Start', 'FindServer')) {
    Reset-Session
    $script:MockScreen = $state
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Known $true "$state remains a known disconnect"
    Assert-Equal $result.Connected $false "$state still allows recovery"
}

Reset-Session
$script:MockScreen = 'Match'
$result = Get-WardogsConnectionState -Config $config -Server $server
Assert-Equal $result.Connected $true 'Recognized match remains connected'
Assert-Equal ($script:WardogsSession.LastMatchedAt -gt (Get-Date).AddMinutes(-1)) $true 'Match timestamp is refreshed'
Assert-Equal $script:ActivityStarts 0 'Running activity worker is not duplicated'
$script:WardogsActivityWorker = $null
$result = Get-WardogsConnectionState -Config $config -Server $server
Assert-Equal $script:ActivityStarts 1 'Activity resumes after a screen-check error stopped its worker'
$null = Get-WardogsConnectionState -Config $config -Server $server
Assert-Equal $script:ActivityStarts 1 'Recovered activity worker is not restarted again'

$script:MockScreen = 'Faction'
$result = Get-WardogsConnectionState -Config $config -Server $server
Assert-Equal $result.Known $false 'Team selection does not claim a disconnect'
Assert-Equal $script:FactionPicks 1 'Team selection is retried'

foreach ($state in @('Match', 'Unknown')) {
    Reset-Session
    $script:MockScreen = $state
    $script:MockProcess = $null
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Connected $false "$state with a closed process still recovers"
    Reset-Session
    $script:MockProcess.Id = 9999
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Connected $false "$state in a different process is not the old session"
    Reset-Session
    $script:WardogsSession.JoinCode = 'another-server'
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Connected $false "$state does not confirm another server"
    $script:WardogsSession = $null
    $result = Get-WardogsConnectionState -Config $config -Server $server
    Assert-Equal $result.Connected $false "$state requires an established join session"
}

# Execute the engine's actual uncertain-state branch without launching the engine.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $basePath 'HLLVSeeding.ps1'), [ref]$null, [ref]$null)
$unknownBranch = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -match 'wardogs.*!\$connectionState.Known'
}, $true))
Assert-Equal $unknownBranch.Count 1 'Engine has one WARDOGS uncertain-state branch'
function Write-Log { param($Message) $script:LastMessage = $Message }
function Wait-WithDashboardCountdown { param($Seconds, $PlayerName, $ServerStatuses, $Message) $script:Waits++ }
function Stop-Game { throw 'An uncertain connection must never close the game.' }
$script:Waits = 0
$gameConfig = [pscustomobject]@{ gameId = 'wardogs'; pollSeconds = 60 }
$connectionState = [pscustomobject]@{ Known = $false; Connected = $null; Detail = 'Connection unverified; keeping WARDOGS open.' }
$steamName = 'Test player'
$serverStatuses = @()
$guard = [scriptblock]::Create("foreach (`$scan in 1..3) { $($unknownBranch[0].Extent.Text); throw 'Uncertain state fell through to disconnect handling.' }")
. $guard
Assert-Equal $script:Waits 3 'Engine waits and continues instead of reaching disconnect handling'
Assert-Equal $script:LastMessage $connectionState.Detail 'Engine explains that the connection is unverified'
"PASS: $script:Checks WARDOGS connection checks. No game launched or input sent."
