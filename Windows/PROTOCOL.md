# Protokol Windows portu

Referenční revize aplikace 0.7.3, ověřeno 24. 10. 2026. Windows port používá stejné formáty jako macOS verze; není to webový obal.

- Firmware MeshCore **v1.18.0, commit `81dbae592ffad40b4212bc0b37e82b38da08f4bc`**: [repozitář](https://github.com/meshcore-dev/MeshCore/tree/81dbae592ffad40b4212bc0b37e82b38da08f4bc).
- [Companion MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/companion_radio/MyMesh.cpp): opkódy, offsety, lokální odezvy, fronta, push události, discovery, login, binární požadavky.
- [Repeater MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/simple_repeater/MyMesh.cpp) a [CLI](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/CommonCLI.cpp): vzdálené příkazy, oprávnění, odpovědi, odložená aktivace rádia a anti replay.
- [nRF52 BLE](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp), [ESP32 BLE](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp), [limit rámce](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h).
- Nezávislá kontrola proti [meshcore.js commit `26193c059fcd1d0524f1ad5b19fd88287ecc5c61`](https://github.com/liamcottle/meshcore.js/tree/26193c059fcd1d0524f1ad5b19fd88287ecc5c61).
- [Companion dokumentace](https://docs.meshcore.io/companion_protocol/), [CLI dokumentace](https://docs.meshcore.io/cli_commands/). Dokumentace protokolu je průběžná; při rozporu rozhoduje připnutý zdroj firmware. Podpora na konkrétním uzlu se potvrzuje až skutečnou odpovědí.

## BLE a rámcování

| Účel | UUID |
|---|---|
| Nordic UART služba | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX, Windows → companion, WriteWithResponse | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX, companion → Windows, Notify | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Jedna BLE hodnota je jeden rámec s opkódem v prvním bajtu. Limit rámce je **176 B**. Bez sériové `<`/`>` obálky, bez stream parseru a bez vymyšlené fragmentace. Aplikace čeká na vyjednání `GattSession.MaxPduSize`, odečítá tři bajty ATT a pro plnou podporu požaduje alespoň 176 bajtů hodnoty. Pokud adaptér/firmware potřebné MTU neposkytne, zobrazí se chyba místo dělení rámců. Notifikace se registrují před zápisem CCCD.

Sken sleduje službu i jméno ze samostatných advertisements/scan responses. Nordic UART samo o sobě není důkaz MeshCore; následuje kontrola formátu odpovědí. Přístup a párování jsou systémové Windows BLE operace. Není implementované obcházení autentizace, odhad PIN ani přímé BLE připojení k repeateru.

## Použité companion operace

Čísla jsou v tabulce desítková, push události níže hexadecimální. Celá čísla v companion rámcích jsou little endian; LPP senzory jsou big endian.

| Příkaz | Obsah / odpověď |
|---|---|
| 22 | Query device, inzerovaná verze klienta 3; odpověď 13, včetně modelu/verze a počtu kanálů. BLE PIN se nepublikuje. |
| 1 | App start, identifikační text aplikace; odpověď 5 self info. Nejde o změnu názvu zařízení. |
| 20 | Baterie lokálního companionu; odpověď 12 v mV. |
| 4 | Stream kontaktů: start 2, kontakt 3, konec 4. |
| 30 / 9 | Konkrétní kontakt podle celého klíče / přidání kontaktu. |
| 31 | Lokální kanál podle indexu; odpověď 18. Secret key zůstává pouze v paměti. |
| 10 | Další čekající zpráva; konec odpověď 10. Zprávy 7/16 a kanály 8/17. |
| 26 | Přihlášení repeateru: celý veřejný klíč 32 B + heslo do 15 UTF-8 B. SENT 6 následovaný push 0x85 nebo 0x86 s prefixem 6 B. Bit 0 úspěšné odpovědi označuje správce. Není to totéž jako role v ACL. |
| 27 | Remote status: celý klíč; SENT a push 0x87 s prefixem. |
| 2, type 1 | CLI: type, attempt=0, timestamp UInt32, prefix klíče 6 B, UTF-8 příkaz do 133 B. SENT není odpověď repeateru. Vzdálená odpověď je soukromá zpráva typu 1 ve frontě. |
| 2, type 0 | Soukromá chat zpráva. Povolená jen pro jednoznačný uložený companion kontakt. |
| 3, type 0 | Kanál: index, timestamp, text. Délka zohlední `jméno: text`, max 160 B on-air / 133 B vstupu. |
| 50 | Binární request: celý klíč + payload. SENT vrátí tag; push 0x8c se páruje právě tímto tagem. |
| 55 | Explicitní discovery: `[55,0x80,0x04,tagLE]`; odpověď push 0x8e se kontroluje pomocí tagu a časového okna. Podpora protokol v8+. |

Push 0x80/0x81 vyvolá lokální obnovu kontaktu, 0x83 stažení fronty, 0x82 potvrzuje ACK konkrétního DM. Push 0x88 přináší skutečně přijatý raw paket se signed RSSI a signed SNR děleným čtyřmi. Discovery rozlišuje SNR požadavku na repeateru od RSSI/SNR odpovědi na companionu.

CLI i soukromé zprávy používají adresování prefixem 6 B; při kolizi uložených kontaktů se odeslání blokuje. Přihlášení a binární požadavky mají celý klíč. Nikdy se nezamění textový chat za administraci repeateru.

Před CLI se vyprázdní stará fronta a odstraní staré čekající vzdálené odpovědi. Další požadavek čeká na celé dokončení předchozího; není automatická fronta zápisů ani retry. Push může přijít už před SENT a zůstane zachovaný. Po timeoutu nelze bez request ID pozdní odpověď bezpečně přiřadit: relace vyžaduje BLE reconnect. Odpojení zruší správce i monitoring. Generace relace blokuje pozdní dokončení do jiného profilu.

### Časování dávky od 0.7.3

CLI limit je `clamp(SENT.timeout / 1000 + 15, 45, 180)` sekund; jde o aplikační rezervu pro vysílací frontu a airtime, nikoli změnu protokolu. Vzdálené operace mají minimální mezeru 1,2 s, počítanou i po přijetí předchozí odpovědi. Aplikační CLI timestamp je přísně rostoucí bez umělého posouvání do budoucnosti. Změna generace BLE během této pauzy zabrání odeslání. Timeout stále blokuje relaci; automatický retry neexistuje.

Ve výše připnutém `examples/companion_radio/MyMesh.cpp`, větvi `CMD_SEND_TXT_MSG`, companion nahrazuje timestamp CLI hodnotou `getCurrentTimeUnique()`. Jedinečnost aplikačních značek tedy pomáhá starším companionům; u 1.18.0 ji zajišťuje již companion. `examples/simple_repeater/MyMesh.cpp::onPeerDataRecv` považuje stejný timestamp za retry a nový CLI příkaz neprovede. `src/MeshCore.h::RTCClock::getCurrentTimeUnique` používá rostoucí celosekundové značky. `src/Dispatcher.cpp` řídí vysílání podle budgetu airtime; odhad SENT není důkaz okamžitého vyslání ani vzdálené odpovědi. Ověřeno proti lokálním zdrojům přesného výše uvedeného commitu.

Průvodce rozlišuje přijatou chybu `unknown config` od timeoutu; pouze přijaté odmítnutí dutycycle dovolí přečíst af. Chyba uvádí bezpečný pevný název kroku, nikoliv hodnotu konfigurace; částečná dávka nestaguje komunitní předvolbu a nic nezapisuje.

## Repeater operace

Katalog vznikl z podporovaných vzdálených větví CLI připnutého firmware. `get/set name`, `lat`, `lon`, `tx`, `radio`, `advert.interval`, `flood.advert.interval`, `repeat`, `owner.info`, `dutycycle`, `af`, `path.hash.mode`, `flood.max`, `flood.max.advert`, `flood.max.unscoped`, `loop.detect`. Nepodporovaná pole zůstávají nenačtená; formulář je nepřepisuje.

- `ver`, `board`, `clock`; synchronizace `time <aktuální Unix čas PC>` a zpětné `clock` s kontrolou UTC do ±60 s. Nepoužívá se čas companionu pro řízení tohoto formuláře.
- `advert`, `advert.zerohop`, `reboot`. Restart/ukončovací příkazy nemají vzdálenou CLI odpověď a neoznačují se jako potvrzené provedení.
- `password <heslo>` očekává přesně `password now: <heslo>`, odpověď se skrývá. `set guest.password <heslo>` očekává OK. Zápis systémového hesla se provede až po potvrzené vzdálené odpovědi.
- Telemetrie request `[3,0,0,0]`, ACL `[5,0,0]`; neznámé LPP typy se neodhadují.
- ACL `setperm <celý klíč> <byte oprávnění>` zachová načtené doplňkové příznaky při změně role; vlastnímu companionu se odebrání správy formulářem blokuje. Prefixy v odpovědi neprokazují kompletnost seznamu.
- Sousedé request `[6,0,3,offsetLE16,0,32,nonceLE32]`; stránka má total/count a max tři záznamy s plným klíčem, stářím a signed SNR. Limit 128 stránek zabraňuje nekonečnému načítání.
- Regiony: `region`, `region home`, `region default`; `region put/remove/allowf/denyf/home/default`, pak `region save` a nové čtení. Před operací nad existujícím regionem se přesný celý název kontroluje pomocí `region get`, protože firmware umí vybírat shody prefixu. Konzervativní formulář odmítne nejednoznačný výsledek.

Zápis nastavení vždy vyžaduje OK a odpovídající zpětné `get`. Radio se ukládá pro restart; čtení hodnoty není potvrzením aktivního rádia. Batch se zastaví při první chybě; neověřený záměr zůstane v historii. `dutycycle` a `af` jsou alternativní reprezentace stejného pole, nesmějí se zapisovat současně.

RSSI ve statusu je síla posledního paketu přijatého **repeaterem**, s neurčeným odesílatelem; noise floor je samostatná veličina. SNR souseda patří příjmu na repeateru, SNR zprávy/kanálové kopie příjmu na companionu, RSSI skenu BLE příjmu na PC.

## Windows primární zdroje

- [WPF](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/), [WinRT API z desktopové aplikace](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps).
- [Bluetooth GATT klient](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client), [systémové párování](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/pair-devices). Custom pairing používá systémové úložiště párování; nativní UI pouze získá uživatelův skutečný PIN nebo potvrzení.
- [Credential Manager](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew), [oznámení Shell_NotifyIcon](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw).
