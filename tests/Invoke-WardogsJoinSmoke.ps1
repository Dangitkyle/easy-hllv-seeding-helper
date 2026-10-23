param([string]$ServerNumber = 'EAST')
$ErrorActionPreference = 'Stop'
$basePath = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $basePath 'WardogsSupport.ps1')

# Import only the engine's desktop helpers, without starting its launch/restart loop.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $basePath 'HLLVSeeding.ps1'), [ref]$null, [ref]$null)
$source = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$ClickerSource'
}, $true)
. ([scriptblock]::Create($source.Extent.Text))
Add-Type -TypeDefinition $ClickerSource -ReferencedAssemblies System.Windows.Forms,System.Drawing
$helperNames = @('Get-GameProcesses', 'Get-GameWindow', 'Get-GameWindowBounds', 'Convert-UiPointToScreenPoint', 'Invoke-GameClick', 'Invoke-LeftClick', 'Set-GameForeground')
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($definition.Name -in $helperNames) { . ([scriptblock]::Create($definition.Extent.Text)) }
}
function Write-Log { param([string]$Message) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" }
$config = Get-Content -LiteralPath (Join-Path $basePath 'servers.json') -Raw | ConvertFrom-Json
Initialize-WardogsConfig -Config $config
$game = $config.wardogs
$game | Add-Member -NotePropertyName gameId -NotePropertyValue 'wardogs' -Force
$server = @($game.servers | Where-Object { $_.number -eq $ServerNumber })
if ($server.Count -ne 1) { throw 'Choose one configured WARDOGS server.' }
try {
    Start-WardogsServer -Config $game -Server $server[0]
    Start-Sleep -Seconds 12
    if (!$script:WardogsActivityState.LastClick) {
        throw "Joined, but activity click was not confirmed. Screen: $($script:WardogsActivityState.LastScreen). Error: $($script:WardogsActivityState.Error)"
    }
    Write-Log "PASS: joined $ServerNumber and observed activity clicks. Last click: $($script:WardogsActivityState.LastClick)."
} finally {
    Stop-WardogsActivity
}
