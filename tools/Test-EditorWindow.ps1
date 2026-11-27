#requires -Version 5.1
param([Parameter(Mandatory)][string]$PluginDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms
$directory = (Resolve-Path -LiteralPath $PluginDirectory).ProviderPath
[xml]$descriptor = Get-Content -LiteralPath (Join-Path $directory 'LibraryComponentEditor.rndesc') -Raw
if ($descriptor.RengaPlugin.PluginType -ne 'Net' -or $descriptor.RengaPlugin.RequiredAPIVersion -ne '2.51') {
    throw 'The descriptor must identify a .NET Framework plugin for API 2.51.'
}
[Reflection.Assembly]::LoadFrom((Join-Path $directory 'Renga.WPF.Styles.dll')) | Out-Null
$module = [Reflection.Assembly]::LoadFrom((Join-Path $directory $descriptor.RengaPlugin.PluginFilename))
$pluginType = $module.GetType('LibraryComponentEditor.Plugin', $true)
$open = $pluginType.GetMethod('OpenEditor', [Reflection.BindingFlags]'Instance, NonPublic')

function Get-Editors {
    [Windows.PresentationSource]::CurrentSources | ForEach-Object { $_.RootVisual } |
        Where-Object { $_ -and $_.GetType().FullName -eq 'LibraryComponentEditor.EditorWindow' }
}
function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

# Exercise the WPF lifecycle from a host window without loading Renga or creating a project.
$hostWindow = New-Object Windows.Window
$first = [Activator]::CreateInstance($pluginType)
$second = [Activator]::CreateInstance($pluginType)
try {
    $hostWindow.Show()
    $handle = [Windows.Interop.WindowInteropHelper]::new($hostWindow).Handle
    $open.Invoke($first, @($handle))
    $editor = Get-Editors
    Assert ($editor.Title -eq 'Library Component Editor' -and $editor.WindowState -eq 'Maximized') 'Unexpected startup state.'
    Assert ($editor.WindowStyle -eq 'SingleBorderWindow' -and $editor.ResizeMode -eq 'CanResize') 'Missing native window controls.'
    $interop = [Windows.Interop.WindowInteropHelper]::new($editor)
    Assert ($interop.Owner -eq [IntPtr]::Zero -and $hostWindow.IsEnabled) 'The editor must be independent of the host.'
    Assert ([Windows.Forms.Screen]::FromHandle($interop.Handle).DeviceName -eq [Windows.Forms.Screen]::FromHandle($handle).DeviceName) 'Wrong startup monitor.'
    Assert ($editor.RestoreBounds.Width -gt 0 -and $editor.RestoreBounds.Height -gt 0) 'Missing restore bounds.'

    foreach ($state in 'Maximized', 'Normal') {
        $editor.WindowState = $state
        if ($state -eq 'Normal') {
            $editor.Width = $editor.MinWidth
            $editor.Height = $editor.MinHeight
        }
        $editor.UpdateLayout()
        foreach ($name in 'ConstructionPane', 'WorkSurface', 'SourcesPane', 'ParametersPane') {
            $pane = $editor.FindName($name)
            Assert ($pane.IsVisible -and $pane.ActualWidth -gt 0 -and $pane.ActualHeight -gt 0) "Missing layout area in the $state window: $name."
            Assert ($pane.Background -and $pane.BorderBrush) "Missing Renga surface or border brush on $name."
        }
        $editor.WindowState = 'Minimized'
        $open.Invoke($first, @($handle))
        Assert ($editor.WindowState -eq $state -and @(Get-Editors).Count -eq 1) 'Repeat activation lost the original window state.'
    }
    $open.Invoke($second, @($handle))
    Assert (@(Get-Editors).Count -eq 2) 'Plugin instances shared an editor.'
    $editor.Close()
    $open.Invoke($first, @($handle))
    Assert (@(Get-Editors).Count -eq 2) 'The closed editor did not reopen.'
    $first.Stop()
    Assert (@(Get-Editors).Count -eq 1) 'Stopping the first instance affected the second.'
    $second.Stop()
    Assert (@(Get-Editors).Count -eq 0) 'An editor remained open after shutdown.'
    Write-Output 'Editor window checks passed.'
} finally {
    $first.Stop()
    $second.Stop()
    $hostWindow.Close()
}
