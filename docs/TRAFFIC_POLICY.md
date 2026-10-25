# Diagnostické měření a provoz LoRa

Implementace pro obě platformy, 25. 10. 2026. Formát MeshCore protokolu se
nemění; připnuté revize zůstávají v platformních souborech `PROTOCOL.md`.

## Audit operací

| Operace aplikace | Přenos | Započítání do servisního limitu |
|---|---|---|
| Inicializace, self-info, firmware a baterie companionu (1, 22, 20) | Lokální BLE | Ne |
| Kontakty, konkrétní kontakt a uložení kontaktu (4, 30, 9) | Lokální BLE | Ne |
| Kanály a vyzvednutí fronty zpráv (31, 10), včetně CLI pollingu fronty | Lokální BLE | Ne |
| Zobrazení grafů, historie, snímků, export/import snímku | Lokální soubory / paměť | Ne |
| Přihlášení repeateru (26), stav/ping (27) | BLE příkaz spustí LoRa požadavek a případnou odpověď | Ano, každý požadavek |
| Vzdálené CLI (2 s typem 1): čtení konfigurace, konzole, nastavení, čas, restart, advert | LoRa | Ano; zápis a jeho zpětné čtení jsou dva požadavky |
| Binární dotaz (50): telemetrie, ACL, každá stránka sousedů | LoRa | Ano, každá stránka zvlášť |
| Zero-hop discovery (55) | Aktivní rádiové vysílání; odpovědět může více uzlů | Ano, konzervativně jako neznámá trasa |
| Odeslání běžné DM nebo kanálové zprávy (2 s typem 0, 3) | LoRa | Mimo servisní rozpočet; stále používá stejnou sekvenční relaci |
| Příjem advertu, zprávy, ACK, statistik | Příjem / push BLE | Sám nespouští rádiový dotaz; aktualizace kontaktu a fronty je lokální |

Ani příkaz nazvaný „get“, „stav“ nebo „ping“ není pasivní příjem. Jedna
servisní jednotka znamená jeden požadavek aplikace, nikoliv jeden fyzický
rádiový paket: přidávají se odpovědi, přeposlání a případné chování firmwaru.
CLI `advert` a `advert.zerohop` se účtují konzervativně v kategorii flood /
neznámá trasa i při známé cestě, protože vyvolávají další rádiové vysílání.

## Konečné měření

- Výchozí volba: **3 vzorky po 30 minutách**, plánovaná délka 90 minut.
- Bez platné cesty v kontaktu companionu je minimum **60 minut**; výchozí
  plán pak znamená tři požadavky během 180 minut.
- Nejvýše **6 plánovaných vzorků** a **6 hodin plánované délky**. První
  požadavek se neposílá při spuštění, až po prvním intervalu.
- Plán je svázaný s companionem, repeaterem a přihlášením. Stav běhu je
  pouze v paměti. Restart aplikace, změna zařízení, odpojení, spánek,
  ztráta správce nebo chyba měření ukončí; obnovení BLE ho nespustí.
- Termíny jsou pevné od začátku plánu. Obsazený termín se spotřebuje jako
  přeskočený. Opoždění přes 30 sekund spotřebuje zmeškané termíny bez
  odesílání; žádné dohánění, automatický retry, login ani oprava cesty.
- Úspěšná odpověď se uloží do stávající historie. UI odděluje spotřebované
  termíny, skutečně uložené vzorky, přeskočené termíny a zbývající počet.
- Zastavení zruší i čekající servisní prodlevu, pokud požadavek ještě neodešel.
  Zastavení nevrací už odeslaný paket. Právě probíhající čekání doběhne do
  odpovědi nebo existujícího protokolového timeoutu; další vzorek nevznikne.
  Plánovaná délka není záruka přesného okamžiku dokončení poslední odpovědi:
  servisní prodleva může přidat až 60 s, čekání na LoRa odpověď nejvýše
  180 s a lokální potvrzení má vlastní krátký BLE timeout.

Tři vzorky umožní základní porovnání napětí a uptime bez trvalého sběru.
Třicetiminutový rozestup omezuje běžný plán na dva dotazy/h; neznámá trasa
ho snižuje na jeden/h. Šest vzorků a šest hodin jsou tvrdé limity plánu,
ne cílová frekvence provozu. **Žádný interval není univerzálně bezpečný**:
záleží na airtime, zatížení sítě, délce trasy, rádiu a odpovědích uzlu.

## Společný servisní rozpočet

Rozpočet je na hranici skutečného odeslání v `MeshSession`, sdílený ručními
akcemi, diagnostikou a všemi uzly. Platí:

