# MeshCore Servicer pro macOS


Nativní aplikace SwiftUI + CoreBluetooth, macOS 14+. Žádný web, WebView, placená knihovna ani běhová závislost na JavaScriptu. Zdrojový projekt je v `MeshCoreServicer.xcodeproj`; protokolová knihovna a její testy jsou také dostupné přes `Package.swift`.

## Co je nové v 0.7

- **Profily companionů:** místní názvy, bezpečné přepnutí s kontrolou veřejné identity, samostatné volby konzole, obnovení BLE a intervalu monitoringu. Oznámení a jejich soukromí zůstávají společné. Přepnutí vymaže paměťovou konzoli a rozepsaný příkaz jiné identity; zprávy a historie správy se načtou pro správný účet. Přihlášení správce a monitoring se neobnovují.
- **Oblíbené příkazy a pojmenované šablony:** v konzoli ikona hvězdy. Ukládá se pouze název a typ příkazu z katalogu, odděleně podle companionu. Vlastní argument se zadává při použití; vložení nikdy neodesílá. Neznámé příkazy a hesla nejsou součástí uložených šablon.
- **Evidence skutečné podpory:** nápověda rozlišuje samotný katalog, obdrženou odpověď, odmítnutý argument a výslovně nepodporovaný příkaz. Výsledek platí jen pro konkrétní companion, repeater a plnou načtenou verzi firmwaru. S neznámou verzí jen pro jednu BLE relaci. Timeout ani přijetí bez vzdálené odpovědi nejsou důkazem podpory; žádné testovací příkazy se neposílají automaticky.
- **Kontroly neověřených změn:** Historie a snímky → Po restartu nabídne odpovídající čtecí kontrolu. U známého nastavení porovná skutečný stav s uloženým záměrem, bez opakování zápisu. Odlišná hodnota i starší záznam bez záměru zůstávají neověřené. Čtení uloženého rádia nepotvrzuje jeho aktivování po restartu a dostupnost nepotvrzuje restart. Po timeoutu je nejprve nutné obnovit BLE relaci a přihlásit správce.
- **Diagnostický report s náhledem:** uloží se přesně zobrazený snímek. Verze, stav spojení a konečný seznam kategorií událostí; bez původního logu, názvů, klíčů, BLE adres, rádia, polohy a obsahu CLI nebo zpráv. Žádná data se automaticky neposílají.
- **Kompatibilita:** oddělený ruční checklist konkrétní kombinace zařízení a verzí. Výchozí stav všech testů je Neprovedeno; záznam je výslovně uživatelský. [Přehled ověření](../COMPATIBILITY.md) rozlišuje automatické testy od dosud neprovedených fyzických zkoušek.

Profily, šablony, evidence a ruční výsledky jsou lokální JSON v preferencích aplikace, nikoliv ve veřejném balíčku. Knihovna má omezení 32 profilů, 128 zkratek, 1 024 záznamů podpory a 256 výsledků testů. Poškozená knihovna se automaticky nepřepíše. Odstranění neaktivního profilu nemaže zprávy, snímky, firmware ani Keychain. Nový profil přebírá výchozí volby nastavené mimo aktivní profil; pozdější úpravy se ukládají samostatně do aktivního profilu.

## Co je nové v 0.6

- Univerzální výchozí stav: žádné předvolené zařízení, majitel, souřadnice, kanály, hesla nebo parametry konkrétní sítě. Název a hardware pocházejí z připojeného companionu. Jde o nezávislý nástroj, nikoliv oficiální aplikaci MeshCore.
- Prvotní nastavení zachovává načtené hodnoty. Český komunitní profil je samostatná volitelná předvolba; bez výběru profilu a potvrzení se nepoužije. Hodiny se synchronizují jen na výslovný pokyn.
- Konzole má místní katalog vzdálených příkazů, české popisy, syntaxi argumentů, označení zápisů a našeptávání z bezpečné historie. Nastavení umožňuje jednotlivé funkce vypnout i vypnout odeslání Enterem. Podrobnosti níže.
- Distribuce obsahuje pouze aplikaci a zdrojové soubory, bez historie, nastavení, hesel a dat z vývojového počítače. Renderované náhledy obsahují zřetelně označená syntetická data.

**Přechod mezi sestavami:** veřejný zdrojový projekt používá obecný identifikátor `org.meshcoreservicer.app`. Distribuční sestava může používat vlastní stabilní identifikátor vydavatele. Jiný identifikátor může znamenat jiný sandbox; historie, preference ani hesla se nemažou a automaticky se mezi identifikátory nepřenášejí. V takovém případě companion zvolte znovu a heslo správce zadejte vlastní. Exportované snímky lze ručně importovat pro stejnou identitu uzlu. macOS může znovu požádat o oprávnění.

## Konzole: nápověda a doplňování

