param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64', [switch]$VerifyUI, [switch]$Installer, [string]$Makensis = '', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    dotnet run --project tests/MeshCore.Tests -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Testy selhaly; publikace zastavena.' }
    $destination = Join-Path $PSScriptRoot "out/$Runtime"
    dotnet publish src/MeshCore.Windows/MeshCore.Windows.csproj -c Release -r $Runtime --self-contained true -p:UseSharedCompilation=false -o $destination
    if ($LASTEXITCODE -ne 0) { throw 'Sestavení selhalo.' }
    Copy-Item README.md, PROTOCOL.md, COMPATIBILITY.md, verify-ui.ps1 -Destination $destination
    Copy-Item installer/README.md (Join-Path $destination 'INSTALLER.md')
    Copy-Item LICENSE (Join-Path $destination 'LICENSE.txt')
    Copy-Item ThirdParty -Destination $destination -Recurse -Force
    # Preserve the notices from the exact runtime versions chosen by this SDK.
    $cache = $env:NUGET_PACKAGES
    if (-not $cache) { $cache = Join-Path $env:USERPROFILE '.nuget/packages' }
    $config = Get-Content (Join-Path $destination 'MeshCoreServicer.runtimeconfig.json') -Raw | ConvertFrom-Json
    foreach ($framework in $config.runtimeOptions.includedFrameworks) {
        $package = "$($framework.name.ToLowerInvariant()).runtime.$Runtime"
        if ($framework.name -eq 'Microsoft.WindowsDesktop.App') { $package = "microsoft.windowsdesktop.app.runtime.$Runtime" }
        $packagePath = Join-Path $cache "$package/$($framework.version)"
        if (Test-Path $packagePath) {
            foreach ($notice in Get-ChildItem $packagePath -File | Where-Object { $_.Name -match '^(LICENSE|THIRD-PARTY-NOTICES)' }) {
                Copy-Item $notice.FullName (Join-Path $destination "ThirdParty/$package-$($notice.Name)") -Force
            }
        }
    }
    if ($VerifyUI) { & (Join-Path $PSScriptRoot 'verify-ui.ps1') -Executable (Join-Path $destination 'MeshCoreServicer.exe') }
    $archive = Join-Path $PSScriptRoot "out/MeshCoreServicer-Windows-$($Runtime.Replace('win-', '')).zip"
    Compress-Archive -Path "$destination/*" -DestinationPath $archive -Force
    Write-Host "Vytvořeno: $archive"
    if ($Installer) {
        & $Python -m unittest discover -s installer -p 'test_*.py'
        if ($LASTEXITCODE -ne 0) { throw 'Testy balení instalátoru selhaly.' }
        $arguments = @('installer/build_installer.py', '--runtime', $Runtime)
        if ($Makensis) { $arguments += @('--makensis', $Makensis) }
        & $Python @arguments
        if ($LASTEXITCODE -ne 0) { throw 'Sestavení instalátoru selhalo.' }
    }
} finally { Pop-Location }