| Omezení | Hodnota |
|---|---|
| Všechny servisní požadavky v klouzavém okně 60 minut | Nejvýše 60 |
| Z nich flood / neznámá trasa | Nejvýše 12 |
| Odstup od předchozího servisního požadavku | 15 s, pokud oba mají známou trasu; jinak 60 s |
| Jedna vícekroková aplikační operace | Nejvýše 32 požadavků a 20 minut před odesláním dalšího kroku |
| Fronta dalších operací | Žádná: obsazená relace požadavek odmítne |

Jde o aplikační stropy pro ruční servis, ne doporučený periodický provoz
ani výpočet regulatorního duty-cycle. Počet požadavků sám nezaručuje
nízký airtime. Opatrnější flood rozpočet zohledňuje zesílení provozu
přeposíláním; společný strop brání obcházení přepínáním repeaterů.
Odstupy tlumí i krátkou ruční dávku. Při normální konfiguraci zůstává
možný zápis a zpětné čtení; rozsáhlá čtení, stránkování nebo obnova se
mohou bezpečně zastavit s částečným výsledkem.

Prodleva je nejvýše jeden aktuální krok, s průběžnou informací v UI.
Při nedostatku hodinového rozpočtu aplikace vysvětlí omezení a uvede dobu,
po které lze akci ručně zopakovat. Nečeká ve frontě do další hodiny.
Neúspěšný nebo nejistý požadavek se nevrací do rozpočtu. CLI fronta se vyprázdní lokálním BLE čtením až po servisní prodlevě,
těsně před novým požadavkem; odpovědi dorazivší během prodlevy se k novému
příkazu nepřiřadí. Před dalším krokem
se znovu kontroluje relace, uzel, oprávnění a limit celé operace.
Po částečném zápisu zůstává nutné nejprve ověřit stav; nic se neopakuje.
Hodinová historie zůstává v instanci relace i při odpojení a přepnutí
companionu; restart aplikace ji neobnovuje. Aktivní měření se neukládá nikdy.
Limity jsou místní pro tento proces; nekoordinují telefon ani jiné klienty.

Nový stream kontaktů vyprázdní cache tras; samotný uložený soubor profilu
se za ověřenou trasu nepovažuje. Známá trasa vyžaduje validní `out_path_len` v kontaktu skutečně přijatém
z companionu, včetně validace délky hashů a velikosti cesty. Nula znamená
přímý dosah. 255, chybějící nebo neplatné údaje se považují za neznámou
trasu. Advert / změna cesty zneplatní příslušný cache záznam do lokálního
načtení kontaktu. Pokud SENT hlásí flood, aktuální požadavek se přeznačí
na flood a cache tras se konzervativně zneplatní. Dřívější známá cesta
nezaručuje budoucí směrování. Pokud plán po 30 minutách přijde o známou
trasu, ukončí se; delší plán musí uživatel výslovně spustit.

## Migrace a ověření

Historie zpráv, vzorky stavu a snímky nemění formát ani úložiště. Starý
`monitorMinutes` / `MonitorMinutes` zůstává zachovaný jako neaktivní
legacy údaj. Nová pole `diagnosticMinutes` / `DiagnosticMinutes` a
`diagnosticSamples` / `DiagnosticSamples` mají při chybění hodnoty 30 a 3.
Ostatní preference se zachovají. Ani uložený plán není povolením ke spuštění.

Testy používají falešný čas a transport. Ověřují konečný plán, prodlevu
prvního vzorku, limity, přeskočení, chyby, ztrátu oprávnění, souběh,
vícekrokový limit, zachování budgetu přes reset, místní BLE čtení,
migraci a zachování historie. Nejde o fyzické BLE/LoRa měření airtime.

Podklad: [MeshCore HA traffic policy](https://github.com/meshcore-dev/meshcore-ha/blob/main/docs/docs/traffic-policy.md),
přečteno 25. 10. 2026. Převzatý je princip společného rozpočtu a rozlišení
trasy; číselné stropy jsou posouzené pro ruční desktopový servis. Automatické
retry, route healing, trvalý polling ani obnovování rozběhnutého plánu se
z tohoto podkladu nepřebírají.

## Provedené ověření této úpravy (25. 10. 2026)

- Swift: 151 automatických testů (79 protokol / politika, 72 aplikační logika).
- C#: 111 automatických testů jádra, plánování, souběhu a migrace.
- Python: 25 testů zdrojového a instalačního balení; instalátory se nevytvářely.
- Xcode Release sestavení arm64 + x86_64 do dočasné složky, bez podpisu vydání.
- Windows/WPF cross kompilace na macOS: 0 chyb, 0 varování.

Testovací transporty a virtuální čas nevysílají přes BLE ani LoRa.
Skutečný T114, repeater, airtime, uspání/probuzení a interaktivní vykreslení
Windows této úpravy nebyly fyzicky ověřené. Stávající instalační balíčky a
ZIPy zůstávají dřívějšími sestaveními. Nic nebylo publikované ani commitnuté.
