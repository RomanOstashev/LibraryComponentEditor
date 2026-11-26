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
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace LibraryComponentEditor.Setup
{
    public sealed class InteropImporter : ITypeLibImporterNotifySink
    {
        private readonly string directory;

        private InteropImporter(string directory) { this.directory = directory; }

        [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void LoadTypeLibEx(string file, int registration, out ITypeLib library);

        public static void Import(string tlb, string directory)
        {
            ITypeLib library;
            LoadTypeLibEx(tlb, 2 /* REGKIND_NONE */, out library);
            try { new InteropImporter(directory).ResolveRef(library); }
            finally { Marshal.ReleaseComObject(library); }
        }

        public Assembly ResolveRef(object typeLib)
        {
            var name = Marshal.GetTypeLibName((ITypeLib)typeLib);
            var file = "Interop." + name + ".dll";
            var assembly = new TypeLibConverter().ConvertTypeLibToAssembly(typeLib,
                Path.Combine(directory, file), TypeLibImporterFlags.ImportAsX64,
                this, null, null, name, null);
            assembly.Save(file);
            return assembly;
        }

        public void ReportEvent(ImporterEventKind kind, int code, string message)
        {
            if (kind == ImporterEventKind.ERROR_REFTOINVALIDTYPELIB)
                throw new InvalidOperationException(message);
        }
    }
}
'@
    }
    $tlb = (Resolve-Path -LiteralPath (Join-Path $SdkDirectory 'tlb/RengaCOMAPI.tlb')).ProviderPath
    [LibraryComponentEditor.Setup.InteropImporter]::Import($tlb, $work.FullName)
    $destinationPath = [IO.Directory]::CreateDirectory($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)).FullName
    Copy-Item -LiteralPath (Join-Path $SdkDirectory 'Net/Renga.NET.PluginUtility.dll') -Destination $destinationPath -Force
    Copy-Item -Path (Join-Path $work.FullName 'Interop.*.dll') -Destination $destinationPath -Force
} finally {
    Remove-Item -LiteralPath $work.FullName -Recurse -Force
}
