# USB připojení · verze 0.10.0

Implementace má dva oddělené protokoly. Zvolte roli před otevřením portu:

| Režim | Spojení | Protokol a oprávnění |
|---|---|---|
| USB companion | Počítač → USB → companion → LoRa → vzdálený uzel | Binární companion protokol; vzdálená správa stále vyžaduje přihlášení |
| USB repeater | Počítač → USB → místní repeater | Textové CLI firmwaru; fyzický sériový přístup poskytuje místní správu bez vzdáleného přihlášení |

BLE zůstává dostupné. Aplikace používá vždy jedno vybrané spojení; změna
transportu ruší relaci správce a zastaví diagnostické měření. Nic sama neflashuje,
nevynucuje restart, nepřepisuje firmware ani konfiguraci a nehledá zařízení
odesíláním příkazů do všech portů. Repeater připojený přes USB není companion.

## První použití

1. Připojte zařízení datovým USB kabelem. Zavřete sériový monitor, flasher nebo
   jinou aplikaci, která port používá. Neotevírejte bootloader/DFU místo aplikace.
2. V **Připojení → Připojení přes USB** zvolte **USB companion** nebo **USB repeater**,
   stiskněte **Obnovit porty**, vyberte port a **Připojit přes USB**.
3. U companionu se načtou místní informace, kanály a fronta zpráv; kontakty lze
   načíst jako u BLE. Repeater přes USB otevřete tlačítkem **Spravovat USB repeater**
   nebo sekcí **Správa repeateru / Konzole**. Po připojení se čtou pouze `ver`,
   `board` a `get name`, bez konfigurace a bez LoRa požadavků.
4. Místní správce může číst jednotlivé hodnoty, potvrdit zápis se zpětným čtením,
   použít konzoli/nápovědu, `stats-core`, `stats-radio`, `stats-packets`, hodiny
   a potvrzovaný restart. USB čas se nastavuje `time <epoch_seconds>`;
   vzdálený `clock sync` zde nemá časovou značku odesílatele.
5. Po timeoutu, vytažení kabelu nebo uspání se připojte znovu výslovně.
   Neověřený zápis neopakujte automaticky: nejprve čtěte stav. Restart nemá
   potvrzující odpověď; samotné odeslání není důkazem provedení.

Parametry: **115200 baud, 8 datových bitů, bez parity, 1 stop bit, bez flow control**.
Port dostane DTR pro USB CDC; aplikace neposílá resetovací/bootloader sekvenci.
Některé desky mohou při otevření/zavření portu restartovat podle svého zapojení.

**Companion musí mít firmware poskytující USB binární protokol.** Samotný USB
konektor nebo BLE companion firmware to nezaručují. Chyba inicializace znamená
neověřenou kompatibilitu, nikoli důkaz vadného kabelu či firmwaru.

Windows vybírá porty COM, macOS `/dev/cu.*`, Linux typicky `/dev/ttyACM*` nebo
`/dev/ttyUSB*`. Linux může vyžadovat členství uživatele ve skupině `dialout`
(podle distribuce); změnu provádí správce systému a projeví se po novém přihlášení.
Aplikaci nespouštějte jako root a nepovolujte port globálním `chmod 666`.
Ovladač USB/UART doplňte jen od výrobce konkrétní desky, je-li potřebný.

## Ověřený zdroj protokolu

Základ: **MeshCore 1.18.0**, commit
`81dbae592ffad40b4212bc0b37e82b38da08f4bc`:

- [ArduinoSerialInterface.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/ArduinoSerialInterface.cpp):
  aplikace → rádio `0x3c` (`<`), 16bitová délka little-endian, pak úplný rámec;
  rádio → aplikace `0x3e` (`>`), stejná délka. Limit payloadu 176 bajtů z
  [BaseSerialInterface.h](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/BaseSerialInterface.h).
- [Repeater main.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/simple_repeater/main.cpp):
  příkaz ukončený CR, echo příkazu, odpověď `  -> ` + text + CRLF, buffer 160 bajtů.
- [MyMesh.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/examples/simple_repeater/MyMesh.cpp):
  podporovaný volitelný prefix dvou znaků a `|`, odražený do odpovědi. Servicer
  používá 3844 různých alfanumerických značek za běh aplikace a znovu je nepoužije
  ani po odpojení. Po jejich vyčerpání vyžádá restart aplikace. Příkaz je omezen
  na 154 UTF-8 bajtů, aby se včetně prefixu a CR bezpečně vešel do bufferu.
