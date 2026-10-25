# MeshCore Servicer pro Windows 0.7.3

Samostatná nativní desktopová aplikace: **C# / .NET 10 / WPF / Windows Bluetooth GATT**. Bez WebView, webového serveru, Electronu, JavaScriptu a placených závislostí. České rozhraní, světlý, tmavý a systémový vzhled. Nezávislý nástroj; nejde o oficiální aplikaci MeshCore.

Tato složka je kompletní samostatný projekt. Zdrojové soubory, licence,
testy, instalátor a dokumentace jsou uvnitř; sestavení nevyžaduje
soubory z nadřazené složky.

## Instalace pro Windows

Kromě přenosného ZIPu jsou k dispozici české EXE instalátory `MeshCoreServicer-0.7.3-Windows-x64-Setup.exe` a `MeshCoreServicer-0.7.3-Windows-arm64-Setup.exe`. Vyberte nativní architekturu svého PC. Instalace pro aktuální účet obsahuje .NET runtime, zástupce v nabídce Start, volitelnou ikonu na ploše a odinstalaci v Nastavení Windows → Aplikace. Aktualizaci proveďte po ukončení aplikace v oznamovací oblasti opětovným spuštěním stejného nebo novějšího instalátoru. Profily, zprávy a systémová hesla zůstávají zachované i po odinstalaci. Instalátory zatím nemají digitální podpis.

Podrobný postup sestavení a stav ověření: ve zdrojovém projektu `installer/README.md`, v instalované aplikaci `INSTALLER.md`. Kompilace a kontrola vložených souborů proběhly na Macu; samotnou instalaci/aktualizaci/odinstalaci zbývá ověřit ve Windows.

## Načítání prvotního nastavení (0.7.3)

Načítání ukazuje jednotlivé kroky (`ver`, intervaly, dutycycle/af, hashe cesty a owner.info), jejich stav a přesný příkaz při chybě. Odpovědi CLI mají limit `max(45 s, odhad SENT + 15 s)`, nejvýše 180 s. Mezi vzdálenými operacemi a po přijaté odpovědi je minimálně 1,2 s klidu. Odhad companionu nezahrnuje všechny vlivy čekání ve vysílací frontě a omezení airtime repeateru; skutečné rádiové doručení zůstává závislé na síti.

Companion firmware 1.18.0 si pro CLI vytváří vlastní jedinečný čas. Pro starší companiony se navíc nepoužije opakovaná časová značka aplikace. Nejde o synchronizaci hodin ani změnu nastavení zařízení. `unknown config` se správně vyhodnotí jako nepodporovaná položka; fallback z dutycycle na af se použije pouze při přijatém odmítnutí, nikdy po timeoutu. Prázdný kontakt vlastníka lze načíst.

Dokud nedoběhne celé načítání, česká předvolba se nepřipravuje. Částečně načtené hodnoty zůstanou rozlišené od neprovedených a neověřených. Příprava nic nezapisuje do repeateru. Po timeoutu se další požadavky ani zápisy automaticky neopakují; odpojte/připojte BLE, načtěte kontakty a znovu přihlaste správce. Při dalším selhání zkontrolujte konkrétní označený krok v průvodci nebo bezpečném diagnostickém exportu.

Zde prošlo 92 testů a cross kompilace. Konkrétní timeout ze snímku nelze bez záznamu výměny nebo testu na zařízení jednoznačně přiřadit jedinému důvodu. Skutečné fungování úpravy přes BLE/LoRa zbývá ověřit ve Windows.

## Čitelnost a velikost okna (0.7.2)

Základní text má 15 DIP, pomocné popisky nejméně 12 DIP. Horní ikony mají samostatný prostor 42 × 42 DIP a větší kresbu; jejich obsah neomezují původní příliš velké okraje. V Nastavení → Velikost rozhraní lze zvolit 100, 115, 130 nebo 150 %. Volba se ukládá pro celou aplikaci. Funguje také Ctrl+plus / Ctrl+minus a Ctrl+0 pro návrat na výchozí velikost. Zvětšení neobnovuje stránku ani nemaže rozepsané formuláře.

