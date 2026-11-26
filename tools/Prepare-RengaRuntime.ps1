#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Destination = $PSScriptRoot,
    [string]$SdkDirectory
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    throw 'Run this script with 64-bit Windows PowerShell 5.1 (powershell.exe).'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$work = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))
try {
    $sdkFiles = [ordered]@{
        'Net/Renga.NET.PluginUtility.dll' = 'a9d6b126f468648b5c6fa8351775380086e05f432c44259f550a72ff773f4279'
        'tlb/RengaCOMAPI.tlb' = '0d458a600bd1543917f9c6f3618d23c1283972bf634c293bfca5f8cd39884897'
    }
    if (-not $SdkDirectory) {
        $zip = Join-Path $work.FullName 'RengaSDK.zip'
        Invoke-WebRequest 'https://dl.rengabim.com/SDK/RengaSDK.zip' -OutFile $zip -UseBasicParsing
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($relative in $sdkFiles.Keys) {
                $target = Join-Path $work.FullName $relative
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry($relative), $target)
            }
        } finally {
            $archive.Dispose()
        }
        $SdkDirectory = $work.FullName
    }
    foreach ($relative in $sdkFiles.Keys) {
        $file = Join-Path $SdkDirectory $relative
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $sdkFiles[$relative]) {
            throw "Unexpected $relative. Specify -SdkDirectory with the extracted Renga SDK 2.51 for Renga 9.4.34553."
        }
    }

    # Generate the managed COM wrapper on this computer using the .NET Framework runtime.
    if (-not ('LibraryComponentEditor.Setup.InteropImporter' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot "Setup/InteropImporter.cs")
    }
    $tlb = (Resolve-Path -LiteralPath (Join-Path $SdkDirectory 'tlb/RengaCOMAPI.tlb')).ProviderPath
    [LibraryComponentEditor.Setup.InteropImporter]::Import($tlb, $work.FullName)
    $destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    [IO.Directory]::CreateDirectory($destinationPath) | Out-Null
    Copy-Item -LiteralPath (Join-Path $SdkDirectory 'Net/Renga.NET.PluginUtility.dll') -Destination $destinationPath -Force
    Copy-Item -Path (Join-Path $work.FullName 'Interop.*.dll') -Destination $destinationPath -Force
    Write-Output "Renga runtime is ready in $destinationPath"
} finally {
    Remove-Item -LiteralPath $work.FullName -Recurse -Force
}
