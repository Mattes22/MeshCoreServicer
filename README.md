# MeshCore Servicer 0.10.0

Nativní desktopová aplikace pro MeshCore companiony a vzdálenou správu repeaterů.
České rozhraní pro **macOS, Windows a Ubuntu/Debian x64 a ARM64**. Nezávislý komunitní
projekt; nejde o oficiální aplikaci MeshCore.

**Spojení:** počítač → Bluetooth LE / USB → companion → LoRa → repeater.
Přímý USB repeater má samostatnou místní správu bez companionu.
Připojení companionu samo nemění konfiguraci ani nespouští LoRa diagnostiku.

## Novinky 0.10.0

USB companion a přímý USB repeater na macOS, Windows i Linuxu. Vyberte režim
v Připojení → Připojení přes USB, obnovte seznam portů a výslovně se připojte.
USB companion používá stávající síťové funkce; přímý repeater má vlastní místní
správu a konzoli. Je potřeba odpovídající firmware, BLE firmware nelze USB kabelem
automaticky změnit na USB companion. [USB protokol, použití a ověření](docs/USB.md).

Distribuce 0.10.0 obsahuje macOS DMG, Windows instalátory a Linux DEB pro obě
architektury. Připravené aktualizační feedy nabízejí stejnou verzi; na vlastním
serveru se projeví až po nahrání nových souborů a metadat.

## Novinky 0.9.1

Linux balíčky opravují závislost ICU pro Ubuntu 26.04. Systémová ICU 78 je
podporovaná spolu s verzemi 70/72/74/76; není nutné přidávat starou ICU z jiné
distribuce. Balíčky obsahují také opravu adresářů z 0.9.0-1. V tomto dílčím vydání zůstaly instalátory
macOS/Windows na 0.9.0; následující 0.10.0 už má nové balíčky všech platforem.

## Funkce od 0.9.0

- Linux port: Avalonia, BlueZ přes systémový D-Bus, systémové párování,
  klíčenka Secret Service a balíčky `.deb` pro x64 a ARM64. Žádný WebView.
- Kontrola aktualizací z `https://servicer.zavadilmatej.cz/updates/` při spuštění,
  potom přibližně jednou denně; lze vypnout. Instalace vyžaduje potvrzení.
- Windows/Linux stahují pouze soubory, jejichž SHA-256 se liší od nové verze.
  Podepsaný manifest, izolovaná příprava, přepnutí verze a restart aplikace.
- macOS používá Sparkle 2.10.1: podepsané rozdílové aktualizace, případně úplný
  podepsaný balíček, pokud rozdíl pro původní verzi není dostupný/použitelný.
- Zahrnuté změny 0.8.1/0.8.2: podrobná Windows BLE diagnostika a cílená GATT
  úprava, bezpečná migrace a výchozí diagnostický plán **4 h × 3**.

**První přechod z 0.8.x vyžaduje standardní instalaci 0.9.0 nebo novější.** Starší aplikace
aktualizační klient neobsahuje. Vývojová sestavení bez distribučního podpisu
manifestu nelze tímto mechanismem aktualizovat. Detaily: [Aktualizace](docs/UPDATES.md).

## Instalace

| Systém | Distribuční balíček | Instalace |
|---|---|---|
| macOS 14+, Apple Silicon/Intel | `MeshCoreServicer-0.10.0-macOS-universal-build15.dmg` | Přetáhnout aplikaci do Aplikací |
| Windows 11, Intel/AMD | `MeshCoreServicer-0.10.0-Windows-x64-Setup.exe` | Instalátor pro aktuální účet |
| Windows 11 na ARM | `MeshCoreServicer-0.10.0-Windows-arm64-Setup.exe` | ARM64 instalátor |
| Ubuntu 22.04/24.04/26.04, Debian 12/13, x64 desktop | `meshcore-servicer_0.10.0-1_amd64.deb` | `sudo apt install ./meshcore-servicer_0.10.0-1_amd64.deb` |
| Ubuntu 22.04/24.04/26.04, Debian 12/13, ARM64 desktop | `meshcore-servicer_0.10.0-1_arm64.deb` | `sudo apt install ./meshcore-servicer_0.10.0-1_arm64.deb` |

Distribuční macOS DMG má Developer ID podpis a notarizaci Apple. Windows EXE
jsou bez Authenticode podpisu; podpis aktualizačních manifestů nenahrazuje
podpis instalátoru pro SmartScreen. Linux balíček vyžaduje BlueZ, desktopový
D-Bus a Secret Service; závislosti doplní APT. ARM64 vyžaduje 64bitový operační systém a grafickou relaci; nejde o balíček armhf.

Balíčky se připravují místně; tento repozitář neznamená jejich automatické
veřejné publikování. Kontrolujte odpovídající SHA-256 a ověřovací záznam vydání.

## Funkce

