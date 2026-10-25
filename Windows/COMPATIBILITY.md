# Ověření Windows portu 0.8.0

Zdrojová verze 0.8.0: 111 automatických testů prošlo; Release cross kompilace
WPF na macOS bez chyb a varování. Fyzický BLE/LoRa test a běh WPF ve Windows
neproběhly. Pro 0.8.0 jsou připravené NSIS instalátory x64/ARM64;
kompilace a extrakční kontrola nenahrazují skutečnou instalaci ve Windows.

## Dřívější ověření verze 0.7.3

Stav k 24. 10. 2026. Vývoj a cross kompilace na macOS ARM64, .NET SDK 10.0.401.

| Oblast | Stav |
|---|---|
| .NET Core protokol, parsery a stavová logika | **92 automatických testů prošlo**; skutečný runner bez BLE |
| Nativní WPF / Windows API reference | Release kompilace bez chyb a varování |
| Sdílené WPF téma a šablony ovládacích prvků | XAML → BAML kompilace prošla; žádný webový obal |
| Samostatná publikace Windows x64 | Vytvořen PE32+ x86-64 EXE a oficiální .NET/WPF runtime |
| Samostatná publikace Windows ARM64 | Vytvořen PE32+ ARM64 EXE a oficiální .NET/WPF runtime |
| Audit veřejného balíčku | Bez osobních profilů, zpráv, hesel a vývojových adresářů |
| Spuštění a vizuální kontrola WPF ve Windows | **Neprovedeno** |
| Windows BLE adaptér, ovladač a vyjednání MTU | **Neprovedeno** |
| T114 / systémové párování / reconnect / uspání | **Neprovedeno** |
| Skutečná LoRa správa RAK4630/RAK4631 repeateru | **Neprovedeno** |
| Credential Manager a systémová oznámení ve Windows | **Neprovedeno** |

Úspěšná kompilace a testy s řízeným testovacím transportem nejsou důkaz fungujícího BLE ani LoRa. Aktualizované balíčky vyžadují ověření na skutečném zařízení. Není vydané tvrzení o kompatibilitě konkrétního adaptéru.

## První kontrola s vlastním T114

1. Rozbalte odpovídající ZIP na Windows, spusťte aplikaci a ověřte čitelnost rozhraní v obou vzhledech a při svém DPI. Žádná ukázková data se nemají zobrazit. Při prvním spuštění nejsou uložené profily ani zapnutá oznámení.
2. Zapněte Bluetooth. V telefonu odpojte companion, ve Windows vyhledejte a vyberte T114. Pokud firmware vyžaduje PIN, proveďte systémové párování se skutečným PIN zařízení. Ověřte, že připojení načetlo název, model, verzi a baterii bez LoRa vysílání.
3. Jestliže Windows nedokáže vyjednat celé BLE rámce, zkontrolujte ovladač adaptéru a firmware. Aplikace zobrazí chybu MTU; zkrácené notifikace ani dělení rámců nejsou akceptovaná náhrada.
4. Ručně načtěte kontakty, vyberte svůj repeater a přihlaste správce. Zkontrolujte, že uložení hesla je volitelné a vznikne odpovídající položka Správce přihlašovacích údajů Windows. Nepřihlašuje se přes BLE k repeateru.
5. Načtěte verzi/desku/hodiny a stav. Pro test změny použijte nejprve méně rizikové pole, například veřejný kontakt vlastníka s vlastními údaji. Zkontrolujte souhrn, potvrďte změnu a porovnejte nezávisle ve druhém klientu. Rádio nejprve pouze přečtěte; neměňte jej bez připraveného návratu a shodného nastavení companionu.
6. Ověřte zprávu v kanálu a DM do druhého vlastního companionu. DM má čekání a skutečný ACK; kanál pouze přijetí companionem. Přeposílání vyžaduje skutečně přijaté raw rádiové kopie, proto samotná zpráva nemusí mít nenulový čítač.
7. Výslovně zapněte oznámení, minimalizujte/zavřete okno a pošlete novou zprávu z druhého zařízení. Zkontrolujte skrytý obsah, zvuk, kliknutí, ztlumení a indikátor nepřečtených. Zprávy načtené při prvním připojení nemají upozorňovat.
8. Ověřte ruční odpojení, neočekávaný výpadek, obsazené BLE telefonem, vypnutý adaptér a uspání/probuzení. Po obnově nesmí zůstat automaticky přihlášený správce ani zapnutý monitoring, zápisy se nesmějí opakovat.
9. Teprve s fyzicky dostupným repeaterem zkuste restart po potvrzení. Samotné přijetí companionem není potvrzený restart. Znovu přihlaste správce, ověřte uptime/dostupnost a hodiny ručně synchronizujte.
10. V Diagnostice zaznamenejte jen skutečně provedené kontroly. Záznam obsahuje konkrétní identity lokálně a přesné verze, Windows a architekturu. Výchozí výsledek je Neprovedeno. Diagnostický export si před uložením prohlédněte; původní log nebo obsah zpráv se neodesílají.

