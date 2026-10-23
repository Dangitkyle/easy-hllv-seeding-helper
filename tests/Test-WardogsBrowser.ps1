$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WardogsSupport.ps1')
$script:Checks = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'." }
    $script:Checks++
}

foreach ($label in @('JOIN BY ID', 'JOIN BY IO', 'JOIN BY I0', 'JOIN BY 1D', 'JOIN BY 10')) {
    $text = "// SERVER BROWSER`nCOMMUNITY`nREFRESH`nSERVER NAME`n$label`nREGION [3/3]`nHOST"
    Assert-Equal (Get-WardogsScreenKind -Text $text) 'Browser' "Recognizes $label"
    Assert-Equal ([bool]($label -match (Get-WardogsJoinByIdPattern))) $true "Finds $label to click"
}
Assert-Equal (Get-WardogsScreenKind -Text "DEPLOY`nOFFICIAL SERVERS`nCOMMUNITY SERVERS") 'BrowserType' 'Browser selection remains distinct'
Assert-Equal (Get-WardogsScreenKind -Text 'FIND SERVER ENTER SERVER ID') 'FindServer' 'Lookup dialog remains distinct'

$server = [pscustomobject]@{ searchText = 'EASY Company | NA EAST' }
foreach ($name in @('EASY Company | NA EAST | discord.gg/easycompany', 'EASY Company I NA EAST I discord.gg/easycompany')) {
    $screen = [pscustomobject]@{ Height = 1080; Lines = @([pscustomobject]@{ Text = $name; Y = 507 }) }
    Assert-Equal (Test-WardogsServerIdentity -Screen $screen -Server $server) $true 'Accepts expected server despite OCR separators'
}
$wrongServer = [pscustomobject]@{ Height = 1080; Lines = @([pscustomobject]@{ Text = 'EASY Company I NA WEST'; Y = 507 }) }
Assert-Equal (Test-WardogsServerIdentity -Screen $wrongServer -Server $server) $false 'Rejects wrong region'
$background = [pscustomobject]@{ Height = 1080; Lines = @([pscustomobject]@{ Text = 'EASY Company I NA EAST'; Y = 800 }) }
Assert-Equal (Test-WardogsServerIdentity -Screen $background -Server $server) $false 'Ignores names outside confirmation dialog'
"PASS: $script:Checks browser and server identity checks."