- BLE skenování, systémové párování a připojení, firmware a baterie companionu.
- Kontakty, adverty, discovery/ping a rozlišení uloženého kontaktu od dostupnosti.
- Přímé/kanálové zprávy, místní historie, oznámení a skutečně zachycené kopie
  přeposlaných kanálových zpráv; počet kopií není počet unikátních uzlů ani ACK.
- Vzdálená konfigurace, rádio, intervaly advertů, čas, statistiky, telemetrie,
  sousedé, ACL, hesla, regiony a restart s potvrzením.
- Prvotní nastavení s volitelným českým profilem, kontrola a potvrzování změn.
- Konzole s místní nápovědou/doplňováním, snímky konfigurace a redigovaný export.

Hesla patří do Keychain, Credential Manager nebo Secret Service. Profily ani
soukromé uzly nejsou součástí distribuce. Podpora konkrétního vzdáleného příkazu
se posuzuje podle skutečné odpovědi zařízení. Mapa a room server chat nejsou
implementované. [Linux podrobnosti a fyzické ověření](Linux/README.md).

## Šetrná diagnostika

Měření je standardně vypnuté a vyžaduje výslovné spuštění. Výchozí plán jsou
3 vzorky po 4 hodinách: první po 4 h, poslední po 12 h. Povolený interval
3–24 h, nejvýše 6 vzorků a celková délka do 24 h. Historie/grafy jsou místní.
Každý vzorek aktivně vyšle LoRa požadavek a vyvolá odpověď. Měření se zastaví
při chybě, odpojení, uspání, změně cíle či ztrátě oprávnění; neobnovuje se po
restartu ani aktualizaci. Žádný retry ani dohánění vzorků.

Ruční servis a diagnostika sdílejí rozpočet 60 požadavků/h, z toho nejvýše
12 bez známé trasy; prodlevy 15/60 s. Každý vzdálený krok se účtuje zvlášť.
Čtyři hodiny jsou konzervativní předvolba podle komunitního podnětu, nikoli
záruka bezpečné zátěže. [Provozní limity a migrace](docs/TRAFFIC_POLICY.md).

## Sestavení a automatické testy

- macOS: otevřít `macOS/MeshCoreServicer.xcodeproj`; `swift test --package-path macOS`.
  Závislost Sparkle je připnutá na 2.10.1. Veřejný projekt má obecný bundle ID a
  lokální ad-hoc podpis; distribuční podpis je samostatný krok.
- Windows: .NET 10 SDK; `dotnet build Windows/MeshCoreServicer.slnx -c Release`.
- Linux: .NET 10 SDK; `dotnet run --project Linux/src/MeshCore.Linux`.
  Nativní běh vyžaduje Linux desktop. [Sestavení Linuxu](Linux/README.md).

```sh
dotnet run --project Windows/tests/MeshCore.Tests -c Release
dotnet run --project Shared/tests/MeshCore.Updates.Tests -c Release
dotnet run --project Linux/tests/MeshCore.Linux.Tests -c Release
python3 -m unittest discover -s Linux/packaging -p 'test_*.py'
dotnet run --project Linux/tests/MeshCore.Globalization.Tests -c Release
python3 -m unittest discover -s Windows/installer -p 'test_*.py'
python3 -m unittest discover -s macOS/scripts -p 'test_*.py'
```

`macOS/` obsahuje SwiftUI/CoreBluetooth, `Windows/` WPF/WinRT,
`Linux/` Avalonia/BlueZ a `Shared/` podepisované aktualizace/launcher.
Linux a Windows sdílejí platformně nezávislé protokolové jádro v
`Shared/MeshCore.Core`; WPF ani WinRT se do Linuxu nekompilují.
MIT licence; bez placených knihoven. [Changelog](CHANGELOG.md).

## Stav ověření

0.10.0: 172 Swift testů (včetně sériového I/O a obou režimů přes virtuální
terminál), 175 testů C# jádra/USB, 40 testů aktualizací a 51 Linux headless
kontrol. Xcode Release arm64/x86_64 a cross publikace Windows/Linux x64/ARM64
prošly. **Fyzické USB, BLE/LoRa a nativní Windows/Linux USB I/O ověřené nejsou.**
Následující doklad Ubuntu instalace se týká předchozího DEB 0.9.1:

Testy používají falešný transport, řízený čas a lokální HTTP náhradu.
Linux 0.9.1-1 prošel aktualizací přes APT a kontrolou závislostí v Ubuntu
26.04.1 LTS ARM64 VM. Nativní běhové testy a hlavní okno aplikace prošly
s ICU 78 při izolovaném skrytí starší ICU. Maticové testy závislostí obou
architektur nenahrazují čisté instalace všech distribucí ani běh x64.
BlueZ, párování, klíčenka a fyzické BLE/LoRa nejsou tímto ověřené.
Podpis a notarizace také nejsou důkazem BLE/LoRa kompatibility.
Hlášení Dell / T‑Deck Plus / Wadamesh beta zůstává k fyzickému ověření:
[audit Windows BLE](Windows/docs/WINDOWS_BLE.md).