Při timeoutu nejdříve obnovte BLE, přihlaste správce a načtěte skutečný stav. Zápis už mohl proběhnout. Import snímku nic nezapisuje, obnova vyžaduje zvláštní výběr a potvrzení.

Testy pokrývají zejména BLE hranice, všechny zkrácené kontaktní rámce, UTF-8 limity, signed RSSI/SNR, směry spojů, status, nezávislý AES/HMAC vektor, discovery tagy, předčasné odpovědi, typ/prefix CLI, sekvenční přístup, timeout a změnu generace, write failure po přijetí odpovědi, frontu a deduplikaci, soukromí oznámení, ACK, zachycené kopie, bezpečné batch zápisy, fallback af, oddělení profilů, poškozené soubory, snímky a kontrolu stavu před obnovou.

Vzhled 0.7.2 vychází z existujících macOS obrazovek a `UIComponents.swift`. Pro skutečné vykreslení sedmi prázdných WPF obrazovek v obou režimech je přiložen `verify-ui.ps1`. Tento Windows test zde **nebyl spuštěný**; nevydáváme macOS náhledy za screenshoty Windows.

Verze 0.7.2 opravuje oříznutí ikon, zvětšuje text a přidává pružné rozložení i uložené měřítko 100–150 %. Čtyři nové testy pokrývají migraci/uložení měřítka, odmítnutí neplatných hodnot a prostor pro čitelný obsah při zmenšení okna. Přiložený Windows WPF test vytváří 70 PNG a kontroluje místo pro ikony; zde nebyl spuštěný. Skutečné změny DPI, přechody mezi monitory a zachování rozepsaných polí při změně velikosti zbývá ověřit ve Windows.

Verze 0.7.3 zlepšuje dávkové načítání prvotního nastavení: limit CLI odpovědi 45–180 s, minimálně 1,2 s mezi vzdálenými operacemi a po přijaté odpovědi, jedinečné aplikační časové značky pro starší companiony, konkrétní průběh a místo selhání. Nové regresní testy ověřují časování, anti-replay pravidlo, zachování bezpečného zastavení po timeoutu, prázdného vlastníka, odmítnutí dutycycle s fallbackem na af, předběžnou validaci vlastníka a odpojení během čtení / čekání. Konkrétní hardwarový timeout ani jeho odstranění zde nebyly potvrzené.

## EXE instalátory 0.7.3

NSIS 3.13, české per-user instalátory x64/ARM64 se zahrnutým runtime. Osm testů generátoru prošlo, kompilace obou instalátorů proběhla s varováními jako chybami. Rozbalené soubory a jejich architektury se porovnaly s publikací pomocí SHA-256; licence je přiložená. Skutečná instalace, zástupci, registr Windows, aktualizace a odinstalace **nebyly v tomto macOS prostředí provedené**. Windows ověřovací skript a přesný postup jsou ve zdrojích v `installer/`. EXE nemají digitální podpis.

Zdrojová úprava konečného měření: ověřte na zařízení první prodlevu, automatické ukončení po limitu, Zastavit, přeskočení obsazeného termínu, společné omezení ručních a diagnostických dotazů a žádné obnovení po spánku / reconnectu. Viz [audit provozu](docs/TRAFFIC_POLICY.md). Fyzický test této úpravy nebyl proveden.

## Instalační balíčky 0.8.0

NSIS kompilace x64 i ARM64, kontrola extrahovaného obsahu podle SHA-256
a nativní architektury aplikace/runtime jsou součástí ověření lokálního vydání.
Přesné výsledky jsou v přiloženém validačním záznamu. EXE zůstávají nepodepsané;
Windows instalace, aktualizace, odinstalace a BLE/LoRa nebyly fyzicky vyzkoušené.
