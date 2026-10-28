# Změny MeshCore Servicer

## 0.10.0 — 28. 10. 2026

- macOS, Windows a Linux: USB sériové připojení companionu s USB firmwarem;
  stejné kontakty, zprávy a vzdálená správa přes LoRa jako u BLE. Port a režim
  vybírá uživatel; připojení samo nezapisuje konfiguraci ani nevysílá advert.
- Přímá místní správa USB repeateru bez companionu a vzdáleného přihlášení:
  informace firmwaru/desky, jednotlivé hodnoty konfigurace, zápis se zpětným
  ověřením, místní konzole s nápovědou, statistiky, čas a potvrzovaný restart.
- Binární companion rámce a textové CLI jsou samostatné protokoly. USB CLI
  páruje odpovědi dvěma znaky odraženými firmwarem; značky se v běhu aplikace
  neopakují ani po odpojení. Po timeoutu je nutné nové výslovné připojení.
- Omezené buffery, žádná fronta souběžných příkazů ani automatické opakování;
  spánek, odpojení, změna režimu a aktualizace ukončí USB relaci a měření.
- USB stav a redigované události v diagnostice bez portů, názvů zařízení,
  hesel, klíčů a obsahu komunikace. Přímá USB konzole nesbírá syrový log.
- Místní USB čtení nezatěžuje LoRa. Ručně vyžádané adverty/discovery sdílejí
  servisní rozpočet; plán vzdálené diagnostiky zůstává 4 h × 3, vypnutý,
  interval 3–24 h, maximálně 6 vzorků/24 h. Historie a profily zůstávají zachované.
- Verze 0.10.0, macOS sestavení 15. Distribuční DMG, Windows EXE a Linux DEB
  pro obě architektury; podepsané aktualizační feedy připravené lokálně.
- macOS sandbox obsahuje sériové oprávnění potřebné k otevření USB portů;
  distribuční bundle ID a vydavatelský tým zůstávají zachované.

## 0.9.1 — 27. 10. 2026

- Linux x64/ARM64: DEB přijímá systémovou ICU 78 z Ubuntu 26.04, zároveň
  zachovává ICU 70/72/74/76 pro dosavadní Ubuntu/Debian. České formátování,
  porovnávání a Unicode zůstávají zapnuté; starší ICU se nemusí ručně doplňovat.
- Doplněné závislosti samostatně distribuovaného .NET runtime: certifikáty CA,
  časová pásma, GSSAPI/Kerberos a Brotli; OpenSSL 3 včetně varianty t64.
- Regresní testy skutečným parserem dpkg pro pět distribučních kombinací a
  obě architektury, včetně odmítnutí chybějící ICU/TLS/certifikátů/časových dat.
  Samostatný test českých kultur umí ověřit skutečně načtenou hlavní verzi ICU.
- Aplikace i zdrojová metadata mají verzi 0.9.1 (macOS sestavení 14).
  Nové distribuční balíčky tohoto opravného vydání jsou pro Linux; dosavadní
  macOS a Windows instalátory 0.9.0 zůstávají samostatně označené.
- Diagnostika zůstává vypnutá, výchozí plán 4 h × 3 a limity 3–24 h,
  nejvýše 6 vzorků/24 h. Historie, profily a ostatní preference se nemění.

## 0.9.0 — 26. 10. 2026

- Linux: revize DEB 0.9.0-1 doplňuje adresáře před soubory v archivu a opravuje
  selhání nové instalace `dpkg-new: No such file or directory`. Regresní testy
  postupného rozbalení, skutečný dpkg unpack obou architektur a instalace/spuštění
  ARM64 v Ubuntu 26.04.1 LTS VM prošly; BLE/LoRa tím ověřené nejsou.
- macOS, Windows a Linux: číslo verze trvale ve stavové liště a v Nastavení;
  macOS zobrazuje také sestavení. Údaj vychází z metadat běžící aplikace.
- macOS: oprava pádu při spuštění v sestavení 11 (`DYLD Library missing`):
  doplněná cesta k přibalenému Sparkle a kontrola propojení obou architektur
  před podpisem a balením. Vadné sestavení je nutné ručně nahradit opraveným DMG.
