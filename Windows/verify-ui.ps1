param(
    [string]$Executable = '',
    [string]$Output = (Join-Path $PSScriptRoot 'out/ui-verification')
)
$ErrorActionPreference = 'Stop'
if (-not $Executable) {
    $Executable = Join-Path $PSScriptRoot 'MeshCoreServicer.exe'
    if (-not (Test-Path $Executable)) { $Executable = Join-Path $PSScriptRoot 'out/win-x64/MeshCoreServicer.exe' }
}
if (-not (Test-Path $Executable)) { throw 'Nejdříve aplikaci sestavte nebo určete cestu k EXE pomocí -Executable.' }
$target = [System.IO.Path]::GetFullPath($Output)
$process = Start-Process -FilePath $Executable -ArgumentList @('--verify-ui', ('"' + $target + '"')) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Kontrola UI selhala. Podrobnosti: $target/result.json" }
Write-Host "WPF kontrola rozložení dokončena: 7 obrazovek × 2 vzhledy × 5 velikostí / měřítek (70 PNG): $target"
Write-Host 'Jde o prázdné skutečné WPF obrazovky. BLE, párování a fyzické zařízení tím nejsou otestované.'
Write-Host 'Změnu DPI skutečného monitoru a čitelnost je nutné ověřit ručně; PNG nejsou fyzický test DPI.'
