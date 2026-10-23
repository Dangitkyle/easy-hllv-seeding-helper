param([string]$PreviewPath = '')
$ErrorActionPreference = 'Stop'
$basePath = Split-Path -Parent $PSScriptRoot
. (Join-Path $basePath 'WardogsSupport.ps1')
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $basePath 'EASYHLLVSeedingUI.ps1'), [ref]$null, [ref]$null)
foreach ($statement in $ast.EndBlock.Statements) {
    $text = $statement.Extent.Text
    if ($text -eq '[void]$form.ShowDialog()' -or $text.StartsWith('$form.Add_Shown(') -or
        $text -eq ". (Join-Path `$PSScriptRoot 'WardogsSupport.ps1')") { continue }
    . ([scriptblock]::Create($text))
}
try {
    Set-UiRunningState -Running $false
    Update-GameSelectionPresentation -UpdateReadyMessage
    if ($form.Text -ne 'EASY Seeding Helper v3.0.0') { throw 'Incorrect window version.' }
    if ($script:ServerRows.Count -ne 9) { throw 'Expected nine server rows.' }
    foreach ($row in $script:ServerRows.Values) {
        if ($row.RowPanel.Bottom -gt $serversPanel.ClientSize.Height) { throw 'Server row is clipped.' }
    }
    if ($countdownLabel.Bottom -gt $mainContentPanel.Height -or $behaviorLabel.Bottom -gt $mainContentPanel.Height) {
        throw 'Dashboard footer is clipped.'
    }
    if (!$wardogsSettingsPage -or !$compServerCheckBox) { throw 'WARDOGS settings are missing.' }
    if ($PreviewPath) {
        $form.ShowInTaskbar = $false
        $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
        $form.Location = [Drawing.Point]::new(-30000, -30000)
        $form.Show()
        $form.PerformLayout()
        $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
        try {
            $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
            $bitmap.Save($PreviewPath, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    }
    'PASS: v3.0.0 dashboard, nine server rows, footer, and WARDOGS settings layout.'
} finally {
    $form.Dispose()
    $script:StatsHttpClient.Dispose()
}
