#requires -Version 5.1
[CmdletBinding()]
param([string]$SdkDirectory)

$ErrorActionPreference = 'Stop'
$deps = Join-Path $PSScriptRoot '.deps'
& "$PSScriptRoot/tools/Prepare-RengaRuntime.ps1" -Destination $deps -SdkDirectory $SdkDirectory

$stylesZip = Join-Path $deps 'Renga.WPF.Styles.zip'
$stylesUrl = 'https://github.com/RengaSoftware/RengaWpfStyles/releases/download/v1.0.0.0/Relnga.WPF.Styles.zip'
Invoke-WebRequest $stylesUrl -UseBasicParsing -OutFile $stylesZip
if ((Get-FileHash $stylesZip -Algorithm SHA256).Hash -ne 'cd3bbf049ad32599b9b016d6e45d7cad4d0dc61c8ecbdc32d73dbca24ed643fa') {
    throw 'Unexpected Renga.WPF.Styles v1.0.0.0 archive.'
}
$archive = [IO.Compression.ZipFile]::OpenRead($stylesZip)
try {
    [IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry('Renga.WPF.Styles.dll'), (Join-Path $deps 'Renga.WPF.Styles.dll'), $true)
} finally {
    $archive.Dispose()
}

$project = Join-Path $PSScriptRoot 'src/LibraryComponentEditor'
dotnet build "$project/LibraryComponentEditor.csproj" -c Release
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed ($LASTEXITCODE)." }

$output = Join-Path $project 'bin/Release/net48'
$package = Join-Path $PSScriptRoot 'artifacts/LibraryComponentEditor'
[IO.Directory]::CreateDirectory($package) | Out-Null
foreach ($file in 'LibraryComponentEditor.dll', 'LibraryComponentEditor.rndesc', 'Renga.WPF.Styles.dll') {
    Copy-Item -LiteralPath (Join-Path $output $file) -Destination $package -Force
}
dotnet build "$PSScriptRoot/tools/Setup/Setup.csproj" -c Release
if ($LASTEXITCODE -ne 0) { throw "Setup build failed ($LASTEXITCODE)." }
Copy-Item -LiteralPath "$PSScriptRoot/tools/Setup/bin/Release/net48/Setup.exe" -Destination $package -Force
Copy-Item -LiteralPath "$PSScriptRoot/LICENSE", "$PSScriptRoot/third-party/Renga.WPF.Styles.LICENSE.txt" -Destination $package -Force
Write-Output "Preview package: $package"