Windows DPI zpracovává WPF v režimu PerMonitorV2; vlastní měřítko aplikace se aplikuje pouze jednou. Rozložení používá dostupnou šířku v DIP: užší okno přepne navigaci na ikony s nápovědou, zalomí karty a přesune akce pod nadpis. Zprávy a kontakty přejdou ze dvou sloupců do dvou řádků. Na nízkém okně je dostupný svislý posuv celé pracovní plochy i jednotlivých seznamů; konzole zachová dostupný vstup. Tabulky mají minimální čitelnou šířku sloupců a vodorovný posuv. Počáteční velikost okna respektuje pracovní plochu obrazovky.

Ověřte ručně zejména 1024 × 768, 1366 × 768 a 1920 × 1080, systémové škálování 100/125/150/200 %, měřítko aplikace 100/150 %, přetažení mezi monitory a změnu velikosti s rozepsanou zprávou nebo konfigurací. Skutečná změna DPI ani Windows vykreslení zde na Macu nebyly otestované. [Dokumentace Microsoftu k DPI](https://learn.microsoft.com/en-gb/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows) a [LayoutTransform](https://learn.microsoft.com/dotnet/desktop/wpf/graphics-multimedia/transforms-overview).

## Vzhled sjednocený s macOS

Verze 0.7.2 přenáší vizuální styl macOS aplikace do nativního WPF: postranní panel šířky 235 bodů se stejným pořadím sekcí a ikonami, značka MeshCore Servicer, štítek companionu v horní liště, vybraný repeater vlevo dole a spodní lišta operací. Shodné jsou tyrkysové zvýraznění, zaoblené karty, rozestupy 20/28 bodů a světlá i tmavá paleta. Písmo a rám okna poskytuje Windows; aplikace neobsahuje Apple fonty ani webové prvky.

Připojení používá úvodní kartu, schéma PC → companion → repeater a profily. Kontakty mají seznam s náhledem uzlu a samostatným inspektorem. Zprávy mají vlevo konverzace, vpravo bubliny a pevně umístěný editor; detail zachycených kopií lze rozbalit. Konzole má tmavý terminál, vkládání rychlých příkazů, našeptávání, nápovědu a spodní vstupní řádek. Správa repeateru používá stejné záložky jako Mac: Přehled, Nastavení, Rádio, Nástroje, Prvotní nastavení, Historie a snímky. Nastavení jsou pojmenované formuláře; rádio má samostatná pole. Neuložené hodnoty zůstávají v modelu i po přepnutí sekce.

Ctrl+1 až Ctrl+6 přepíná pracovní sekce, Ctrl+, otevře nastavení. Rychlé příkazy konzole pouze vloží text; odešle jej až uživatel. Všechna data pocházejí ze stejné aplikační a protokolové vrstvy. Při změně repeateru se vymažou také výsledky nástrojů předchozího uzlu.

## Spuštění

1. Použijte `MeshCoreServicer-Windows-x64.zip` pro běžný Intel/AMD počítač, `MeshCoreServicer-Windows-arm64.zip` pro Windows na ARM. Cílem je Windows 11 s Bluetooth LE adaptérem; projekt používá Windows SDK 10.0.19041. Samotné sestavení nepotvrzuje kompatibilitu konkrétního ovladače nebo staršího Windows.
2. **Rozbalte celý ZIP** do vlastní složky. Spusťte `MeshCoreServicer.exe`. Všechny přiložené DLL a runtime soubory ponechte vedle něj; aplikace obsahuje .NET i WPF runtime, není nutné zvlášť instalovat .NET.
3. Aplikace nepotřebuje administrátorská práva. Balíček není podepsaný komerčním Authenticode certifikátem; Windows jej může označit jako aplikaci neznámého vydavatele. Zdroj je přiložen zvlášť pro vlastní sestavení.
4. V **Připojení** zapněte hledání, vyberte svůj **companion** a připojte jej. Bluetooth spojení v telefonu nejprve uvolněte. Případné systémové párování a PIN potvrďte podle svého zařízení. Tlačítko Nastavení Bluetooth otevře systémové nastavení, tlačítko Systémově spárovat používá Windows pairing API s nativním dialogem pro požadovaný PIN/porovnání.
5. V **Kontakty** ručně načtěte uložené kontakty. Vyberte repeater, otevřete jeho správu a přihlaste správce vlastním heslem. Ping je požadavek na provozní stav po LoRa, discovery je explicitní zero-hop vysílání pro companion protokol v8+.
6. Nejprve načtěte konfiguraci. Hodnoty upravujte v pojmenovaných formulářích na kartách Nastavení a Rádio a klikněte Zkontrolovat a uložit. Před zápisem se zobrazí přesný souhrn; každý krok se ověří čtením. Rádio použije firmware až po restartu a změna může přerušit LoRa spojení.

**Topologie:** Windows → BLE → companion → LoRa → repeater. K repeateru se aplikace přes BLE nepřipojuje. T114/nRF52840 i jiné BLE companiony se rozlišují podle odpovědí protokolu; konkrétní název ani soukromé rádiové parametry nejsou přednastavené.

Připojení načte pouze lokální informace, kanály a čekající frontu zpráv. Samo neposílá advert, discovery, přihlášení ani konfiguraci po LoRa. Neočekávané odpojení může obnovit poslední ověřené BLE spojení; identita profilu se znovu porovná. Správce, monitoring a nejisté zápisy se neobnovují. Ruční odpojení zastaví pokusy. Při uspání se BLE uvolní a monitoring skončí.

Zavření okna ponechá aplikaci v oznamovací oblasti pro příjem zpráv. Dvojklik na ikonu otevře okno; pravé tlačítko → Ukončit aplikaci. Automatické spouštění se nenastavuje.

## Funkce

- BLE skenování Nordic UART služby, připojení, odpojení, opětovné připojení, systémové párování, model, firmware a baterie companionu. Popisky RSSI skenu označují BLE advertisement přijatý PC.
- Kontakty companion/repeater/room server, aktualizace po advertu, explicitní discovery a ukládání uzlů s celým veřejným klíčem. Uložený kontakt a ověřená dostupnost jsou oddělené údaje.
- Správa repeateru: název, poloha, výkon, rádio, zero-hop a flood interval, přeposílání, vlastník, dutycycle/af, délka hashů cesty, flood limity a loop detection. Čtení podpory probíhá skutečnými požadavky. Neznámé nebo odmítnuté operace se nepředstírají.
- Verze a hardware repeateru, hodiny, synchronizace podle PC s kontrolou UTC, telemetrie Cayenne LPP, stránkovaní sousedé, ACL s plným klíčem při změně, hesla správce/hosta, regiony a jejich trvalé uložení, advert a restart s potvrzením.
- Prvotní nastavení ve výchozím stavu zachová současné hodnoty. **Volitelný český profil** připraví flood 25 h, zero-hop 0, dutycycle 10 % (při výslovné nepodpoře fallback af 9), path.hash.mode 1 a vlastní kontakt. Jen návrhy; uživatel vybírá a potvrzuje zápis. Nejde o univerzální parametry pro každou síť. Rádio, hesla a identita se tím nemění. Čas se synchronizuje samostatně a po restartu je potřeba ho znovu ověřit.
- Přímé zprávy jednoznačným uloženým companion kontaktům a kanály načtené ze zařízení. Room server chat není implementovaný; text repeateru by byl CLI, proto se mu chat neposílá. Text se omezuje podle UTF-8 bajtů, u kanálů i podle délky jména.
- Fronta zpráv se automaticky stáhne při připojení a při push události. Během CLI se fronta čte sekvenčně, ostatní zprávy se zachovají. Přijetí companionem, čekání na ACK, potvrzené doručení DM a nejistý výsledek jsou odlišné stavy. Kanál nemá ACK.
- U kanálů počet **skutečně zachycených rádiových kopií s alespoň jedním hopem**, spárovaných s kryptografickým otiskem zprávy. Nejde o počet unikátních repeaterů, dosažených příjemců ani potvrzení doručení. Posledních 64 kopií má vlastní čas, hopy, RSSI a SNR příjmu na companionu. Historické přeposílání z doby, kdy aplikace neposlouchala, nelze zpětně zjistit.
- Systémová upozornění přes Windows notification area (`Shell_NotifyIcon`), volitelný zvuk, skrytý obsah při prvním zapnutí, ztlumení konverzací, otevření konverzace kliknutím a indikátor nepřečtených na hlavním panelu. Nejde o cloud push ani trvalé toast centrum. Windows může oznámení potlačit režimem Nerušit. Prvotní backlog nevyvolává oznámení; **oznámení jsou standardně vypnutá**.
- Konzole: místní katalog, česká nápověda, Tab/dvojklik pro vložení, šipky pro výběr, Esc zavře návrhy, Ctrl+šipky pro historii, Ctrl+Enter nebo volitelně Enter odešle. Zápisy se standardně nenabízejí. Zkratky ukládají pouze název a typ příkazu; hodnoty se doplní až při použití a vložení nic neodesílá. Evidence skutečných odpovědí je vázaná na identitu a firmware; samotný katalog není potvrzení podpory.
- Snímky načtené konfigurace bez hesel a soukromých klíčů, JSON import/export pro stejnou dvojici identit, výběr polí, živé porovnání, kontrola nezměněného stavu před obnovou a zpětné ověření každého zápisu.
- Historie napětí a statistik, graf, ruční monitoring po LoRa (5–1440 minut, výchozí 15, nezačíná hned), přehled nejistých změn a ověření konfigurace bez opakování zápisu. Pokles uptime znamená možný restart; dostupnost sama restart nepotvrzuje. Čtení uloženého rádia nepotvrzuje jeho aktivování.
- Bezpečný diagnostický export s přesným náhledem a ruční checklist hardware. Žádná telemetrie aplikace ani automatické odesílání dat.

Změna identity a přímá manipulace s privátními klíči nejsou ve formulářích. Mapa a jiné síťové transporty nejsou součástí této verze.

## Data a hesla

Při prvním spuštění nejsou přibalené profily, zprávy, majitel, souřadnice, kanály ani hesla. Nastavení a historie vzniknou až používáním v `%LOCALAPPDATA%\MeshCoreServicer`. Historie zpráv je lokální nešifrovaný JSON pod účtem Windows; přístup a zálohování řídí uživatel/OS. Klíče kanálů se neukládají do historie; veřejné identity a otisky slouží k oddělení účtů. Konzole je pouze v paměti, citlivé příkazy a odpovědi jsou skryté.

Hesla správce se ukládají pouze na výslovnou volbu do **Správce přihlašovacích údajů Windows**, typ Generic, cíl `MeshCoreServicer/Admin/<veřejný klíč repeateru>`, pod aktuálním účtem. Neukládají se do JSON, logu ani distribučních ZIPů. Správa hesel macOS Keychain se nepřenáší. Změna hesla správce se potvrzuje konkrétní odpovědí firmware a zruší relaci správce; nové přihlášení je samostatné ověření. Při timeoutu už může být heslo změněné.

Profily mají samostatné volby konzole, obnovení BLE a monitoringu; vzhled/oznámení jsou společné. Zprávy a historie správy jsou oddělené veřejnou identitou companionu. Přepnutí vymaže paměťovou konzoli a její rozepsaný vstup. Poškozené soubory se automaticky nepřepíší. Smazání profilu nemaže archiv zpráv nebo systémová hesla. Diagnostický export neobsahuje identity, názvy, BLE adresy, polohu, rádio, původní výjimky, obsah zpráv nebo CLI; vždy nejprve zkontrolujte jeho přesný náhled.

## Licence

[MIT](LICENSE). Licence přibalených runtime komponent jsou zachované
v [ThirdParty](ThirdParty/README.md).

## Vývoj a sestavení

Otevřete `MeshCoreServicer.slnx` v aktuálním Visual Studiu s podporou .NET 10 a workloadem Desktop development with .NET, jako spouštěcí projekt nastavte `MeshCore.Windows`. Nebo z této složky použijte bezplatné .NET 10 SDK:

```powershell
dotnet run --project tests/MeshCore.Tests -c Release
dotnet build MeshCoreServicer.slnx -c Release
.\build.ps1 -Runtime win-x64
.\build.ps1 -Runtime win-arm64
```

`build.ps1` nejprve spustí testy, publikuje vlastní runtime a vytvoří ZIP v `out`. Testovací runner nepotřebuje xUnit ani jiné NuGet knihovny; při selhání vrací nenulový exit code. Projekt obsahuje jen oficiální framework/Windows SDK reference. Balíčky lze vytvořit i cross kompilací; **WPF a Windows BLE nelze tímto způsobem spustit na macOS**. Native AOT ani trimming se nepoužívá kvůli WPF a WinRT.

Architektura:

| Vrstva | Soubory |
|---|---|
| Windows BLE transport | `src/MeshCore.Windows/BleTransport.cs` |
| MeshCore protokol a korelace | `src/MeshCore.Core/Protocol.cs`, `Session.cs` |
| Aplikační logika | `Controller*.cs`, `Commands.cs`, `Storage.cs` |
| Systémová hesla | `CredentialStore.cs` |
| WPF UI a systémová oznámení | `MainWindow*.cs`, `NativeUI.cs`, `Tray.cs` |
| Testy bez fyzického vysílání | `tests/MeshCore.Tests/Program.cs` |

BLE zapisuje s odpovědí a vyžaduje MTU pro celý rámec; nesmí používat sériové obálky ani dělit zprávy. Odpovědi bez spolehlivého request ID se zpracovávají vždy jednou sekvenční relací. Timeout nebo nejasná chyba zápisu relaci zablokuje do obnovení BLE; zápisy se nikdy neopakují automaticky.

Podrobnosti protokolu a přesné zdrojové revize: [PROTOCOL.md](PROTOCOL.md). Stav skutečného ověření a postup pro zařízení: [COMPATIBILITY.md](COMPATIBILITY.md).

## Kontrola skutečného WPF rozhraní ve Windows

Téma je kompilované do BAML, takže sestavení kontroluje XAML typy a šablony. Na vývojovém Macu proběhla kompilace a 92 testů jádra; **běh WPF a vizuální kontrola ve Windows nebyly provedené**.

Pro kontrolu přímo ve Windows spusťte z projektu `./verify-ui.ps1`, případně `./build.ps1 -Runtime win-x64 -VerifyUI`. V rozbaleném binárním balíčku lze spustit přiložený `verify-ui.ps1` s výchozím EXE vedle skriptu. Skript otevře izolované nativní okno, aplikuje šablony sedmi sekcí v obou vzhledech při pěti kombinacích velikosti a měřítka (760×540/100 %, 1024×720/115 %, 1440×960/100 %, 1920×1080/130 %, 900×650/150 %) a uloží 70 PNG a `result.json` do `out/ui-verification`. Obrázky zobrazují **prázdné skutečné WPF rozhraní** s označením kontroly, bez ukázkových údajů. Režim nenačítá osobní profily, nepřipojuje BLE, nespouští monitoring ani nepíše konfiguraci. Slouží ke kontrole rozhraní; nenahrazuje fyzický test zařízení ani ruční kontrolu čitelnosti a ovládání při různém DPI.

Kontrola navíc ověřuje skutečný prostor ikon v šablonách tlačítek, zalamování nadpisů a hranice karet. Mění velikost a vlastní měřítko skutečného WPF okna; skutečné DPI monitoru nenahrazuje. Testy jádra obsahují migraci starého nastavení velikosti, validaci a trvalé uložení i pravidla čitelného rozložení.

## Zdrojový balíček

`python3 scripts/package_source.py` vytvoří samostatnou zdrojovou složku,
ZIP a SHA-256 v `dist/source`. Nečte data aplikace a nezahrnuje instalátory,
cache ani podpisové klíče. Pro další balíček použijte jiné `--output`.
