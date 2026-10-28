# Windows BLE: 0.8.1 a cílená úprava zdrojů 0.8.2

Stav 25. 10. 2026. Oprava je zahrnutá do lokálních instalačních
balíčků 0.8.1; veřejné publikování nebylo provedeno. Samotný přechod z 0.7.3 na 0.8.0 tuto opravu nedokládá.

## Nový export 0.8.1 a úprava zdrojů 0.8.2

Dodaný redigovaný export Windows 0.8.1 x64, build OS 26200, dokládá úspěšné
otevření objektu zařízení, povolený přístup a vytvoření objektu GATT relace.
Při vyhledání služby nastane po přibližně 1,08 s nativní HRESULT `0x80070016`
(`ERROR_BAD_COMMAND`). Úklid skončí úspěšně. Nejde o dosažení 20s limitu.
Charakteristiky, notifikace a MeshCore inicializace ještě nezačaly; počáteční
MTU 23 u vytvořeného objektu relace neprokazuje nedostatečné výsledné MTU.
Export neurčuje příčinu ve firmware, párování nebo ovladači. Kód Windows
není odmítnutý příkaz MeshCore a neprokazuje chybu vzdáleného repeateru.

Zdrojová 0.8.2 používá místo `GetGattServicesForUuidAsync` jedno úplné
`GetGattServicesAsync(BluetoothCacheMode.Uncached)` a poté vybírá **přesné NUS
UUID**. Jde o dokumentovanou alternativní cestu vyhledání, nikoli automatický
retry po chybě. Ostatní služby se uvolní. Timeouty, úklid pozdních výsledků,
RX Write, TX Notify, zabezpečení a požadavek na celé rámce zůstávají.
Toto čtení GATT služeb nespouští MeshCore CLI, zápisy konfigurace ani LoRa.
**Úspěch úplné enumerace na tomto Dellu/T-Decku zatím nebyl ověřen.**

V exportu je tatáž běžná nativní chyba navíc nesprávně označená
`LateFaultObserved`. Příčinou této prokázané vady logu byl obecný catch
v `BleNativeOperation.Await`: připojoval zpracování pozdního výsledku i na
již přímo pozorovanou výjimku. V 0.8.2 se takto sleduje jen výsledek po
zrušení čekání tokenem. Běžná nativní chyba se propíše právě jednou.
Skutečné pozdní chyby po timeoutu se nadále pozorují a prostředky se uvolní.

Oba diagnostické exporty obsahují pevnou revizi
`windows-ble-enumerate-services-2`, aby šlo rozlišit tuto změnu i bez úspěšného
připojení. Starší 0.8.1 instalační soubory změnu neobsahují. Nový instalátor
ani veřejné vydání 0.8.2 se v tomto kroku nevytvářejí.

## Původní hlášení

Dell, Windows 11, Servicer 0.7.3 x64; T-Deck Plus s firmwarem **Wadamesh beta**.
Uživatel jej upřesnil jako „aktuální beta“, přesné číslo/verze sestavení ale
není doložené. Uživatel uvádí systémové spárování, úspěšné
připojení oficiální aplikace a úspěšný sken v Serviceru. Dialog po stisku Připojit
byl bez vysvětlení; dosavadní log nerozlišoval fáze.

**Příčina selhání tohoto zařízení není prokázaná.** Z hlášení nelze určit párování,
firmware, ovladač, obsazené spojení ani MTU. Funkční jiný klient je důležitá
okolnost, ale neurčuje, která operace v Serviceru selhala.

V původním kódu jsou doložené jiné vady: přímé použití prázdné Exception.Message,
stejné logování předběžného úklidu a ukončení relace, neomezené čekání na některé
WinRT operace a spolknutí chyby protokolové inicializace. Regresní test navíc
odhalil pořadí zrušení/úklidu, při němž mohl být ruční konec označen jako chyba.
Tyto opravy nejsou důkazem odstranění fyzického problému T-Decku.

## Implementace

- `BleConnectionFlow` v jádře řídí otevření, oprávnění, GATT relaci, službu,
  charakteristiky, CCCD/notifikace, MTU a místní inicializaci MeshCore.
  `NativeBleConnection` je jeden vlastník nativních objektů na jeden pokus.
- Fáze mají Started/Succeeded/Failed/Cancelled a náhodné ID pokusu. Chyba má
  nezávislý identifikátor MC-BLE, fázi, důvod z pevného číselníku a dostupné
  HRESULT, GATT status, protokolový kód či skutečně přečtené MTU. Prázdné a syrové
  WinRT texty se nepoužívají pro vysvětlení chyby. Ostatní chybové dialogy mají
  neprázdný náhradní text, fázi a MC-APP identifikátor.
- Nativní fáze: limit 20 s; zjištění MTU čeká na změnu nejvýše 15 s, místní
  protokolová inicializace nejvýše 2 minuty, celý pokus nejvýše 3 minuty.
  Limit aplikace není tvrzení, že Windows nativní operaci zastavil.