Pište příkaz (`get ra`) nebo český název (`rádio`). Návrhy rozlišují katalog a místní historii. **Tab nebo kliknutí pouze vloží návrh**, šipky mění výběr; Escape zavře návrhy a šipky pak procházejí historii s obnovením rozepsaného vstupu. U voleb `repeat`, `path.hash.mode` a `loop.detect` nabídka doplní i ověřené hodnoty (po zapnutí nabídky změn). Ostatní vlastní argumenty mohou pocházet pouze z vaší místní historie. Argumenty v ostrých závorkách jsou jen součást nápovědy, do vstupu se nevkládají. Doplňte vlastní hodnotu a příkaz odešlete tlačítkem, případně Enterem. Neúplné známé příkazy a neplatné hodnoty jsou před odesláním odmítnuty. Ruční příkazy mimo katalog zůstávají dostupné.

V **Nastavení → Konzole** nastavíte našeptávání, nápovědu, návrhy z historie, nabídku příkazů měnících stav a odesílání Enterem. Zápisy a vysílání se ve výchozím stavu nenabízejí. Katalog otevřete ikonou knihy. Našeptávání nevolá síťovou službu ani neposílá příkazy zařízení. Historie je jen v paměti a citlivé příkazy jsou vyřazené. Přihlášení i skutečné odpovědi vždy používají stejnou sekvenční relaci jako správa repeateru.

