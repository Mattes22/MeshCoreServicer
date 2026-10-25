# MeshCore Servicer pro macOS

Nativní aplikace ve Swiftu, SwiftUI a CoreBluetooth pro **macOS 14+**, Apple
Silicon a Intel. České rozhraní, světlý a tmavý vzhled. Nezávislý komunitní
projekt, nejde o oficiální aplikaci MeshCore.

**Spojení:** Mac → Bluetooth LE → companion → LoRa → repeater.
Repeater se nespravuje přímým BLE připojením.

## Instalace

Balíček `MeshCoreServicer-0.7.0-macOS-universal.dmg` otevřete a aplikaci
přetáhněte do Aplikací. Před nahrazením starší kopie ji ukončete přes ⌘Q.
Distribuční vydání 0.7.0 má Developer ID podpis a notarizaci Apple; přiložené
`.sha256` a `.validation.json` patří k přesnému vydanému DMG. Běžné potvrzení
prvního otevření a povolení Bluetooth řídí macOS.

## Funkce

- Připojení a obnova BLE, informace o companionu a kontakty.
- Přímé a kanálové zprávy, lokální historie a volitelná systémová oznámení.
- Počet skutečně zachycených přeposlaných kopií kanálových zpráv.
- Správa repeaterů přes LoRa, rádio, intervaly advertů a synchronizace času.
- Telemetrie, sousedé, ACL, regiony, hesla a restart s potvrzením.
- Prvotní nastavení s volitelným českým komunitním profilem.
- Konzole s historií a nápovědou, snímky konfigurace a diagnostika.

Hesla se ukládají do macOS Keychain. Připojení samo nemění konfiguraci
ani nevysílá advert/discovery. Aplikace nemá přibalené osobní profily.

## Samostatný projekt a sestavení

Tato složka obsahuje kompletní projekt. Vyžaduje Xcode s podporou macOS 14+
a Swift 5.9+. Otevřete `MeshCoreServicer.xcodeproj` a schéma
`MeshCoreServicer`. Veřejný zdrojový balíček používá lokální ad-hoc podpis
bez osobního vývojářského týmu; vlastní sestavení automaticky nezískává
podpis ani notarizaci vydavatele.

Příkazy spouštějte z kořene tohoto projektu:

```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Univerzální sestavení:

```sh
xcodebuild -project MeshCoreServicer.xcodeproj -scheme MeshCoreServicer \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath build build
```

## Struktura a dokumentace

| Cesta | Obsah |
|---|---|
| `Sources/MeshCoreKit` | Transport, protokol a korelace odpovědí |
| `Sources/MeshCoreServicer` | SwiftUI, aplikační logika a systémové služby |
| `Tests` | Testy parseru a aplikační logiky |
| `Config`, `MeshCoreServicer.xcodeproj` | Xcode projekt, ikona a oprávnění |
| `scripts`, `docs` | Sestavení, balení a dokumentace |

- [Podrobný návod](docs/MACOS.md).
- [Protokol a připnuté revize](PROTOCOL.md).
- [Kompatibilita](COMPATIBILITY.md), [ruční ověření hardwaru](HARDWARE_CHECKLIST.md).
- [Podpis a notarizace](scripts/MACOS_DISTRIBUTION.md).
- [Přispívání](CONTRIBUTING.md), [MIT licence](LICENSE).

Sestavení a automatické testy nenahrazují BLE/LoRa test na fyzickém zařízení
ani test stažení a prvního spuštění na jiném čistém Macu.

## Zdrojový balíček

`python3 scripts/package_source.py` vytvoří samostatnou zdrojovou složku,
ZIP a SHA-256 v `dist/source`. Nečte data aplikace a nezahrnuje instalátory,
cache ani podpisové klíče. Pro další balíček použijte jiné `--output`.