- Pozdní výsledky se neadoptují; pozdě vrácené zařízení, relace a služby se
  uvolní. Pozdní chyby jsou pozorované, exportuje se pouze typovaný číselný
  záznam. Pozdní callback z předchozího vlastníka nemůže odpojit nový spoj.
- Notifikace a stav spojení se hlídají už během připojování. Počáteční stav
  Disconnected sám o sobě není neočekávaná ztráta již navázaného spoje.
- Úklid rozlišuje BeforeConnect/User/Sleep/Shutdown/Failure/Unexpected;
  úklid prázdného transportu nevyvolává událost odpojení. Neúspěch jednoho
  uvolnění nezabrání uvolnění ostatních objektů. Před dialogem se ukončí
  připojovací stav a nativní prostředky se uvolní.
- Připojení není souběžné ani řazené do fronty. Volitelná automatická obnova
  přerušeného BLE spoje po selhání další pokusy sama neplánuje; nový pokus je
  ruční. Správce ani diagnostické měření se automaticky neobnovují.

## Protokol, kompatibilita a bezpečnost

Referenční protokol zůstává MeshCore v1.18.0, commit
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`. Přesná beta verze hlášeného T-Decku
není známá a její kompatibilita se tímto auditem neprokazuje.

Používají se přesné NUS UUID z [PROTOCOL.md](../PROTOCOL.md), uncached vyhledání,
RX s Write a TX s Notify. Handler ValueChanged je připojen před zápisem CCCD.
CCCD používá API WithResult, aby zůstal zachovaný i ProtocolError. Není přidán
fallback na libovolnou jinou službu, WriteWithoutResponse, obcházení párování,
odhad PINu ani oslabení ochrany charakteristik. Souhlas/oprávnění se vyžadují
přes Windows na UI vlákně. Systémové párování zůstává samostatná uživatelská akce.

Windows MTU vyjednává samo; aplikace sleduje MaxPduSize a MaxPduSizeChanged.
Dosavadní konzervativní požadavek pro plné rámce zůstává ATT MTU >= 179
(176 B + 3 B ATT). Při nedostatečné hodnotě se oznámí naměřená hodnota;
MeshCore rámce se nerozdělují do aplikačních zápisů. Windows dokumentuje také
vlastní ATT fragmentaci, ta však nedokazuje podporu dlouhých zápisů/notifikací
konkrétní variantou companion firmware.

Připnutý ESP32 SerialBLEInterface volá `setMTU(MAX_FRAME_SIZE)` s rámcovým limitem
176, nikoli 179, a nastavuje šifrování s MITM. To je relevantní kompatibilitní
omezení dosavadní politiky plného rámce, **nikoli důkaz příčiny z uživatelského
hlášení**. Bez skutečné hodnoty MTU a ověření celé výměny nelze tvrdit, že daná
beta má stejné chování, ani bezpečně povolit neověřenou fragmentaci.

### Upřesnění pro Wadamesh

Prohlédnutý oficiální repozitář Wadamesh má commit
`ce0b6380249f742d56f052b5e346a91d2ad55a82`. Jeho prostředí
`LilyGo_TDeck_companion_radio_touch` používá `MULTI_TRANSPORT_COMPANION`
a NimBLE-Arduino 1.4.3. Základ závislosti `core-v1.18.0` z repozitáře
ALLFATHER-BV/meshcomod byl ověřen na commitu
`6a8906212e9071efa4d3699a623b1a5ec8e2de6e`.

Tento základ používá stejné NUS UUID, RX Write, TX Notify a zabezpečení
Secure Connections + MITM + bonding. Přijatý BLE zápis je jeden rámec;
zdroj neprovádí skládání libovolných aplikačních fragmentů.
Wadamesh ale po základním `begin()` v `MultiTransportCompanionInterface`
přenastavuje MTU na `MAX_FRAME_SIZE + 3`, tedy **179**, a to i při pozdějším
zapnutí BLE. Závěr o základním ESP32 MTU 176 proto nelze přenášet na tuto
variantu Wadamesh. Hodnota nastavená ve zdroji sama také nedokazuje skutečně
vyjednané MTU na konkrétním spojení s Windows.

Kontrola těchto připnutých zdrojů není identifikací firmware nahraného
v hlášeném zařízení. Není podkladem pro označení chyby za chybu Wadamesh,
párování či MTU a nevede ke změně UUID, zabezpečení ani rámcování Serviceru.

Inicializace odesílá jen místní BLE dotazy (device query 22, app start 1,
baterie 20, kanály 31, čtení fronty 10). Neprovádí vzdálené CLI, discovery,
přihlášení repeateru, změnu času, advert, konfiguraci ani LoRa měření.
Limity [diagnostického měření](TRAFFIC_POLICY.md) zůstávají na obou platformách:
od zdrojové verze 0.8.2 3 vzorky po 4 hodinách, interval 3–24 hodin, nejvýše
6 vzorků během 24 hodin. Společný servisní rozpočet a zákaz automatického
obnovení zůstávají zachované.
Žádný interval není univerzálně bezpečný.

## Krátký postup pro hlásícího uživatele

1. Použít nové testovací sestavení ze zdrojů 0.8.2 obsahující tuto úpravu.
   V exportu před pokusem ověřit revizi `windows-ble-enumerate-services-2`;
   původní instalátor 0.8.1 nestačí.
   Poznamenat Windows build, architekturu a přesné označení Wadamesh beta firmware,
   pokud je lze zjistit na zařízení nebo z původu firmware. Neprovádět reset,
   přehrání firmware, mazání historie ani změnu rádia.
2. Ukončit jiné BLE klienty pro tentýž companion. Zachovat existující systémové
   spárování; neopakovat ho automaticky. Je-li vyžádán systémový souhlas/PIN,
   potvrdit ho lokálně podle vlastního zařízení; PIN nikam neposílat.
3. Spustit sken, vybrat T-Deck a jednou Připojit vybrané. Poznamenat fázi,
   identifikátor a zobrazené číselné kódy. Po selhání musí zmizet Připojuji…
   a být dostupný nový ruční pokus. Nesnažit se opakovaným klikáním vytvářet frontu.
4. Otevřít **Diagnostika → Export fází BLE (bez identit)…**. Funguje i bez
   jediného úspěšného spojení a bez profilu. Prohlédnout náhled a uložit JSON.
   Obsahuje revizi `windows-ble-enumerate-services-2`, verzi aplikace/OS/architekturu,
   čas, náhodná ID, fáze a číselné výsledky. Neobsahuje názvy/adresy zařízení,
   PINy, klíče, obsah zpráv/paketů, stack trace ani syrové výjimky.
5. V novém exportu zjistit, zda fáze Service nově prošla a kde případně
   pokus selhal dál. Při opakování stejné chyby ani změně fáze netvrdit
   automaticky vyřešení. Uložený export doplnit informací, zda oficiální klient s toutéž beta verzí
   funguje při odděleném pokusu. Jméno uzlu, MAC adresu, PIN a hesla nepřikládat.
6. Pokud se připojení podaří, ověřit místní firmware/baterii a ruční odpojení,
   nový pokus, ztrátu dosahu, uspání/probuzení a případné zrušení tlačítkem Odpojit.
   Měření musí zůstat vypnuté. Připojení ani prohlížení exportu nesmí vyvolat LoRa
   servis. Zvlášť ověřit příjem úplných rámců a skutečné MTU této beta varianty.

## Ověření a meze

Regresní testy běží nad falešným ovladačem a řízenými úlohami, bez Windows BLE API
nebo rádia. Pokrývají prázdnou zprávu/HRESULT, každou nativní fázi, timeouty,
pozdní výsledky i chyby, kódy GATT/protokolu, zrušení, odpojení, souběh, úklid,
nový pokus, protokolovou inicializaci, redakci exportu a nepřítomnost LoRa
požadavků při připojení. Původní testy omezení provozu zůstávají součástí runneru.

Skutečná WinRT komunikace, souhlas/párování, vyjednání MTU a funkční spojení na
Dell/T-Deck Plus čekají na fyzické ověření. Úspěšná cross kompilace WPF a simulované
testy nejsou důkazem, že hlášený problém je opravený na zařízení.

## Primární podklady

- [Microsoft: Bluetooth GATT client a životnost spojení](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-client).
- [Microsoft: úplná enumerace GATT služeb](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothledevice.getgattservicesasync).
- [Microsoft: systémové chyby a ERROR_BAD_COMMAND](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-).
- [Microsoft: BluetoothLEDevice.RequestAccessAsync](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothledevice.requestaccessasync).
- [Microsoft: MaxPduSize](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattsession.maxpdusize)
  a [MaxPduSizeChanged](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattsession.maxpdusizechanged).
- [Microsoft: CCCD WithResult](https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattcharacteristic.writeclientcharacteristicconfigurationdescriptorwithresultasync).
- [MeshCore ESP32 BLE, připnutý commit](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/esp32/SerialBLEInterface.cpp),
  [nRF52 BLE](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/nrf52/SerialBLEInterface.cpp),
  [limit rámce](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h).
- [Wadamesh: transport a nastavení MTU](https://github.com/ALLFATHER-BV/wadamesh/blob/ce0b6380249f742d56f052b5e346a91d2ad55a82/src/helpers/esp32/MultiTransportCompanionInterface.cpp),
  [prostředí pro T-Deck](https://github.com/ALLFATHER-BV/wadamesh/blob/ce0b6380249f742d56f052b5e346a91d2ad55a82/platformio.ini).
- [Wadamesh: připnutý základ BLE, UUID a zabezpečení](https://github.com/ALLFATHER-BV/meshcomod/blob/6a8906212e9071efa4d3699a623b1a5ec8e2de6e/src/helpers/esp32/SerialBLEInterface.cpp).