Katalog je ověřen proti firmwaru `81dbae592ffad40b4212bc0b37e82b38da08f4bc` (v1.18). Nejde o zjištění schopností konkrétního zařízení. Nepodporované operace vracejí skutečnou chybu uzlu; příkazy dostupné pouze po sériové lince a správa privátních klíčů nejsou v nabídce. Zdroj: [oficiální CLI dokumentace](https://docs.meshcore.io/cli_commands/) a připnutý zdrojový kód popsaný v [PROTOCOL.md](../PROTOCOL.md).

## Co je nové v 0.5

- **Systémová oznámení zpráv:** banner, volitelný zvuk, odznak v Docku, otevření konverzace kliknutím, skrytý obsah ve výchozím stavu a ztišení kanálů.
- **Obnovení BLE:** po nečekaném výpadku a po probuzení, s prodlevami 1–30 s; ruční odpojení pokusy ukončí. Připojení neopakuje neověřené vysílání nebo přihlášení.
- **Snímky konfigurace:** uložení načtených polí s časem čtení, JSON import/export, porovnání se skutečným stavem a selektivní obnova s potvrzením a zpětným ověřením. Bez hesel a privátních klíčů.
- **Zdraví repeateru:** historie napětí, uptime a provozu; volitelný monitoring po LoRa s intervalem 5–1440 minut, výchozí 15 minut. Monitoring je vypnutý, první požadavek čeká celý interval.
- **Detail kanálových kopií:** posledních 64 skutečných rádiových příjmů každé zprávy s časem, hopy, RSSI a SNR dané kopie. Souhrnný čítač zůstává zachovaný i po omezení detailu.
- **Kontrola po restartu:** samostatné ověření dostupnosti a hodin, detekce možného restartu z poklesu uptime a trvalý seznam změn čekajících na ověření.

Označené náhledy těchto obrazovek lze vygenerovat pomocí `scripts/render-previews.sh`.

## Co je nové v 0.4

Správa repeateru má nové záložky **Nástroje** a **Prvotní nastavení**. Rozšíření vychází z dodaných snímků oficiální aplikace; protokol a příkazy jsou ověřené proti stejnému připnutému firmwaru v [PROTOCOL.md](../PROTOCOL.md).

- Průvodce s volitelnou předvolbou české komunity: flood **25 hodin**, zero-hop **0**, duty cycle **10 %** nebo ekvivalentní **af 9**, **path.hash.mode 1** (dvoubajtové hashe), vlastní veřejný kontakt a synchronizace hodin.
- Průvodce čte současné hodnoty a podporu jednotlivých příkazů, nabízí výběr kroků a před zápisem ukazuje souhrn. Shodné hodnoty nepřepisuje, nepodporované kroky nepouští a při první chybě se zastaví. Žádný krok se automaticky nespouští připojením ani otevřením stránky.
- Samostatné nástroje pro verzi a hardware, hodiny UTC, skutečnou telemetrii, stránkovaný seznam sousedů s plnými klíči a SNR posledního paketu daného souseda na vzdáleném repeateru.
- Veřejný kontakt vlastníka, přístupová oprávnění ACL, změna hesla správce/hosta, síťové parametry, základní operace regionů s trvalým uložením, flood/zero-hop advert a restart s potvrzením.

Ukázkové hodnoty pro vizuální kontrolu jsou pouze v samostatném rendereru `scripts/render-previews.swift`, nikoliv v běžné aplikaci.

## Co je nové v 0.3

- Nativní **Zprávy**: soukromé konverzace s companion kontakty a skupinové kanály načtené z připojeného companionu, hledání, nepřečtené zprávy a rozepsané vstupy.
- Příjem z lokální fronty companionu, odesílání na výslovný pokyn a historie oddělená podle veřejného klíče vlastního companionu.
- Soukromé zprávy rozlišují přijetí požadavku companionem, čekání na ACK, potvrzení protějšku a neznámý výsledek. Kanály nemají potvrzení doručení.
- U kanálových zpráv **Zachyceno N přeposlání**: počet odpovídajících přeposlaných rádiových kopií zachycených companionem. Samostatně je počet přeposlání v cestě konkrétního přijatého paketu.

Náhledy zpráv ve světlém i tmavém režimu vytváří samostatný renderer s výslovně označenými testovacími hodnotami.

## Rozhraní od verze 0.2

Rozhraní bylo přepracované podle pracovních postupů MeshCore Open a desktopového Mesh-Client. Konkrétní zdroje a rozhodnutí jsou v [UI_RESEARCH.md](../UI_RESEARCH.md).

- Postranní navigace s klávesami ⌘1–⌘6, trvalý stav companionu a indikace rozepsaných změn.
- Kontakty s hledáním podle názvu, klíče i typu, filtry, zobrazením uložené cesty včetně vícebajtových hashů a samostatným detailem uzlu.
- Centrum repeateru s oddíly **Přehled / Nastavení / Rádio**, přehledovými metrikami a srozumitelnou dobou běhu.
- Samostatné načítání hodnot, validace v místě editace, ochrana rozepsaných změn při obnovení i změně uzlu a kontrola hromadného uložení před odesláním.
- Uložení postupuje přes odeslání a zpětné čtení. Odlišná odpověď ponechá rozepsanou hodnotu, zobrazí skutečnou hodnotu a zastaví zbývající změny.
- Rádio má samostatná pole pro MHz, BW, SF a CR; upozornění na restart zůstává viditelné.
- Konzole má rychlé vložení čtecích příkazů, historii ↑/↓ s obnovením rozepsaného vstupu, hledání, filtr podle repeateru a stav každé odpovědi.
- Diagnostika má hledání, filtrování chyb a neblokující oznámení v okně.

Náhledy rádia a konzole lze vytvořit samostatným rendererem; testovací scénář se do aplikace nekompiluje.

## Spuštění

1. Otevřete `MeshCoreServicer.xcodeproj` v Xcode (ověřeno v Xcode 27.0, Swift 6.4, jazykový režim Swift 5).
2. Zvolte schéma **MeshCoreServicer**, cíl **My Mac**, spusťte ⌘R. Projekt používá lokální ad-hoc podpis, bez placeného vývojářského účtu. Pro vlastní dlouhodobé podepisování lze nastavit osobní vývojářský tým.
3. Povolte aplikaci Bluetooth v systémovém dialogu. Případné BLE párování a PIN řeší macOS; heslo správce repeateru je samostatné přihlašování přes LoRa.

Sestavení z terminálu:

```sh
xcodebuild -project MeshCoreServicer.xcodeproj -scheme MeshCoreServicer \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
open 'build/Build/Products/Debug/MeshCore Servicer.app'
```

Na Intel Macu použijte `arch=x86_64`. Pro instalaci použijte podepsané a notarizované univerzální DMG z Releases tohoto repozitáře: otevřete ho a přetáhněte aplikaci do Aplikací. Starší `dist/MeshCore Servicer.app` a `dist/MeshCoreServicer-macOS-universal.zip` jsou ad-hoc sestavy bez notarizace. Intel část byla sestavena, její běh na fyzickém Intel Macu nebyl ověřen. Pro BLE spouštějte `.app` nebo Xcode schéma, nikoliv samotný spustitelný soubor z `swift run` (nemá vlastní aplikační Info.plist a podepsaná oprávnění).

## Ověření s vlastním companionem a repeaterem

1. V telefonu odpojte svůj companion, aplikaci používající jeho BLE zavřete. Companion zapněte a ponechte poblíž Macu.
2. V **Připojení** spusťte hledání a vyberte svůj companion (BLE název může obsahovat firmware prefix). Dokončete případné systémové párování pomocí PINu svého companionu. Aplikace PIN neodhaduje a neukládá.
3. Ověřte skutečně načtený název, model, firmware, napětí baterie a rádio companionu. Porovnejte rádio s parametry své sítě. Aplikace žádnou frekvenci automaticky nenastavuje.
4. V **Kontakty** zvolte **Načíst kontakty**. Vyberte svůj repeater podle celého veřejného klíče, nejen názvu. Stav „uloženo“ není potvrzení dostupnosti.
5. Volitelně spusťte **Objevit blízké repeatery (LoRa)**. To vyšle zero-hop discovery přes companion; odpovědi se přijímají 30 sekund a jsou párované náhodným tagem. Neuložený uzel lze samostatným tlačítkem uložit. Samotné discovery kontakty nepřepisuje.
6. Ve **Správě repeateru** zadejte heslo správce a přihlaste se. Oprávnění musí potvrdit repeater. Zapnutá volba ukládá heslo do macOS Keychain až po úspěšném přihlášení. Znovunačtení a odstranění hesla mají vlastní tlačítka.
7. Použijte **Ping / načíst provozní stav**. Jde o skutečný protokolový požadavek na stav; může vyžadovat přihlášení/ACL. Čas odpovědi potvrzuje dostupnost v daném okamžiku, nikoliv trvalý online stav.
8. Na záložce **Nastavení** použijte **Načíst nastavení**; rádio načítejte samostatně na záložce **Rádio**. Konzoli nejprve ověřte čtecími příkazy `ver`, `board`, `get name`, `get radio`, případně `neighbors`. Žádný vzdálený příkaz se neposílá automaticky při připojení.
9. Změny provádějte jednotlivě. Uložení čeká na CLI odpověď repeateru a potom znovu čte hodnotu `get`. Zobrazuje se skutečná načtená hodnota včetně případného zaokrouhlení firmwarem. Název má konzervativní limit 23 UTF-8 bajtů kvůli advertu s polohou. Lokální advert: 0 nebo sudé 60–240 minut; flood advert: 0 nebo 3–168 hodin. 0 interval vypíná.
10. Změnu rádia provádějte až nakonec. V tomto firmwaru `set radio` ukládá parametry, které se použijí po restartu. Aplikace před uložením varuje; rádio companionu nemění. Restart vyžaduje potvrzení. Firmware na `reboot` neodpovídá, proto aplikace nikdy nehlásí potvrzený restart pouze na základě přijetí požadavku companionem. Po restartu ověřte dostupnost ručně.
11. V **Diagnostice** otevřete report s náhledem a exportujte časované kategorie událostí. Vyzkoušejte také ruční odpojení, opětovné připojení, vypnutý Bluetooth a chybné heslo. Po obnovení spojení je přihlášení správce zrušené.

## Oznámení, obnovení BLE a historie

**Oznámení:** otevřete Nastavení aplikace přes ozubené kolečko nebo ⌘,. Zapněte systémová oznámení a potvrďte dialog macOS. Jsou vypnutá, dokud je výslovně nezapnete. Zvuk a zobrazení jména/textu mají samostatné volby. Obsah je ve výchozím stavu skrytý; nevyzvednuté historické zprávy během první synchronizace nevyvolávají bannery. Na právě čtenou konverzaci se oznámení nevytváří. Minimalizovaná, zakrytá nebo neaktivní aplikace nové zprávy sama neoznačuje přečtené. Ztišení v záhlaví kanálu vypne jeho další bannery a zvuk, nikoliv příjem a nepřečtené počty. Kliknutí na oznámení otevře hlavní okno a odpovídající konverzaci; oznámení jiné identity companionu nepřepne zařízení ani nenačte cizí účet automaticky.

Zavření okna ponechá aplikaci běžet; znovu ji otevřete z Docku nebo oznámení. Ukončení aplikace přes ⌘Q ukončí i příjem. macOS může oznámení potlačit nastavením Soustředění, systémovým zákazem nebo pravidly náhledů. Aplikace nenahrazuje tato systémová pravidla.

**Obnovení BLE:** ve výchozím stavu zapnuté, lze vypnout v Nastavení. Připojuje pouze companion výslovně zvolený během daného běhu aplikace. Po novém spuštění aplikace jej zvolte ručně. Pokusy mají prodlevu 1, 2, 4, 8, 16 a potom nejvýše 30 sekund. Vypnutý Bluetooth a spánek čekání pozastaví. Tlačítko Odpojit nebo Zastavit obnovování ukončí záměr připojení. Zrušený bond a chyby zabezpečených charakteristik vyžadují ruční opravu párování. Po návratu BLE se znovu čtou lokální informace a fronta; neobnovuje se admin přihlášení, zprávy ani konfigurace se automaticky znovu neposílají.

**Historie a snímky** je samostatná záložka Správy repeateru:

- **Zdraví:** ruční načtení stavu uloží vzorek. Pravidelné načítání je aktivní LoRa operace; zapněte je pouze s vědomím uvedeného intervalu. První požadavek se neposílá okamžitě. Při jiné operaci se interval přeskočí; při chybě, odhlášení, změně uzlu, odpojení nebo spánku Macu se monitoring zastaví a automaticky neobnoví. Čítače jsou kumulativní od restartu; RSSI/SNR patří k poslednímu paketu na vzdáleném repeateru, jehož odesílatel není známý.
- **Snímky konfigurace:** nejprve načtěte potřebná pole. Uložení snímku samo nečte po LoRa. Do snímku se dostanou jen podporovaná načtená pole s časy čtení; nejisté zápisy se vynechají. Pokud je načtené dutycycle i af, uchová se pouze dutycycle. JSON může obsahovat veřejné owner info. Import nic nezapisuje do repeateru a odmítne jinou identitu, nesprávný cíl, neznámá pole, tajné klíče či nepovolené hodnoty. Pro obnovu vyberte pole (rádio není předem zaškrtnuté), načtěte aktuální stav, porovnejte rozdíly a potvrďte. Před prvním zápisem se znovu přečtou všechna měněná pole; změna od porovnání celý postup zastaví. Každý zápis má zpětné čtení. Obnova nerestartuje zařízení a není atomickou transakcí; při pozdější chybě už provedené změny zůstávají viditelné.
- **Po restartu:** odeslaný požadavek neznamená potvrzený restart. Pokles načteného uptime označuje možný restart. Následná odpověď na stav potvrzuje dostupnost v daném čase; načtení hodin odpovídajících času Macu je samostatný krok. Seznam neověřených změn přežije odpojení a další spuštění. Konfigurace se vyřadí po úspěšném zpětném ověření; obecné CLI, regiony, odebrání ACL a některé jiné operace vyžadují vlastní kontrolu. Tlačítko Označit ručně ověřeno pouze upraví seznam a neposílá příkaz.

Historie je lokální JSON v aplikačním sandboxu `Library/Application Support/MeshCoreServicer/Operations`, oddělená podle celých veřejných klíčů companionu a repeateru. Uchovává 2 000 vzorků, 30 snímků a 50 posledních neověřených položek na uzel, nejvýše 32 uzlů na identitu. Překročení počtu uzlů se hlásí bez odstranění starých uzlů. Poškozené soubory se automaticky nepřepisují. Historie není dodatečně šifrovaná aplikací. Dostupná historie identity se načte po identifikaci připojeného companionu; po odpojení je dál čitelná přes výběr uloženého uzlu. Hesla zůstávají v Klíčence.

Konkrétní postup skutečného ověření je v [HARDWARE_CHECKLIST.md](../HARDWARE_CHECKLIST.md). Tento seznam je návod pro reálný test, nikoliv protokol již provedeného měření.

## Prvotní nastavení repeateru

1. Připojte companion, načtěte kontakty, vyberte správný repeater a v **Přehledu** se přihlaste jako správce.
2. Otevřete **Správa repeateru → Prvotní nastavení → Načíst stav repeateru**. Jde o výslovné čtení přes LoRa. Průvodce načte verzi, intervaly, duty cycle, hash mode a owner info. Jen když firmware výslovně odmítne `get dutycycle`, zkusí `get af`; timeout nepovažuje za nepodporovaný příkaz.
3. Výchozí profil zachovává současné hodnoty. Chcete-li předvolbu české komunity, nejprve ji výslovně vyberte. Zkontrolujte navržené hodnoty. Doplňte vlastní kontakt a zaškrtněte jeho krok, pokud jej chcete změnit. `owner.info` je veřejný údaj. Prázdný vstup se automaticky nevyplní cizím kontaktem ani neodešle.
4. Vyberte požadované kroky, případně zapněte synchronizaci hodin. Použijte **Zkontrolovat a použít…**, přečtěte souhrn a potvrďte. Každý `set` musí mít odpověď a odpovídající zpětné `get`. Po částečném selhání zůstává vidět dokončená část; žádné změny se automaticky nevracejí nebo neopakují.
5. Zkontrolujte výsledek a případné chyby. Průvodce nemění rádio, výkon, identitu, přeposílání ani hesla. Volitelný profil české komunity zachycuje doporučení z 24. 10. 2026; před použitím ověřte jeho aktuálnost pro svou síť.
6. Po restartu znovu ověřte čas přes **Nástroje → Diagnostika → Načíst verzi a čas** a případně **Synchronizovat hodiny…**. Posílá se explicitní `time <Unix čas Macu>`, nikoliv závislost na správně nastavených hodinách companionu. Firmware odmítne posun zpět. Aplikace poté čte `clock` a kontroluje shodu UTC s přesností minut, kterou odpověď dovoluje. Neprovádí automatický reset hodin nebo restart.

**Nástroje → Síť a regiony:** každou síťovou hodnotu nejprve načtěte. `dutycycle` a `af` mění stejné pole; hromadný zápis obou aplikace odmítá a po zápisu jedné zneplatní staré čtení druhé. Regiony nejprve načtěte. Formulář podporuje přidání/úpravu, povolení/zákaz floodu, domácí region, výchozí scope a odstranění. Před potvrzenou změnou existujícího regionu ověří úplný název proti prefixovému vyhledávání firmware. Následuje `region save` a načtení přehledu. Souhrn může být firmwarem zkrácen; aplikace z něj nevymýšlí úplný seznam. Hromadné definice, import regionů a změna identity nejsou v této verzi implementované.

**Nástroje → Přístup:** ACL se načítá binárně, protože `get acl` je v tomto firmwaru jen pro lokální sériovou konzoli. Firmware vrací šestibajtové prefixy bez stránkování; zobrazená část nemusí být úplná. Změna používá celý veřejný klíč, zachovává známé doplňkové příznaky a po odpovědi čte ACL znovu. Odebrání vlastního přístupu správce formulář blokuje. Hesla mají 1–15 UTF-8 bajtů bez mezer; změna vyžaduje dvojí zadání a potvrzení. Citlivá odpověď firmwaru se nezobrazuje v konzoli ani logu. Po potvrzené změně admin hesla se aplikace odhlásí a podle volby aktualizuje Klíčenku, nebo z ní staré heslo odstraní. Nové přihlášení se netestuje automaticky. Při timeoutu může být heslo již změněné; opakování je ruční.

## Zprávy a zachycená přeposlání

Po připojení se lokálně načtou existující kanály a vyzvednou čekající zprávy. Tyto BLE požadavky nevysílají po LoRa. V **Zprávách** vyberte kanál nebo uložený companion kontakt; konverzaci lze otevřít také z kontaktů tlačítkem **Napsat zprávu**. Odesílání vyžaduje tlačítko **Odeslat** nebo ⌘Enter. Enter v editoru přidává řádek. Počítadlo hlídá UTF-8 bajty, zprávy se automaticky nedělí ani neopakují.

Soukromý chat je povolen jen pro jednoznačně identifikované companion kontakty. Repeater by běžný text interpretoval jako vzdálený CLI příkaz; používejte jeho samostatnou konzoli. Room server chat a změna klíčů či zakládání kanálů zatím nejsou podporované. Aplikace používá kanály již nastavené v companionu.

ACK soukromé zprávy znamená potvrzení protějšku, nikoliv přečtení člověkem. Kanál po odpovědi OK uvádí **Přijato companionem · bez potvrzení doručení**. Timeout nebo odpojení znamená neověřený výsledek; před ručním opakováním počítejte s možností duplicity.

**Zachyceno N přeposlání** roste pouze při příjmu odpovídající kopie z rádiového logu companionu s flood cestou delší než nula. Opětovné vyzvednutí zprávy z fronty čítač nezvýší. Počet může zahrnovat opakování stejného repeateru; neudává unikátní uzly ani všechna přeposlání v síti a nenahrazuje ACK. Firmware posílá raw log jen pro pakety do 173 bajtů; nezachycené pakety, výpadky BLE a provoz mimo dobu připojení se nezapočítají. Nula tedy znamená nula zachycených přeposlaných kopií. Není-li známý klíč kanálu pro přesné párování, počet není dostupný. Počet přeposlání v cestě je jiná metrika jednoho paketu.

Historie obsahuje posledních 5 000 zpráv pro každou identitu companionu v aplikačním sandboxu, v `Library/Application Support/MeshCoreServicer/Messages`. Je uložená jako lokální JSON bez dalšího šifrování aplikací; diagnostický export text zpráv neobsahuje. Klíče kanálů zůstávají pouze v paměti a do historie se neukládají. Po změně klíče se otevře samostatná konverzace; u staré frontované zprávy protokol neuvádí původní klíč. Poškozený soubor historie aplikace automaticky nepřepíše.

## Lokální ad-hoc balíček

Univerzální Release sestavíte bez osobního certifikátu:

```sh
xcodebuild -project MeshCoreServicer.xcodeproj -scheme MeshCoreServicer \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath build build
python3 scripts/package-release.py --app 'build/Build/Products/Release/MeshCore Servicer.app'
```

Balicí skript používá výslovný seznam zdrojových složek, vynechává Xcode uživatelská data a odmítá cesty k domovským adresářům ve zdrojích nebo binárce. Projekt používá mapování cest překladače a odstranění ladicích symbolů z Release aplikace, aby do vydání nevkládal osobní vývojový adresář. Samostatné dSYM se nepřibalují. Nikdy nečte ani nepřibaluje Application Support, preference nebo Klíčenku. Podpis je ad-hoc, bez notarizace; na jiném Macu může být potřeba systémově povolit spuštění. Projekt lze otevřít v Xcode a lokálně sestavit. Veřejný balíček se nikam automaticky nepublikuje.

## Protokol a architektura

Přesné zdroje, UUID, příkazy a omezení párování odpovědí jsou v [PROTOCOL.md](../PROTOCOL.md).

- `Sources/MeshCoreKit/BluetoothTransport.swift`: CoreBluetooth, skenování Nordic UART, discovery charakteristik, systémové zabezpečení, notifikace, potvrzované zápisy, časové limity a obnovení spojení na vyžádání.
- `Sources/MeshCoreKit/Protocol.swift`: nezávislý binární parser a encodery; little-endian hodnoty, kontrola délek a rozlišení obou směrů discovery SNR.
- `Sources/MeshCoreKit/Session.swift`: jedna aktivní operace, lokální odpovědi, stream kontaktů, přihlášení a stav po LoRa, synchronizace CLI odpovědí z fronty companionu, deduplikace a timeouty.
- `Sources/MeshCoreKit/MessagingProtocol.swift`: rámce zpráv, kanály, ACK, dekódování rádiových pozorování a přesné párování kopií skupinového paketu.
- `Sources/MeshCoreServicer/MessagesModel.swift`, `ChatArchive.swift`, `AppModel+Messages.swift`: konverzace, stav doručení, počítání zachycených kopií, lokální historie a koordinace se správou repeateru.
- `Sources/MeshCoreServicer/AppModel.swift`: stav aplikace, autorizace, ověřování dostupnosti, čtení/změny konfigurace, konzole a diagnostika.
- `Sources/MeshCoreServicer/KeychainStore.swift`: Security.framework, účty oddělené celým veřejným klíčem repeateru; bez hesel v UserDefaults či souborech.
- `Sources/MeshCoreServicer/ContentView.swift`, soubory `*Workspace.swift` a `UIComponents.swift`: šest nativních SwiftUI sekcí, systémový světlý/tmavý režim, neblokující průběh a potvrzovací dialogy.
- `Sources/MeshCoreKit/RepeaterTools.swift`: komunitní profil, binární ACL a sousedé, Cayenne LPP telemetrie, validace hodin a vstupů správy.
- `Sources/MeshCoreServicer/AppModel+RepeaterTools.swift`, `RepeaterToolsWorkspace.swift`: stav a UI průvodce a rozšířených nástrojů.
- `Sources/MeshCoreKit/Reliability.swift`: politika obnovování BLE, bezpečný model snímku, vzorky stavu a rádiové kopie.
- `Sources/MeshCoreServicer/NotificationCoordinator.swift`, `AppPreferences.swift`, `AppSettingsView.swift`: systémová oznámení, soukromí a preference; v testech a rendereru jsou systémové služby vypnuté.
- `Sources/MeshCoreServicer/OperationsModel.swift`, `AppModel+Reliability.swift`, `OperationsWorkspace.swift`: historie správy, snímky a jejich obnova, monitoring a kontrola po restartu.
- `Sources/MeshCoreKit/Presentation.swift`: testovatelné hledání, interpretace cest, porovnání hodnot a klávesová historie.

Běžná aplikace nemá demonstrační režim ani fiktivní provozní hodnoty. Samostatný nástroj `scripts/render-previews.sh` slouží pouze k vizuální kontrole; vytváří označené PNG náhledy a nevytváří CBCentralManager ani BLE relaci. Konkrétní příklad rádia ve formuláři je pouze placeholder, nikoliv přednastavená nebo načtená konfigurace. Mapa není součástí této verze.

## Testy a skutečně ověřený rozsah

```sh
swift test
```

V omezeném sandboxu lze použít přesunuté cache:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/meshcore-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/meshcore-swift-cache \
swift test --disable-sandbox --scratch-path /private/tmp/meshcore-servicer-build
```

Ověřeno 24. 10. 2026 na Apple Silicon:

- úspěšné Xcode Release sestavení skutečné `.app`, kontrola `codesign --verify --deep --strict` a plistů;
- **134 automatických testů** binárních rámců, kontaktů a zkrácených vstupů, little-endian pořadí, UTF-8 limitů, firmware/self-info, obousměrných discovery metrik, stavu a oddělení noise floor od RSSI;
- testy hledání a filtrů, zakódovaných cest, porovnání vrácených hodnot, historie vstupu a aplikační logiky ukládání s částečným selháním;
- testy inicializace bez LoRa vysílání, streamu kontaktů, chyb, časového limitu a blokování dalšího požadavku, přihlášení od správného uzlu, předčasné odpovědi, sekvenčního CLI pollingu, duplicit a přerušení BLE zápisu;
- testy DM a kanálových rámců, ACK před odpovědí SENT, pozdního ACK a kolizí, oddělení CLI od chatu, deduplikace vlastního echa, skutečných rádiových kopií proti duplicitám fronty, změny klíče kanálu a nezávislého AES/HMAC testovacího vektoru;
- testy historie podle identity companionu, odmítnutí zastaralého zápisu, zachování poškozeného souboru a zákazu běžných zpráv repeaterům/room serverům;
- testy místního katalogu CLI, českého vyhledávání, předností a deduplikace návrhů, vyřazení citlivé historie, neúplných argumentů, limitů a trvalého nastavení konzole;
- testy univerzálního výchozího nastavení bez zápisů, volitelného komunitního profilu, fallbacku dutycycle/af, potvrzení před zápisem, sekvenčního zpětného čtení, zastavení po chybě a zákazu zápisu ze souhrnu pro dříve vybraný uzel;
- testy binárních tagů včetně předčasné odpovědi, paddingu ACL a sousedů, stránkování, signed SNR, big-endian telemetrie, neznámých typů LPP, hodin UTC, ochrany hesel, prefixů regionů a vlastního ACL přístupu;
- testy zpomalování a ručního zrušení reconnect politiky, soukromí a ztišení oznámení, nečteného stavu minimalizované konverzace, omezení detailu rádiových kopií, výběru polí snímku, obnovy se změněným stavem, monitoringu bez okamžitého vysílání, jeho zastavení a trvalé historie restartu.

**Neověřeno na fyzických zařízeních:** skutečné BLE připojení, systémové párování, vyjednaná velikost zápisu, RF přenos zpráv, reálné ACK a počítání přeposlaných kopií, admin přihlášení, zápis konfigurace a komunitního profilu, telemetrie, ACL, změny hesel a regionů, synchronizace hodin, restart a Keychain interakce. Rovněž nebylo interaktivně ověřeno doručení systémového banneru, zvuku, kliknutí na oznámení, odznak Docku, uspání/probuzení Macu ani skutečné automatické obnovení BLE. Přímé ovládání nativního okna nebylo dostupné (uzavřené spojení služby computer use). Rozložení skutečných SwiftUI obrazovek bylo vizuálně zkontrolované pomocí samostatného offscreen rendereru ve světlém a tmavém režimu; to nenahrazuje interaktivní test okna a fyzických zařízení. Úspěšné sestavení a testy s náhradním transportem nejsou důkazem funkčního BLE spojení s vaším kusem hardwaru.

## Chyby a hranice první verze

- Telefon může držet jediné dostupné BLE spojení a companion se potom při skenování vůbec neobjeví. CoreBluetooth tuto příčinu nedokáže spolehlivě odlišit od nedostupného zařízení; aplikace ji uvádí jako možnou příčinu.
- Zastaralý BLE bond lze odstranit v Nastavení systému → Bluetooth a znovu se spárovat. Aplikace nepřepisuje PIN ani firmware.
- Obnovení BLE po nečekaném výpadku je volitelně automatické. Ruční odpojení je ukončí. Přihlášení, zprávy ani změny konfigurace se neopakují. Vzdálený monitoring je samostatná výslovná volba a po přerušení se znovu zapíná ručně.
- Chybné admin heslo může firmware zahodit bez odpovědi. Timeout není důkaz, že se příkaz neprovedl. CLI odpovědi nemají spolehlivé ID požadavku; po timeoutu je relace blokovaná do odpojení a připojení. Před dalším CLI příkazem se vyprázdní čekající zprávy. Extrémně opožděnou odpověď stejného uzlu nelze v tomto protokolu absolutně vyloučit; po nejistém výsledku vždy nejprve čtěte stav, změnu slepě neopakujte.
- CLI polling sdílí frontu s chatem; soukromé i kanálové zprávy předává do historie a CLI odpovědi zůstávají v konzoli. Odeslání zprávy a správa repeateru sdílí jednu sekvenční relaci.
- RSSI v seznamu BLE je příjem advertu **na Macu**. Discovery má zvlášť příjem odpovědi **na companionu** a SNR požadavku **na repeateru**. Vzdálený stav reportuje poslední paket **na rádiu repeateru**, jehož odesílatele firmware neidentifikuje. SNR CLI zprávy se týká posledního LoRa příjmu na companionu. Noise floor je samostatná úroveň šumu.
- Diagnostický export neobsahuje surové rámce ani text příkazů/odpovědí. Konzole má jen paměťovou historii a skrývá citlivé příkazy i jejich odpovědi. Aplikace neexportuje privátní klíče a nikdy je sama nevyžaduje.
- Vydavatelský certifikát ani přihlašovací údaje nejsou součástí zdrojů. Aktuální DMG je podepsané a notarizované; starší samostatná aplikace a ZIP zůstávají ad-hoc. S novým podpisem se může macOS znovu ptát na oprávnění či přístup ke Klíčence.

## Podepsaná macOS distribuce (Developer ID a notarizace)

Pro bezpečnou distribuci mimo App Store je připravený `scripts/release-macos.py`. Odděluje lokální univerzální archiv, Developer ID podpis a výslovné odeslání k notarizaci. Vydavatelské klíče zůstávají v Klíčence; script přijímá pouze podpisovou identitu a název místního notarytool profilu. Do veřejného `dist` se nové DMG dostane až po schválení aplikace i DMG Applem, připojení ticketů a ověření Gatekeeperu. Samotná přítomnost skriptu neznamená dokončenou notarizaci stávajících ad-hoc ZIPů.

Vydání **0.7.0** bylo 24. 10. 2026 skutečně podepsané Developer ID Application, se zapnutým Hardened Runtime a sandboxem. Apple schválil aplikaci i DMG bez hlášených problémů. Oba artefakty mají připojený notarizační ticket. Ověření podpisů pro arm64 a x86_64, integrity obrazu, Gatekeeper a `syspolicy_check distribution` aplikace uvnitř připojeného DMG prošla. Validační záznam `.validation.json` a kontrolní součet `.sha256` se přikládají k DMG v Releases. Test stažení a prvního spuštění na jiném čistém Macu ještě neproběhl; tato kontrola ani notarizace neověřují BLE komunikaci.

Jednorázové nastavení, příkazy a omezení: [scripts/MACOS_DISTRIBUTION.md](../scripts/MACOS_DISTRIBUTION.md). Vydavatelské údaje se uchovávají pouze v místní Klíčence a ke zdrojům se nepřibalují.
