param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$PayloadManifest,
    [switch]$DisposableTestEnvironment
)
$ErrorActionPreference = 'Stop'
if (-not $DisposableTestEnvironment) { throw 'Použijte pouze čistý testovací účet/VM a výslovný přepínač -DisposableTestEnvironment.' }
$Installer = (Resolve-Path $Installer).Path
$manifest = Get-Content $PayloadManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs/MeshCore Servicer'
$dataRoot = Join-Path $env:LOCALAPPDATA 'MeshCoreServicer'
$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
$key = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\MeshCoreServicer'
$existing = $registry.OpenSubKey($key)
if ($existing -or (Test-Path $installRoot) -or (Test-Path $dataRoot)) { throw 'Test vyžaduje čistý účet bez existující instalace a historie MeshCore Servicer. Nic nebylo změněno.' }
function Run-Setup([int]$expected = 0) {
    $process = Start-Process $Installer -ArgumentList '/S' -PassThru -Wait
    if ($process.ExitCode -ne $expected) { throw "Instalátor vrátil $($process.ExitCode), očekáváno $expected." }
}
function Verify-Payload {
    foreach ($file in $manifest.Files) {
        $path = Join-Path $installRoot $file.Path
        if (-not (Test-Path -LiteralPath $path)) { throw "Chybí $($file.Path)." }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Odlišný obsah $($file.Path)." }
    }
    $entry = $registry.OpenSubKey($key)
    if (-not $entry -or $entry.GetValue('DisplayVersion') -ne $manifest.Version -or $entry.GetValue('Architecture') -ne $manifest.Architecture) { throw 'Nesouhlasí registrace aplikace.' }
    $entry.Dispose()
}
Run-Setup
Verify-Payload
Write-Host 'Čistá tichá instalace a všechny hashe: OK'
# A sentinel belongs to the isolated test account, not to a real user archive.
New-Item -ItemType Directory -Path $dataRoot | Out-Null
$sentinel = Join-Path $dataRoot 'installer-test-preserve.txt'
Set-Content $sentinel 'preserve-test-data' -Encoding UTF8
$extra = Join-Path $installRoot 'user-file-to-preserve.txt'
Set-Content $extra 'preserve-extra-file' -Encoding UTF8
Run-Setup
Verify-Payload
Write-Host 'Opakovaná instalace / oprava: OK'
$created = $false
$mutex = [Threading.Mutex]::new($false, 'Local\MeshCoreServicer.Windows', [ref]$created)
if (-not $created) { $mutex.Dispose(); throw 'Aplikace nebo jiný test už běží.' }
try { Run-Setup 1618 } finally { $mutex.Dispose() }
Verify-Payload
Write-Host 'Blokace běžící aplikace: OK'
$entry = $registry.OpenSubKey($key, $true)
$entry.SetValue('DisplayVersion', '99.0.0')
try { Run-Setup 1638 } finally { $entry.SetValue('DisplayVersion', $manifest.Version); $entry.Dispose() }
Verify-Payload
Write-Host 'Odmítnutí downgrade: OK'
$uninstaller = Join-Path $installRoot 'Uninstall.exe'
$process = Start-Process $uninstaller -ArgumentList @('/S', ('_?=' + $installRoot)) -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "Odinstalace selhala: $($process.ExitCode)" }
foreach ($file in $manifest.Files) { if (Test-Path -LiteralPath (Join-Path $installRoot $file.Path)) { throw "Po odinstalaci zůstal $($file.Path)." } }
if ($registry.OpenSubKey($key)) { throw 'Zůstala registrace aplikace.' }
if ((Get-Content $sentinel -Raw).Trim() -ne 'preserve-test-data' -or (Get-Content $extra -Raw).Trim() -ne 'preserve-extra-file') { throw 'Osobní nebo přidaný soubor nebyl zachovaný.' }
$registry.Dispose()
Write-Host 'Odinstalace a zachování osobních i přidaných souborů: OK'
Write-Host 'Test neověřuje BLE, změnu nastavení zařízení, skutečný upgrade z jiné vydané verze ani podpis/SmartScreen. Testovací sentinel a přidaný soubor zůstaly v izolovaném účtu.'
