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

    $editor.UpdateLayout()
    $tree = $editor.FindName('ConstructionTree')
    $root = $editor.FindName('TemplateNode')
    $geometry = $editor.FindName('GeometryNode')
    $card = $editor.FindName('ParametersCard')
    $views = $editor.FindName('ViewTabs')
    $workSurface = $editor.FindName('WorkSurface')
    $tools = $editor.FindName('ToolSlots')
    $actions = $editor.FindName('ActionSlots')
    $inspector = $editor.FindName('InspectorTabs')
    $sources = $editor.FindName('SourcesPane')
    $sourceTabs = $editor.FindName('SourceTabs')

    Assert ($tree.IsVisible -and $tree.SelectedItem -eq $root -and $card.Content -eq $root.Header) 'The layout did not open at the root of the template.'
    Assert ($views.Items.Count -eq 1 -and $workSurface.IsVisible -and $editor.FindName('ViewCube').IsVisible) 'Missing default 3D workspace or view cube.'
    Assert ($editor.FindName('TemplateCommandBar').IsVisible -and $tools.Columns -eq 5 -and $actions.Columns -eq 5) 'Missing editor command areas.'
    $geometry.IsSelected = $true
    $editor.UpdateLayout()
    Assert ($card.Content -eq $geometry.Header -and $card.ContentTemplate -eq $geometry.Tag) 'The parameters card did not follow the tree selection.'
    $root.IsSelected = $true

    Assert ($inspector.Items.Count -eq 2 -and $sourceTabs.Items.Count -eq 2 -and $sourceTabs.IsVisible) 'Missing inspector or source tabs.'
    $inspector.SelectedIndex = 1
    $sourceTabs.SelectedIndex = 1
    $editor.UpdateLayout()
    Assert ($inspector.SelectedContent.IsVisible -and $sourceTabs.SelectedContent.IsVisible -and $workSurface.IsVisible) 'Switching tabs hid the 3D workspace or left a tab empty.'
    $sources.IsExpanded = $false
    $editor.UpdateLayout()
    Assert (-not $sourceTabs.IsVisible -and $workSurface.IsVisible) 'Collapsing the sources must leave the workspace open.'
    $sources.IsExpanded = $true
    $editor.UpdateLayout()
    Assert ($sourceTabs.IsVisible) 'The sources did not reopen.'

    foreach ($state in 'Maximized', 'Normal') {
        $editor.WindowState = $state
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