- Linux x64 a ARM64: nativní Avalonia aplikace, BlueZ BLE, systémové párování,
  zprávy, správa repeaterů, konzole, historie a klíčenka Secret Service.
  Balíček `.deb` pro Ubuntu/Debian; bez webového obalu.
- Potvrzované aktualizace z vlastního HTTPS serveru. Windows/Linux stahují
  pouze změněné soubory podle podepsaného manifestu a SHA-256. Samostatný
  launcher přepíná ověřené verze, zachovává předchozí verzi a restartuje aplikaci.
- macOS: Sparkle 2.10.1, podepsané rozdílové aktualizace s možností úplného
  podepsaného archivu, pokud rozdíl pro původní verzi nelze použít.
- Kontrola při spuštění a přibližně denně, vypínatelná v Nastavení. Program se
  stáhne a nainstaluje až po souhlasu. První přechod z 0.8.x vyžaduje instalátor.
- Aktualizace zastaví měření, uvolní BLE a zachová osobní data. Správce ani
  měření se po restartu neobnovují. Firmware a konfiguraci zařízení nemění.
- Zahrnuty opravy Windows BLE a plán 4 h × 3 z 0.8.1/0.8.2 včetně migrace.
  Limity 3–24 h, 6 vzorků/24 h a servisní rozpočet se nemění. Čtyři hodiny
  nejsou zárukou bezpečné zátěže sítě.
- Společné číslo verze 0.9.0, macOS sestavení 13. Příprava je místní;
  nic se automaticky nepublikuje. Fyzické BLE/LoRa a aktualizace na cílových
  počítačích vyžadují samostatné ověření.

Podrobnosti: [aktualizace](docs/UPDATES.md), [Linux](Linux/README.md),
[limity provozu](docs/TRAFFIC_POLICY.md).


## 0.8.2 — 25. 10. 2026 (zdrojová příprava)

- macOS i Windows: výchozí diagnostika 3 vzorky po 4 hodinách; první dotaz
  čeká 4 hodiny, další jsou naplánované po 8 a 12 hodinách od spuštění.
- Interval 3–24 hodin pro každou trasu, nejvýše 6 vzorků a plán do 24 hodin.
  Kombinace se validují společně; například 4 h × 6 je platné, 5 h × 6 není.
- Výchozí i všechny existující profily migrují kratší intervaly pod 3 h na 4 h.
  Platné delší intervaly se zachovají v minutové přesnosti. Pokud by plán
  překročil 24 h, zachová se interval a sníží počet vzorků na povolené maximum.
  Migrace je idempotentní a zachovává historii i ostatní preference.
- UI ukazuje hodiny, počet požadavků a odpovědí, celkovou délku, průběh
  a datum/čas příštího vzorku. Před spuštěním vysvětluje aktivní provoz po LoRa.
- Čtyřhodinová předvolba reaguje na komunitní podnět; není pravidlem protokolu
  ani zárukou bezpečné zátěže sdílené sítě.
- Ruční správa, rozpočet 60 požadavků/h (z toho 12 flood/neznámá trasa), prodlevy
  15/60 s a účtování kroků zůstávají. Místní BLE čtení a historie nevytvářejí LoRa provoz.
- Měření zůstává výslovně spouštěné, bez retry či dohánění. Limit, chyba,
  odpojení, spánek, změna cíle nebo ztráta oprávnění ho ukončí; samo se neobnoví.
- Windows: po hlášení chyby `0x80070016` ve fázi Service se služby načítají
  jednou úplnou uncached GATT enumerací a přesné NUS UUID se vybere místně.
  Jde o cílenou úpravu čekající na fyzické ověření, ne důkaz opravy daného spoje.
  Opraveno také falešné zdvojení běžné chyby jako LateFaultObserved; export
  obsahuje revizi připojovací implementace.
- Verze obou platforem 0.8.2; macOS sestavení 10. Windows BLE opravy z 0.8.1
  zůstávají zahrnuté. Nové instalátory se nevytvářely; nic nebylo publikováno.

