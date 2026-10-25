# MeshCore Servicer

Nativní desktopová aplikace pro MeshCore companiony a vzdálenou správu repeaterů.
České rozhraní pro **macOS a Windows**, zprávy, konzole s nápovědou a diagnostika.
Nezávislý komunitní projekt, nejde o oficiální aplikaci MeshCore.

**Spojení:** počítač → Bluetooth LE → companion → LoRa → repeater.
Repeater se nespravuje přímým BLE připojením.

## Instalace

Instalační soubory jsou v části **Releases** tohoto repozitáře. Zdrojový ZIP
z tlačítka Code slouží vývojářům.

| Systém | Balíček | Instalace |
|---|---|---|
| macOS 14+, Apple Silicon i Intel | `MeshCoreServicer-0.7.0-macOS-universal.dmg` | Otevřít a přetáhnout aplikaci do Aplikací |
| Windows 11, Intel/AMD | `MeshCoreServicer-0.7.3-Windows-x64-Setup.exe` | Spustit instalátor pro aktuální účet |
| Windows 11 na ARM | `MeshCoreServicer-0.7.3-Windows-arm64-Setup.exe` | Spustit ARM64 instalátor |

macOS vydání 0.7.0 má Developer ID podpis a notarizaci Apple; ověřte přiložený
`.sha256` a `.validation.json`. Windows instalátory 0.7.3 zatím nemají digitální
podpis. Sestavení ze zdrojů ani libovolná upravená kopie automaticky podpis
vydavatele nezískává.

## Funkce

- BLE skenování, připojení a obnova spojení; stav, firmware a baterie companionu.
- Kontakty, příjem advertů, objevování uzlů a ověření dostupnosti.
- Přímé a kanálové zprávy, lokální historie, volitelná oznámení a počet
  skutečně zachycených přeposlaných kopií kanálové zprávy.
- Správa repeateru přes LoRa: konfigurace, rádio, intervaly advertů, čas,
  telemetrie, sousedé, ACL, hesla, regiony a restart s potvrzením.
- Prvotní nastavení s volitelným českým komunitním profilem a kontrolou změn.
- Konzole s historií, místní nápovědou a doplňováním; snímky konfigurace,
  ruční monitoring a diagnostický export.

Hesla se ukládají do macOS Keychain nebo Windows Credential Manager. Aplikace
neobsahuje osobní profily ani přednastavené soukromé uzly. Připojení samo nemění
konfiguraci ani nevysílá advert/discovery. Podpora operace se posuzuje podle
skutečné odpovědi zařízení. Mapa a room server chat nejsou implementované.

## Sestavení a testy

**macOS:** Xcode s podporou macOS 14+ a Swift 5.9+. Otevřete
`macOS/MeshCoreServicer.xcodeproj`, vyberte schéma `MeshCoreServicer` a spusťte je.
Ve veřejném exportu je lokální ad-hoc podpis bez osobního vývojářského týmu.
Testy parseru a aplikační logiky spustí `swift test --package-path macOS`.

**Windows:** .NET 10 SDK a Windows SDK, případně Visual Studio s podporou .NET
10 a WPF. Z adresáře `Windows`:

```powershell
dotnet run --project tests/MeshCore.Tests -c Release
dotnet build MeshCoreServicer.slnx -c Release
.\build.ps1 -Runtime win-x64
```

Pro ARM použijte `-Runtime win-arm64`. WPF a Windows BLE vyžadují Windows.
Pythonové kontroly balení z kořene projektu:

```sh
python3 -m unittest discover -s macOS/scripts -p 'test_*.py'
python3 -m unittest discover -s Windows/scripts -p 'test_*.py'
python3 -m unittest discover -s Windows/installer -p 'test_*.py'
```

## Struktura a dokumentace

Jeden repozitář obsahuje dvě rovnocenné složky: `macOS/` a `Windows/`.
Každá obsahuje vlastní projekt, zdroje, testy a nástroje pro sestavení.

| Cesta | Obsah |
|---|---|
| `macOS/Sources/MeshCoreKit`, `macOS/Tests/MeshCoreKitTests` | Swift transport, protokol a testy |
| `macOS/Sources/MeshCoreServicer`, `macOS/Tests/AppModelTests` | macOS SwiftUI a aplikační logika |
| `macOS/Config`, `macOS/MeshCoreServicer.xcodeproj` | macOS projekt, ikona a oprávnění |
| `Windows/src`, `Windows/tests` | Nativní C#/WPF port a testy |
| `Windows/installer` | Sestavení Windows instalátorů |
| `macOS/scripts`, `Windows/scripts` | Nástroje pro sestavení, balení a veřejný export |
| `macOS/docs`, `.github` | Návody a šablony hlášení chyb |

- [Podrobný návod macOS](macOS/docs/MACOS.md), [Windows](Windows/README.md).
- [Protokol a připnuté revize](macOS/PROTOCOL.md), [protokol Windows portu](Windows/PROTOCOL.md).
- [Kompatibilita macOS](macOS/COMPATIBILITY.md), [Windows](Windows/COMPATIBILITY.md),
  [ruční ověření hardwaru](macOS/HARDWARE_CHECKLIST.md).
- [Podpis a notarizace macOS](macOS/scripts/MACOS_DISTRIBUTION.md),
  [Windows instalátory](Windows/installer/README.md).
- [Přispívání](CONTRIBUTING.md).

Automatické testy a sestavení nenahrazují ověření BLE/LoRa na konkrétním
hardwaru. Stav skutečných zkoušek je uvedený v návodech a kompatibilitě.

## Licence

[MIT](LICENSE). Licence a oznámení přibalených runtime komponent Windows jsou
zachované ve [Windows/ThirdParty](Windows/ThirdParty/README.md). Firmware MeshCore
ani meshcore.js se do aplikace nepřibalují; jejich zdrojové revize slouží jako
reference pro implementaci protokolu.