- [CommonCLI.cpp](https://github.com/meshcore-dev/MeshCore/blob/81dbae592ffad40b4212bc0b37e82b38da08f4bc/src/helpers/CommonCLI.cpp):
  podporované čtení, nastavení, statistiky, čas a restart. USB nepoužívá vzdálený
  login ani šifrovací formát LoRa zprávy. Hodnota začínající `>` zůstává hodnotou,
  nikoli chybou; `OK` zápisu se navíc ověřuje následným `get`.
- Srovnáno s [meshcore.js serial transportem](https://github.com/liamcottle/meshcore.js/blob/26193c059fcd1d0524f1ad5b19fd88287ecc5c61/src/connection/serial_connection.js)
  a [115200 nastavením portu](https://github.com/liamcottle/meshcore.js/blob/26193c059fcd1d0524f1ad5b19fd88287ecc5c61/src/connection/nodejs_serial_connection.js),
  commit `26193c059fcd1d0524f1ad5b19fd88287ecc5c61`.

Swift používá nativní Darwin termios a Dispatch; Windows/Linux oficiální MIT
knihovnu [System.IO.Ports 10.0.0](https://www.nuget.org/packages/System.IO.Ports/10.0.0).
Transport, stream parser, serializace požadavků a UI jsou oddělené. Rozdělené
příchozí čtení se skládá v parseru; MeshCore rámce se svévolně nefragmentují.
Opožděné dokončení otevření portu se uklidí a nesmí znovu aktivovat ukončenou relaci.

Textové hromadné výpisy bez jednoznačného zakončení (`get acl`, `log`, `region load`),
mazání `erase` a čtení/zápis privátních klíčů nejsou touto konzolí podporované.
Nezaměňujte tuto první přímou USB správu s kompletním vzdáleným pracovním prostorem:
USB zatím nemá místní grafy, snímky, průvodce prvotním nastavením ani formuláře ACL/regionů.

## LoRa, historie a citlivá data

USB čtení informací, konfigurace a statistik nevysílá přes LoRa. Ručně vyžádané
`advert`, `advert.zerohop` a `discover.neighbors` vysílají; UI vyžádá potvrzení
a používá stejný servisní rozpočet jako vzdálená správa. Přímý USB repeater nemá
automatické dotazování. U USB companionu zůstává plán vzdáleného měření **4 h × 3**,
interval 3–24 h, nejvýše 6 vzorků/24 h, bez automatického obnovení či dohánění.
Žádný interval není zárukou bezpečné zátěže. [Provozní limity](TRAFFIC_POLICY.md).

Profily companionů se stále identifikují veřejným klíčem; USB připojení nepřepíše
uloženou BLE adresu. Zprávy a historie zůstávají zachované. Přímý USB repeater
nevytváří falešný kontakt ani účet companionu; konzole má omezený místní výpis
aktuální relace. Hesla a jejich echo se neukládají do historie, exportu ani logu.
Změna hesla přes USB nevyžaduje jeho uložení; hesla vzdálené správy zůstávají
v Keychain / Credential Manager / Secret Service podle dosavadních voleb.

Diagnostický export obsahuje režim transportu a konečný seznam kategorií USB
událostí (čas, fáze/výsledek, na .NET i dostupný HRESULT). Neobsahuje port, cesty,
název zařízení, echo příkazu, odpovědi ani syrové výjimky. Je dostupný i po
neúspěšném otevření. `stats-radio` ukazuje metriky posledního paketu přijatého
repeaterem; noise floor není RSSI a USB spoj žádné RSSI/SNR nemá.

## Fyzické ověření před distribucí

Na macOS, Windows a Linuxu s odpovídající architekturou:

1. USB companion firmware: otevřít správný port, ověřit firmware, identitu,
   baterii, kontakty a zprávy; současně sledovat, že připojení nevysílá LoRa servis.
2. Zkontrolovat návrat k BLE a sdílení profilu podle stejného klíče, zachování
   historie a BLE adresy. Nesprávný režim/firmware musí skončit srozumitelnou
   chybou a uvolněným portem, bez automatického flashování.
3. USB repeater: přečíst `ver`, `get name`, nastavení a statistiky; potvrdit
   neškodnou změnu názvu a ověřit zpětným `get`, potom původní hodnotu obnovit.
   Bez vysílání lze ověřit konzoli, hodiny a odpojení. Advert zkoušet jen
   samostatně na vlastní síti se souhlasem jejího správce.
4. Vytáhnout kabel při čtení/zápisu, obsadit port jiným procesem, zkusit nový pokus,
   uspat počítač a ověřit, že se USB relace ani měření samo neobnoví.
5. Restart potvrdit a ověřit nové připojení; samotný odeslaný příkaz nesmí být
   označen jako potvrzený restart. Rádio testovat až s plánem obnovení spojení.
6. Exportovat diagnostiku i po chybě otevření a zkontrolovat nepřítomnost
   portů, názvů, přihlašovacích údajů a obsahu komunikace.

Automatické testy používají falešné porty, řízený čas a virtuální sériový terminál;
nenahrazují fyzický USB ani BLE/LoRa test. Pro 0.10.0 jsou lokálně připravené
instalátory a podepsané aktualizační feedy; zveřejnění je samostatný krok.

## Distribuované macOS oprávnění

Aplikace zůstává v sandboxu; sériové zařízení otevírá přes POSIX port.
Podepsaná distribuce proto obsahuje `com.apple.security.device.serial`.
Release kontrola vyžaduje toto oprávnění v konfiguraci i skutečném podpisu.
[Apple: sériový přístup v sandboxu](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).