Podrobnosti a migrace: [Provoz LoRa a diagnostika](docs/TRAFFIC_POLICY.md).
Ověření: 158 Swift testů a 155 C# testů prošlo. Nové testy používají řízený
čas a falešný transport, bez fyzického BLE/LoRa. Univerzální Xcode Release
arm64/x86_64 a Windows WPF Release cross kompilace prošly. Pro 0.8.2 se
nevytvářel instalátor, podpis vydání ani notarizace.

## 0.8.1 — 25. 10. 2026

- Windows: neprázdné chybové dialogy s identifikátorem a fází připojení.
- Windows: strukturované fáze BLE a export bez identit, obsahu komunikace
  a syrových výjimek, dostupný i po neúspěšném pokusu.
- Windows: omezené čekání na WinRT, úklid pozdních výsledků, rozlišení důvodů
  ukončení, propagace chyb inicializace a ruční nový pokus po selhání obnovy.
- Limity LoRa diagnostiky a požadavek na úplné rámce a zabezpečení se nemění.

[Příčina hlášení Dell/T-Deck Plus není prokázaná; postup fyzického ověření](Windows/docs/WINDOWS_BLE.md).
macOS sjednocuje číslo verze na 0.8.1 (sestavení 9); jeho funkce se nemění.
Instalační balíčky 0.8.1 jsou připravené lokálně, bez veřejného publikování.
macOS DMG má Developer ID podpis a notarizaci Apple; Windows EXE zůstávají
nepodepsané. Prošlo 151 Swift testů, 144 C# testů a 25 testů balení, univerzální
Xcode archiv i samostatné Windows publikace x64/ARM64. Obsah EXE byl rozbalen
a porovnán s manifesty pomocí SHA-256; vložená ladicí data neobsahují místní cesty.
Fyzické BLE/LoRa a instalace/aktualizace/odinstalace ve Windows nebyly provedeny.

## 0.8.0 — 25. 10. 2026

- Neomezený monitoring nahrazuje ručně spuštěné diagnostické měření s intervalem
  a počtem vzorků. Výchozí plán: 3 vzorky po 30 minutách se známou trasou;
  pro flood nebo neznámou trasu nejméně 60 minut. Limit: 6 vzorků během 6 hodin.
- Každý vzorek aktivně vyšle požadavek přes LoRa a vyvolá odpověď.
  Rozhraní zobrazuje plán, průběh, zbývající vzorky a Zastavit.
- Ruční servis a diagnostika sdílejí omezení: nejvýše 60 požadavků za klouzavou
  hodinu, z toho nejvýše 12 přes flood nebo neznámou trasu. Prodleva je nejméně
  15 sekund při známé trase, jinak 60 sekund. Vícekrokové operace účtují každý
  vzdálený požadavek zvlášť; nejvýše 32 kroků nebo 20 minut na operaci.
- Žádné automatické opakování, dohánění zmeškaných vzorků ani obnovení měření
  po odpojení, spánku či restartu. Změna uzlu, ztráta oprávnění a chyba měření
  zastaví. Již odeslaný požadavek může dokončit čekání na odpověď.
- Historie a grafy zůstávají místní. Migrace zachová data a starý monitoring
  automaticky nezapne. Místní BLE čtení companionu se neúčtuje jako LoRa servis.
- macOS i Windows používají společné číslo verze 0.8.0; macOS sestavení 8.

Žádný interval není univerzálně bezpečný. Podrobnosti a zdůvodnění limitů:
[Provoz LoRa a diagnostika](docs/TRAFFIC_POLICY.md).

Ověření: 151 Swift testů, 111 C# testů a 25 testů balení bez skutečného zařízení;
Xcode Release pro arm64 a x86_64 a Windows WPF cross kompilace prošly.
macOS DMG se distribuuje s Developer ID podpisem a notarizací Apple;
Windows EXE jsou bez digitálního podpisu a mohou zobrazit SmartScreen.
Fyzické BLE/LoRa měření, čerstvá instalace na jiném Macu a instalace, aktualizace
či odinstalace ve Windows nebyly v tomto prostředí provedené.
