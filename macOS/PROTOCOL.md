# Ověřené zdroje protokolu

Ověřeno 23. 10. 2026, rozšíření nástrojů znovu ověřeno 24. 10. 2026 přímo proti staženým zdrojům:

- **MeshCore `81dbae592ffad40b4212bc0b37e82b38da08f4bc`**, referenční firmware v1.18.0-81dbae5; konkrétní deska není předpokladem aplikace.
- **meshcore.js `26193c059fcd1d0524f1ad5b19fd88287ecc5c61`**, `master`; původní adresa `liamcottle/meshcore.js` přesměrovává na `meshcore-dev/meshcore.js`.
- [Oficiální dokumentace companion protokolu](https://docs.meshcore.io/companion_protocol/), [CLI](https://docs.meshcore.io/cli_commands/), [struktury statistik](https://docs.meshcore.io/stats_binary_frames/).

Firmware je rozhodující, pokud dokumentace nebo starší parser meshcore.js vynechává nová pole. Aplikace posílá `DEVICE_QUERY [22,3]` (klientský formát v3 kvůli SNR zpráv); aktuální companion na tomto commitu hlásí firmware protocol code 14. Nejde o totožná čísla verzí.

## Zdrojové odkazy připnuté na commit

- [MyMesh.cpp companionu](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp): kódy, encodery odpovědí, `handleCmdFrame`, `queueMessage`, přihlášení, stav a control push.
- [nRF52 BLE transport](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp): MITM zabezpečení a PIN, Nordic UART, fronty rámců a připojení po zabezpečení.
- [meshcore.js BLE konstanty](https://github.com/meshcore-dev/meshcore.js/blob/26193c059fcd1d0524f1ad5b19fd88287ecc5c61/src/constants.js), [BLE transport](https://github.com/meshcore-dev/meshcore.js/blob/26193c059fcd1d0524f1ad5b19fd88287ecc5c61/src/connection/web_ble_connection.js), [encodery a odpovědi](https://github.com/meshcore-dev/meshcore.js/blob/26193c059fcd1d0524f1ad5b19fd88287ecc5c61/src/connection/connection.js).
- [BaseChatMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseChatMesh.cpp): `sendLogin`, šifrované LoRa datagramy a `sendCommandData`.
- [Repeater MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/simple_repeater/MyMesh.cpp), [RepeaterStats](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/simple_repeater/MyMesh.h): admin ACL, odpovědi na CLI, binární status, discovery.
- [CommonCLI.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/CommonCLI.cpp), [CommonRadioPrefs.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/CommonRadioPrefs.cpp): skutečné názvy a rozsahy nastavení.
- [Control payloady](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/docs/payloads.md): discovery požadavky a odpovědi.

## BLE

| Účel | UUID |
|---|---|
| Nordic UART služba | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX z pohledu companionu; Mac zapisuje | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX z pohledu companionu; Mac odebírá notifikace | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Jeden BLE zápis/notifikace = jeden companion rámec. Žádná sériová hlavička `<`/`>`, délka ani dodatečné CRC. Firmware limit je 176 bajtů (`BaseSerialInterface.h`). Transport používá `.withResponse`, nikdy svévolně nefragmentuje a kontroluje `maximumWriteValueLength`. Pokud se rámec nevejde, operace skončí chybou. Zápisy i očekávané odpovědi jsou dokončené před dalším požadavkem.

nRF52 používá `SECMODE_ENC_WITH_MITM`, firmware PIN a systémové bondování. Přístup k chráněným charakteristikám má vyvolat systémové párování CoreBluetooth. Vlastní BLE login rámec se neposílá.

## Implementované operace

Čísla jsou desítková, pokud mají prefix `0x`, jsou hexadecimální. Vícebajtové hodnoty jsou little-endian.

| Operace | Požadavek | Odpověď |
|---|---|---|
| Informace o firmwaru | `22,3` | `13`: protokol, kapacity, BLE PIN (přeskočen), build[12], model[40], verze[20] |
| Lokální self-info | `1,1,0,0,0,0,0,0` + název aplikace | `5`: identita a rádio companionu |
| Lokální baterie | `20` | `12` + millivolty u16 |
| Kontakty | `4` | `2` začátek, `3` jednotlivé kontakty, `4` konec |
| Kontakt podle klíče | `30` + veřejný klíč[32] | `3` |
| Výslovné uložení nového kontaktu | `9` + kontaktní struktura bez volitelného lastmod | `0` / `1,error` |
| Admin login po LoRa | `26` + veřejný klíč[32] + UTF-8 heslo (max. 15 bajtů) | `6` přijetí k odeslání, `0x85` potvrzení s admin bitem a prefixem[6], případně `0x86` nebo timeout |
| Stav / ping | `27` + veřejný klíč[32] | `6`, poté `0x87,0,prefix[6],RepeaterStats` |
| Vzdálené CLI | `2,1,0,timestamp[4],prefix[6],UTF-8 příkaz` | `6`, potom frontovaná CLI zpráva |
| Synchronizace čekající zprávy | `10` | `7` / `16` kontaktní zpráva, `8` / `17` kanálová zpráva, `10` konec |
| Čtení kanálu | `31,index` | `18,index,name[32],secret[16]`; počet slotů je v DeviceInfo |
| Soukromá zpráva | `2,0,0,timestamp[4],prefix[6],UTF-8 text` | `6` lokální přijetí, případně `0x82` ACK protějšku |
| Kanálová zpráva | `3,0,index,timestamp[4],UTF-8 text` | `0` OK, nikoliv `6`; bez potvrzení doručení |
| Binární vzdálený požadavek | `50,key[32],requestPayload` | `6` s tagem u32, poté `0x8c,0,tag[4],responsePayload` |
| Discovery (companion v8+) | `55,0x80,0x04,tag[4]` | `0` lokální přijetí; `0x8e` control push s discovery payloadem |

`6` obsahuje flag direct/flood, tag/ACK pole a doporučený timeout v ms. Neprokazuje příjem repeaterem. Aplikace respektuje timeout s rezervou a limitem 180 s.

`0x80` a `0x81` nesou veřejný klíč a vyvolávají lokální obnovení kontaktu. `0x8a` obsahuje úplný kontakt z advertu, který ještě nemusí být uložený. Kontaktní typy: companion 1, repeater 2, room server 3 (dále senzor 4).

CLI odpověď má txt_type 1. V3 zpráva `16` obsahuje SNR/4, dva rezervované bajty, prefix[6], path, typ, timestamp[4], text. Timestamp odpovědi **není** echo ID požadavku. Proto není používán jako korelační ID. Přihlášení a stav se kontrolují proti prefixu cíle. Každá úplná vzdálená operace je výhradní, ne pouze jednotlivý BLE zápis. Před CLI se odeberou staré čekající zprávy, duplicity jsou potlačené. Po nejednoznačném timeoutu je nutné obnovit relaci.

Control push `0x8e` má SNR příjmu/4 na companionu, RSSI na companionu, path a control payload. Discovery odpověď obsahuje `0x90 | node_type`, SNR původního požadavku/4 na repeateru, tag[4] a klíč[8 nebo 32]. Aplikace žádá plný klíč, filtruje tag a 30s okno. Žádné discovery nevysílá při připojení.

Binární status má základ 48 bajtů: baterie u16, fronta u16, noise floor i16, last RSSI i16, osm u32 čítačů včetně airtime/uptime, err_events u16, last SNR i16/4, dva u16 čítače duplicit. Volitelně následují RX airtime a chyby příjmu jako u32. Firmware přidává metriky vlastního posledního rádiového příjmu, nikoliv měření celého vzdáleného spoje.

## Chat a potvrzení

Formát kontaktní zprávy po případném V3 prefixu je `prefix[6],path,txt_type,timestamp[4],text`. Podepsaná zpráva typu 2 má ještě čtyřbajtový prefix autora před textem. Typ 1 zůstává CLI a nezobrazuje se jako chat. Kanálová zpráva má `index,path,txt_type,timestamp[4],text`; firmware přidává do textu `jméno: `. V3 rámce 16/17 mají na začátku signed SNR/4 a dva rezervované bajty. Path je kódovaná délka: horní dva bity určují velikost hashe minus jedna, dolních šest počet hopů; 255 značí neurčenou/přímou cestu ve frontované zprávě. Hodnota se nezobrazuje jako prostý počet bajtů.

SENT `6` obsahuje route flag, očekávaný ACK u32 a timeout u32. ACK `0x82` má kód u32 a round-trip v ms u32. Očekávaný kód se uchová i po timeoutu pro případ pozdního ACK; kolize mezi uloženými zprávami se označí jako nejednoznačná. ACK není potvrzení přečtení. Kanálový příkaz v připnutém `handleCmdFrame` vrací pouze OK a aplikace to nezaměňuje za doručení.

Limit aplikace je konzervativních 133 UTF-8 bajtů. U kanálu se navíc hlídá limit `160 - délka jména - 2`, aby firmware nezkrátil doplněné jméno a text. Posílá se pouze přes oficiální companion příkazy. Čtení slotů a vybírání fronty jsou lokální BLE operace; po připojení nevyvolají LoRa vysílání. Odesílání je výslovné a bez automatických opakování.

## Počet zachycených přeposlání kanálové zprávy

Companion automaticky posílá `PUSH_CODE_LOG_RX_DATA 0x88,snr/4,rssi,rawPacket` před dekódováním a odstraněním duplicit. [Companion MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp), [Packet.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/Packet.cpp), [Mesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/Mesh.cpp) a [Utils.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/Utils.cpp) určují následující formát.

Dolní dva bity raw hlavičky jsou route, další čtyři payload type a horní dva payload version. Parser přijímá skupinový text typu 5/verze 0; route 0 a 3 mají čtyřbajtovou transportní část před cestou. Přeskočí se kódovaná cesta včetně vícebajtových hashů. Cesta ani transportní část nejsou součástí identity obsahu.

Pro přesné přiřazení se ze známé dešifrované zprávy reprodukuje skupinový payload připnutého firmwaru: první bajt SHA256 šestnáctibajtového klíče kanálu, první dva bajty HMAC-SHA256 ciphertextu s klíčem doplněným šestnácti nulami a AES-128-ECB ciphertext nulami doplněného `timestamp[4],txt_type,text`. Aplikace používá systémové CommonCrypto a CryptoKit. Interní otisk je plný SHA256 z `[5] + payload`; nejedná se o nový formát síťového paketu. Shoda se ověřuje proti celému otisku, nikoliv jen jednobajtovému hashi kanálu. Test obsahuje nezávislý AES/HMAC vektor.

Každý odpovídající raw příjem s flood route 0/1 a neprázdnou cestou zvýší čítač o jednu. Opakovaná dekódovaná zpráva z fronty jej nezvyšuje; vlastní echo se připojí k původnímu odeslanému záznamu bez změny stavu doručení. Počet není počet unikátních repeaterů, globální síťový součet ani ACK. Log se nevysílá pro raw pakety přes 173 bajtů a nezachytí výpadky BLE nebo dobu odpojení. RSSI/SNR raw pozorování patří k dané kopii přijaté companionem. Klíče ani ciphertext se nezapisují do historie nebo diagnostiky.

## Vzdálené nastavení

Použité přesné příkazy: `get/set name`, `get/set lat`, `get/set lon`, `get/set tx`, `get/set radio`, `get/set advert.interval`, `get/set flood.advert.interval`, `get/set repeat`. `set radio freq,bw,sf,cr` ukládá nastavení a odpovídá `OK - reboot to apply`. `advert` je flood advert. `reboot` neposílá odpověď. `stats-core`, `stats-radio`, `stats-packets` jsou sériové příkazy, proto pro vzdálené statistiky používáme binární status, nikoliv tyto lokální CLI příkazy.

### Rozšíření 0.4 · prvotní nastavení a nástroje

Všechny následující příkazy jsou ověřené v připnutém `CommonCLI.cpp`, `CommonRadioPrefs.cpp`, companion `MyMesh.cpp` a repeater `MyMesh.cpp` výše. Volitelná předvolba české komunity zachycuje postup z 24. 10. 2026; není univerzálním výchozím nastavením ani automaticky aktualizovaným doporučením.

| Účel | Použité CLI / binární tělo | Potvrzení a omezení |
|---|---|---|
| Flood perioda | `get/set flood.advert.interval`, profil `25` | Hodiny, 0 nebo 3–168; OK a čtení stejné hodnoty |
| Zero-hop perioda | `get/set advert.interval`, profil `0` | Minuty; 0 vypíná, jinak sudé 60–240 |
| Duty cycle | `get/set dutycycle`, profil `10` | Zpětné čtení např. `> 10.0%`; porovnání s tolerancí půl posledního desetinného místa |
| Starší alternativa | `get/set af`, profil `9` | `dc = 100 / (af + 1)`, tedy af 9 = 10 %; neposílají se oba zápisy |
| Hash cesty | `get/set path.hash.mode`, profil `1` | 0/1/2 znamená 1/2/3 bajty hashe; týká se budoucích cest/advertů, ne přepsání historie |
| Veřejný kontakt | `get/set owner.info` | Úložiště 120 bajtů; aplikace max. 118 UTF-8 kvůli 133bajtovému limitu celého CLI příkazu. `|` reprezentuje nový řádek |
| Hodiny | `time <Unix epoch>`, následně `clock` | Čas Macu vzniká při provádění kroku. Firmware přijme jen vyšší čas a vrací `OK - clock set…`; readback UTC má přesnost minut. `clock sync` by používal timestamp companionu, proto jej aplikace pro čas Macu nepoužívá |
| Verze/hardware | `ver`, `board` | Skutečný text odpovědi repeateru |
| Advert | `advert`, `advert.zerohop` | Ruční aktivní vysílání, CLI odpověď potvrzuje přijetí příkazu repeaterem |
| Discovery sousedů | `discover.neighbors` | Ruční aktivní vysílání repeateru; později načíst seznam |
| Síť | `get/set flood.max`, `flood.max.advert`, `flood.max.unscoped`, `loop.detect` | Limity 0–64; detekce off/minimal/moderate/strict. Zpětné ověření |
| ACL čtení | Binární tělo `05,00,00` | Pole záznamů `prefix[6],permissions[1]`; bez počtu a stránkování. Odpověď nemusí obsahovat všechny uživatele |
| ACL změna | `setperm <celý veřejný klíč hex64> <perms>` | Dolní dva bity 0=odebrání, 1=read-only, 2=read-write, 3=admin. Načtené horní bity se zachovají. Následuje nové binární čtení; ověření je omezené prefixem a částí seznamu |
| Heslo správce | `password <heslo>` | Firmware vrací `password now: <heslo>`; aplikace odpověď porovná v paměti a nezobrazí ani nezaloguje. Pak zruší admin stav; nové přihlášení je samostatné |
| Heslo hosta | `set guest.password <heslo>` | OK; aplikace si aktuální heslo nevyžaduje a trvale je neukládá |
| Regiony | `region`, `region home`, `region default`; změny `region put/remove/allowf/denyf/home/default`, pak `region save` | Ověřuje se přesný název existujícího regionu/rodiče, aby prefixové vyhledávání nezměnilo jiný region. Následuje potvrzení, trvalé uložení a nové čtení přehledu. Souhrn může být zkrácený |

Binární požadavky používají jedinou výhradní relaci jako CLI a přihlášení. Tag se přebírá ze SENT, nikoliv z lokálně odhadnutého času. Předčasná odpověď se uchová, jiný tag se ignoruje. Companion autentizuje odpověď od známého cíle; aplikace žádný vlastní šifrovaný datagram nevysílá. Není použit zastaralý požadavek 39 pro telemetrii.

**Telemetrie:** binární tělo `03,00,00,00` (inverzní maska 0 povoluje všechny dostupné senzory), odpověď obsahuje Cayenne LPP z připnutého firmwaru ([`electroniccats/CayenneLPP` 1.6.1](https://github.com/ElectronicCats/CayenneLPP/blob/1.6.1/src/CayenneLPP.h), viz `platformio.ini` a `src/helpers/sensors/LPPDataHelpers.h`). Číselné hodnoty jsou big-endian, na rozdíl od companion polí; signed teplota /10, napětí /100, vlhkost jeden bajt /2. Parser zachovává kanál senzoru, zná běžné skalární i vektorové typy, kontroluje délky a při neznámém typu zastaví dekódování bez hádání dalšího offsetu. Zobrazené hodnoty jsou snímek z repeateru; teplota není automaticky označována za venkovní/okolní.

**Sousedé:** binární tělo `06,00,count,offset[u16 LE],order,prefixLength,nonce[u32 LE]`. Aplikace žádá count 3, pořadí 0 (nejnovější), plné klíče délky 32. Odpověď `total[u16],count[u16]`, poté `key[32],heardSecondsAgo[u32],snr[i8]/4`. Stránkuje se do dosažení hlášeného počtu; seznam se mezi odpověďmi může změnit a uložený soused neznamená online stav. SNR je poslední příjem daného souseda na vzdáleném repeateru.

Přímé LoRa datagramy obsahují po dešifrování nulový padding AES do 16 bajtů. Binární parsování ACL, sousedů a telemetrie jej zohledňuje a nevytváří z něj fiktivní záznamy. ACL prázdná odpověď může obsahovat 12 nul za odstraněným čtyřbajtovým tagem.

Změna identitního klíče, generování nové předpony, bulk import/definice regionů a factory reset nejsou formuláři implementované. Změna identity je zásah do soukromého klíče i adresy uzlu a není součástí komunitního profilu.

Heslo je na lokálním BLE úseku uvnitř zabezpečené charakteristiky; autentizaci, derivaci shared secret a šifrování vysílaných LoRa zpráv provádí companion firmware. Aplikace nevysílá vlastní kryptografické raw pakety. Lokální reprodukce skupinového payloadu slouží pouze k párování zachycených kopií. Aplikace nevyžaduje soukromou identitu companionu a neprovádí firmware update ani factory reset.

## Rozšíření 0.5 · spolehlivost a lokální historie

Protokolový commit se nemění: firmware `81dbae592ffad40b4212bc0b37e82b38da08f4bc`, JS reference `26193c059fcd1d0524f1ad5b19fd88287ecc5c61`. Nové obrazovky používají již implementované příkazy status, get/set a frontu zpráv. Nevzniká nový opkód, BLE UUID ani vlastní síťový formát.

- CoreBluetooth obnova je místní politika spojení s backoff 1–30 s, nikoliv opakování protokolového požadavku. Po výpadku se zruší čekající operace a admin relace. Ruční odpojení zruší záměr připojení. Čeká se na dokončení rušeného připojení; pozdní callback starého objektu se nepřijímá jako ukončení jiné relace. Párovací chyby chráněných charakteristik a zrušený bond vyžadují ruční zásah.
- Volitelný monitoring posílá existující status request 27 až po celém zvoleném intervalu. Sdílí výhradní session s CLI a chatem. Obsazená relace znamená přeskočený interval, chyba monitoring zastaví. Nenásleduje automatické přihlášení ani reset/změna konfigurace.
- Snímek má výslovný seznam povolených konfiguračních klíčů `CLIValidation.keys`. Hesla a privátní identita na seznamu nejsou. Při importu se kontroluje verze, celý veřejný klíč companionu i repeateru, rozsahy hodnot, velikost souboru a konfliktní dvojice dutycycle/af. Porovnání používá aktuální get. Po potvrzení se všechna měněná pole znovu přečtou před prvním set; každý set má následné get. Protokol nemá atomickou transakci ani compare-and-swap, takže souběžnou externí změnu po posledním čtení absolutně vyloučit nelze. Při selhání uprostřed se již provedené změny nevracejí.
- Detail kanálové zprávy uchovává posledních 64 raw pozorování metadat (čas Macu, počet hopů, RSSI a SNR konkrétního příjmu na companionu). Souhrnný čítač obsahuje i dřívější zachycené kopie mimo tento detail. Historické zprávy verze 0.3/0.4 lze načíst i bez pole captures; chybějící příjmy se nevyrábějí zpětně. Nepersistuje se raw ciphertext ani klíč kanálu.
- Notifikace používají [Apple UserNotifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app), odznak Docku AppKit a nastavení aplikace SwiftUI. Oprávnění se žádá pouze při zapnutí uživatelem. Počáteční čtení fronty nevyvolává upozornění; duplicita, CLI, vlastní zpráva nebo právě čtená konverzace je nevytvoří. Kliknutí přenáší jen identitu companionu a konverzace. Žádné push servery nebo vzdálené služby nejsou použité.
- Historie restartu rozlišuje zadaný požadavek bez potvrzení provedení, možný restart odvozený z uptime, novou odpověď na status a samostatné čtení správného UTC. Uchovává pouze názvy neověřených kroků a data, nikoliv hesla nebo celé citlivé příkazy. Uložené rádio před restartem není označené za potvrzené aktivní rádio.


## Místní katalog vzdálené konzole (0.6)

`ConsoleCatalog.swift` vychází ze stejného commitu firmwaru uvedeného výše. Nabízí vzdálené `ver`, `board`, `clock`, `neighbors`, `region`, `region home`, `region default`, `get`/`set` pro explicitní whitelist validátoru, `time`, `advert`, `advert.zerohop` a `reboot`. Formáty jsou z `CommonCLI.cpp` a `CommonRadioPrefs.cpp`, porovnané s [CLI dokumentací](https://docs.meshcore.io/cli_commands/). Nevkládá osobní hodnoty ani doporučenou frekvenci. Čtecí příkazy stále vyvolávají požadavek po LoRa až výslovným odesláním.

Položka katalogu není zárukou podpory připojeným firmwarem. Sériové příkazy (`stats-*`, `get acl`, čtení privátního klíče) se nenabízejí. Nastavení hesel a identity patří do samostatných ověřených formulářů; nevyužívá se historie jejich argumentů. Přijetí návrhu mění jen vstupní pole. Známé argumenty procházejí stejným validátorem jako formuláře; neznámé ručně zadané příkazy zůstávají dostupné s běžným limitem rámce. Nová verze nemění BLE UUID, rámcování, autentizaci ani způsob párování odpovědí.


## Profily, evidence odpovědí a kontroly (0.7)

Rámcování, UUID a autentizace se v této verzi nemění. `MeshSession.onCLIReply` oznamuje pouze skutečně přiřazenou odpověď typu CLI od požadovaného uzlu. `noReply` tuto událost nevytváří. Evidence ukládá identitu companionu a repeateru, úplnou načtenou verzi firmwaru, typ příkazu a výsledek, bez argumentů a textu odpovědi. Chybějící verze omezuje evidenci na konkrétní BLE relaci. Obecná chyba argumentu se nezaměňuje za výslovně nepodporovaný příkaz; úspěšná odpověď není zpětné ověření změny.

Profily obsahují pouze místní volby, název a poslední BLE identifikátor. Při připojení uloženého profilu se kontroluje skutečný veřejný klíč z self-info; neshoda spojení ukončí. Profil neobsahuje radio presety, admin relaci nebo heslo a nevyvolává automatický monitoring. Hesla zůstávají ve stávající službě Keychain.

Neověřený zápis známého nastavení může mít uloženou zamýšlenou hodnotu. Kontrola posílá pouze existující `get <klíč>` a porovnává skutečný stav; při absenci záměru nebo neshodě zůstává položka otevřená. Kontrola hodin používá `clock`, dostupnosti binární status a uloženého rádia `get radio`. Žádná z těchto kontrol neopakuje zápis. Čtení uloženého rádia neprokazuje parametry aktuálně použitého RF ovladače. Po timeoutu musí být nejprve ručně obnovena relace; kontrola nemůže obejít stav `requiresReconnect`.

Diagnostický report používá konečný seznam kategorií událostí a extrakci čísel verzí, nikoliv původní řádky logu. Exportuje se zobrazený neměnný snímek. Ručně zadané výsledky hardware testů jsou samostatné uživatelské údaje, vázané také na firmware companionu, verzi aplikace, macOS a architekturu. Aplikace je nezaměňuje za automatické ověření a nic nikam neposílá.
