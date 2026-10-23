$ErrorActionPreference = 'Stop'
$basePath = Split-Path -Parent $PSScriptRoot
. (Join-Path $basePath 'WardogsSupport.ps1')
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $basePath 'HLLVSeeding.ps1'), [ref]$null, [ref]$null)
$names = @('Get-GameConfigurations', 'Get-ServerStatusKey', 'Get-PrioritySeedingTarget')
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($definition.Name -in $names) { . ([scriptblock]::Create($definition.Extent.Text)) }
}
$script:Checks = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'." }
    $script:Checks++
}
function Assert-Rejected([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Equal $rejected $true $Name
}

$config = Get-Content -LiteralPath (Join-Path $basePath 'servers.json') -Raw | ConvertFrom-Json
Assert-Equal $config.version '3.0.0' 'Release version'
Initialize-WardogsConfig -Config $config
$config.enabledGames.wardogs = $true
$config.enabledGames.hllv = $true
$config.enabledGames.hllWw2 = $true
$games = @(Get-GameConfigurations -Config $config)
Assert-Equal ($games.gameId -join ',') 'wardogs,hllv,hllWw2' 'Cross-game priority'
$statuses = @()
foreach ($game in $games) {
    $index = 0
    foreach ($server in $game.servers) {
        $number = if ($server.number) { "$($server.number)" } elseif ($server.name -match '#(\d+)') { $Matches[1] } else { throw 'Missing server number.' }
        $statuses += [pscustomobject]@{
            GameId = $game.gameId
            ServerNumber = $number
            GameEnabled = $server.enabled -ne $false
            IsAvailable = $true
            IsUnderSeedThreshold = $true
            Order = $index++
        }
    }
}
function Get-TargetKey([hashtable]$Skip = @{}) {
    $target = @(Get-PrioritySeedingTarget -Statuses $statuses -Games $games -SkipUntil $Skip)
    if ($target.Count -eq 0) { return '' }
    Get-ServerStatusKey -Status $target[0]
}
Assert-Equal (Get-TargetKey) 'wardogs:EAST' 'East comes first'
$east = $statuses | Where-Object { $_.GameId -eq 'wardogs' -and $_.ServerNumber -eq 'EAST' }
$west = $statuses | Where-Object { $_.GameId -eq 'wardogs' -and $_.ServerNumber -eq 'WEST' }
$comp = $statuses | Where-Object { $_.GameId -eq 'wardogs' -and $_.ServerNumber -eq 'COMP' }
$east.IsUnderSeedThreshold = $false
Assert-Equal (Get-TargetKey) 'wardogs:WEST' 'West after East is seeded'
$west.IsUnderSeedThreshold = $false
Assert-Equal (Get-TargetKey) 'hllv:1' 'Disabled Comp is skipped'
$comp.GameEnabled = $true
Assert-Equal (Get-TargetKey) 'wardogs:COMP' 'Comp is optional and third'
$comp.GameEnabled = $false
$vietnamOne = $statuses | Where-Object { $_.GameId -eq 'hllv' -and $_.ServerNumber -eq '1' }
$vietnamOne.IsAvailable = $false
Assert-Equal (Get-TargetKey) 'hllv:2' 'Down Vietnam server is skipped'
$vietnamOne.IsAvailable = $true
Assert-Equal (Get-TargetKey) 'hllv:1' 'Recovered Vietnam server returns to priority'
foreach ($status in @($statuses | Where-Object { $_.GameId -eq 'hllv' })) { $status.IsUnderSeedThreshold = $false }
Assert-Equal (Get-TargetKey) 'hllWw2:WW2' 'WW2 after higher-priority work is complete'
$east.IsUnderSeedThreshold = $true
$west.IsUnderSeedThreshold = $true
Assert-Equal (Get-TargetKey) 'wardogs:EAST' 'Recovered Wardogs takes priority over WW2'
$skip = @{ 'wardogs:EAST' = (Get-Date).AddSeconds(60) }
Assert-Equal (Get-TargetKey -Skip $skip) 'wardogs:WEST' 'Failed connection falls through'
$skip['wardogs:EAST'] = (Get-Date).AddSeconds(-1)
Assert-Equal (Get-TargetKey -Skip $skip) 'wardogs:EAST' 'Next scan restarts at East'

$server = $config.wardogs.servers[1]
$now = [datetimeoffset]::UtcNow
$snapshot = [pscustomobject]@{
    meta = [pscustomobject]@{ fetchedAt = $now.ToString('o'); stale = $false; refreshSeconds = 180 }
    data = @([pscustomobject]@{
        serverId = $server.joinCode
        observedAt = $now.ToString('o')
        players = 0
        maxPlayers = 100
        passwordProtected = $false
        name = $server.name
    })
}
Assert-Equal (ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now).Players 0 'Empty server count is valid'
$snapshot.meta.stale = $true
Assert-Rejected { ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now } 'Stale API data is rejected'
$snapshot.meta.stale = $false
$snapshot.data[0].observedAt = $now.AddSeconds(-601).ToString('o')
Assert-Rejected { ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now } 'Carried old population is rejected'
$snapshot.data[0].observedAt = $now.ToString('o')
$snapshot.data[0].players = $null
Assert-Rejected { ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now } 'Missing population is not treated as zero'
$snapshot.data[0].players = 101
Assert-Rejected { ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now } 'Invalid population is rejected'
$snapshot.data = @()
Assert-Rejected { ConvertFrom-WardogsSnapshot -Snapshot $snapshot -Server $server -Now $now } 'Absent server is rejected'
"PASS: $script:Checks release priority and API checks."
