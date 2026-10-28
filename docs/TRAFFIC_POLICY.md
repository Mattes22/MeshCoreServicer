# Diagnostické měření a provoz LoRa

Zdrojová verze 0.8.2 pro obě platformy, 25. 10. 2026. Formát MeshCore protokolu se
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

- Výchozí volba: **3 vzorky po 4 hodinách**, plánovaná délka **12 hodin**.
  První požadavek se odešle až 4 hodiny po ručním spuštění, další po 8 a 12
  hodinách. Měření je standardně vypnuté.
- Pro známou trasu i flood / neznámou trasu platí interval **3–24 hodin**,
  nejvýše **6 plánovaných vzorků** a **24 hodin plánované délky**.
  Každá kombinace musí splnit `interval × počet vzorků ≤ 24 hodin`.
  Neplatný plán se nespustí. Úložiště zachovává minutovou přesnost;
  UI interval i celkovou délku zobrazuje v hodinách a případném zbytku minut.
- UI před spuštěním ukazuje počet požadavků i očekávaných odpovědí a dobu do
  prvního vzorku. Za běhu také průběh, zbývající vzorky, datum a místní čas
  příštího termínu a tlačítko Zastavit. Každý vzorek je aktivní LoRa požadavek
  s odpovědí přes sdílenou síť; nejde o pasivní odposlech.
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
Výchozí čtyřhodinový rozestup reaguje na komunitní podnět prodloužit pravidelné
čtení na 3–4 hodiny: uživatelé často ponechávají předvolby. Jde o rozhodnutí
aplikace, **nikoliv pravidlo protokolu**. Výchozí plán tak rozloží tři požadavky
a odpovědi do dvanácti hodin místo původních 90/180 minut. Šest vzorků a 24 hodin
jsou stropy plánu, ne cílová frekvence provozu. **Žádný interval, ani 4 hodiny,
není univerzálně bezpečný**: záleží na airtime, zatížení sítě, délce trasy,
rádiu a odpovědích uzlu. Flood může násobit přeposílání i při stejném plánu.

| Počet vzorků | Nejdelší povolený interval | Nejdelší plán |
|---|---|---|
| 1 | 24 h | 24 h |
| 2 | 12 h | 24 h |
| 3 | 8 h | 24 h |
| 4 | 6 h | 24 h |
| 5 | 4 h 48 min | 24 h |
| 6 | 4 h | 24 h |

Minimum zůstává 3 h pro každý řádek. Například 4 h × 6 je platné,
5 h × 6 není. Tento rozsah se týká pouze plánovaných diagnostických vzorků;
ruční Načíst stav jednou, přihlášení nebo změna konfigurace nečekají 3–4 hodiny.

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
nezaručuje budoucí směrování. Ztráta známé trasy nemění interval plánu, protože hodinové minimum je společné.
Každý skutečně odeslaný krok se však účtuje podle aktuální trasy: při floodu
platí přísnější ruční rozpočet a prodleva. Změna cílového zařízení či relace
měření nadále zastaví.

## Migrace a ověření

Historie zpráv, vzorky stavu a snímky nemění formát ani úložiště. Starý
`monitorMinutes` / `MonitorMinutes` zůstává zachovaný jako neaktivní
legacy údaj. Nová pole `diagnosticMinutes` / `DiagnosticMinutes` a
`diagnosticSamples` / `DiagnosticSamples` mají při chybění hodnoty **240 minut a 3**.
Při dekódování se intervaly kratší než 180 minut převedou na 240 minut ve
výchozích volbách i ve všech existujících, také neaktivních profilech.
Platné intervaly 180–1440 minut včetně minutové přesnosti se zachovají.
Pokud by zachovaný interval s počtem vzorků překročil 24 hodin, sníží se pouze
počet vzorků na `min(původní počet, floor(1440 / interval))`; interval má přednost.
Ostatní neplatná data nadále podléhají ochraně poškozeného souboru před přepsáním.

Migrace je hodnotová a idempotentní. Normalizované volby se zapíšou při běžném
uložení preferencí; jejich opětovné načtení nepřinese další změnu. Historie,
identity profilů, aliasy, zkratky a ostatní preference se nemění. Staré hodnoty
`monitoring` / `Monitoring` se nečtou jako souhlas se spuštěním; aktivní plán
nikdy není součástí serializovaných voleb. Ani uložený plán není povolením ke spuštění.

Testy používají falešný čas a transport. Ověřují konečný plán, prodlevu
prvního vzorku, limity, přeskočení, chyby, ztrátu oprávnění, souběh,
vícekrokový limit, zachování budgetu přes reset, místní BLE čtení,
migraci a zachování historie. Nejde o fyzické BLE/LoRa měření airtime.

Podklad: [MeshCore HA traffic policy](https://github.com/meshcore-dev/meshcore-ha/blob/main/docs/docs/traffic-policy.md),
přečteno 25. 10. 2026. Převzatý je princip společného rozpočtu a rozlišení
trasy; číselné stropy jsou posouzené pro ruční desktopový servis. Automatické
retry, route healing, trvalý polling ani obnovování rozběhnutého plánu se
z tohoto podkladu nepřebírají.

## Ověření 0.8.2

Automatické testy s řízeným časem ověřují 4 h × 3, přesnou první prodlevu,
termíny 4/8/12 hodin, ukončení, plán 24 h × 1, všechny minutové kombinace
intervalů 180–1440 a počtů 1–6, neplatné hranice a migraci profilů z 0.8.0/0.8.1.
Zůstávají testy chyb, souběhu, servisního rozpočtu, místního BLE čtení,
zastavení a nepřítomnosti automatického obnovení. Testy nečekají skutečné
hodiny a nevysílají přes BLE ani LoRa. Prošlo 158 Swift testů a 155 C# testů; univerzální Xcode Release arm64/x86_64
a Windows WPF Release cross kompilace prošly. Podrobnosti a meze jsou uvedené
v platformních souborech `COMPATIBILITY.md`.

Skutečný T114, T-Deck, repeater, airtime, uspání/probuzení a interaktivní běh
Windows této úpravy nebyly fyzicky ověřené. Instalační balíčky 0.8.1 a starší
zůstávají původními sestaveními; pro 0.8.2 se instalační vydání nevytváří.

## Linux a aktualizace 0.9.0

Linux používá stejné diagnostické plány a servisní rozpočet jako Windows.
Výchozí plán zůstává 4 h × 3, nejvýše 6 vzorků/24 h. Aktualizace měření
zastaví; po restartu ho neobnovuje. Kontrola verzí používá internetové HTTPS
spojení, nikoli LoRa. Prohlížení historie zůstává místní.

## USB od 0.10.0

USB companion používá pro vzdálené LoRa kroky stejné limity jako BLE.
Přímá místní správa USB repeateru nevyvolává pravidelné dotazy; čtení konfigurace
a statistik nevyužívá LoRa. Ručně potvrzený advert/discovery se účtuje
do společného servisního rozpočtu. Přepnutí transportu a spánek ruší měření.
