# MeshCore Servicer 0.10.0 · Windows

Nativní WPF aplikace s WinRT Bluetooth pro Windows 11 x64 a ARM64; bez WebView.
Počítač se připojuje přes BLE ke companionu, který zprostředkuje vzdálený
servis repeateru po LoRa. Hesla jsou ve Windows Credential Manager.
[Společný přehled](../README.md).

## Sestavení

Z kořene kompletního repozitáře s .NET 10 SDK:

```powershell
dotnet run --project Windows/tests/MeshCore.Tests -c Release
dotnet run --project Shared/tests/MeshCore.Updates.Tests -c Release
dotnet build Windows/MeshCoreServicer.slnx -c Release
dotnet publish Windows/src/MeshCore.Windows -c Release -r win-x64 --self-contained true
```

Windows projekt odkazuje na sourozeneckou složku `Shared`: protokolové jádro,
aktualizace a launcher. Samotné `Windows/src` pro sestavení nestačí.
`build.ps1` nadále slouží pro přímé vývojové sestavení; podepisovanou distribuční
strukturu připravuje `tools/package_release.py` z publikované aplikace a
launcheru. [Instalátory](installer/README.md).

## Verze 0.9.0

- Zahrnuje podrobné fáze Windows BLE, bezpečné chyby s identifikátorem, HRESULT
  a GATT/protokolovým kódem, redigovaný export i bez úspěšného připojení.
- GATT služby se načtou jednou úplnou uncached enumerací; přesná NUS služba se
  vybere místně. Nejde o důkaz opravy konkrétního Dellu/T‑Decku Plus/Wadamesh beta.
- Diagnostika má výchozí 4 h × 3, intervaly 3–24 h, nejvýše 6 vzorků/24 h.
  Ruční správa sdílí původní servisní rozpočet; historie zůstává místní.
- Potvrzované aktualizace stahují pouze změněné soubory podle podepsaného
  manifestu a SHA-256. Stabilní launcher ověří a spustí novou verzi; původní
  zůstává pro návrat. Měření ani správce se po restartu neobnovují.
- První přechod ze starší verze je přes instalátor 0.9.0. Přímé vývojové
  sestavení nemá distribuční strukturu a samo se neaktualizuje.

Připojení companionu nespouští LoRa diagnostiku ani zápisy. Instalace je pro
aktuální účet, .NET runtime je přiložený. EXE zatím nemají Authenticode podpis;
podpis aktualizačního manifestu ho pro SmartScreen nenahrazuje.

[Windows BLE audit a fyzické ověření](docs/WINDOWS_BLE.md),
[provozní limity](docs/TRAFFIC_POLICY.md), [ověření sestavení](COMPATIBILITY.md),
[protokol](PROTOCOL.md), [aktualizace](../docs/UPDATES.md).

Automatické testy používají náhradní transport a řízený čas. Cross kompilace,
extrakce instalátoru a kontrola hashů nenahrazují instalaci ve Windows,
Credential Manager, BLE adaptér ani skutečné LoRa požadavky.

## USB od 0.10.0

USB companion i přímý USB repeater: [připojení, protokol a ověření](../docs/USB.md).
Port se otevírá jen výslovně; BLE i USB současně se nepoužívají.
