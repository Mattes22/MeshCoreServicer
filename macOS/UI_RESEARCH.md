# Úprava rozhraní 0.2

Průzkum 23. 10. 2026. Prohlédnuté primární materiály:

- [MeshCore Open – Repeater Management](https://github.com/zjs81/meshcore-open/blob/dev/documentation/repeater-management.md): centrum správy, členění stavu, skupiny nastavení, načítání hodnot na vyžádání a CLI. Vizuálně prohlédnutý [screenshot kontaktů](https://raw.githubusercontent.com/zjs81/meshcore-open/dev/docs/screenshots/contacts.jpg).
- [Mesh-Client – README a screenshoty](https://github.com/Colorado-Mesh/mesh-client#visuals): desktopová navigace, filtry, seznam repeaterů a diagnostika. Vizuálně prohlédnuté obrazovky [repeatery](https://raw.githubusercontent.com/Colorado-Mesh/mesh-client/main/docs/images/repeaters.png) a [připojení](https://raw.githubusercontent.com/Colorado-Mesh/mesh-client/main/docs/images/connection.png).
- [mc-webui – My Repeaters](https://github.com/MarekWo/mc-webui/blob/main/docs/user-guide.md): samostatný výběr uzlu před správou a vyhledávání repeateru.

| Potřeba | Co jsme implementovali |
|---|---|
| Najít uzel v delším seznamu | Hledání s diakritikou i bez ní, veřejný klíč, typové filtry, počty a boční detail |
| Zorientovat se ve správě | Trvalá identita cíle, oddíly Přehled / Nastavení / Rádio, oddělení přihlášení od ověření dostupnosti |
| Rychle zhodnotit stav | Napětí, uptime, pakety; rádiové metriky a provoz oddělené do panelů |
| Nastavovat rádio bez zápisu CSV | Čtyři samostatná pole; frekvence s jednotkou, výběry BW, SF a CR |
| Vidět rozdíl mezi návrhem a skutečností | Načtená hodnota pod editorem, indikace neuložené změny, průběh odeslání a zpětného čtení |
| Uložit více hodnot | Před odesláním konkrétní souhrn, následné sekvenční provedení, zastavení na první chybě a zachování zbylých úprav |
| Pracovat s CLI na klávesnici | Rychlé vložení příkazů, Enter, ↑/↓ s návratem k rozepsanému vstupu, hledání a kontext vybraného repeateru |
| Dohledat problém | Časovaný log, úrovně, hledání a export; chyby přímo v okně |

Návrh je implementovaný vlastními SwiftUI komponentami a systémovými SF Symbols. Cizí zdrojový kód, obrázky ani značky nejsou vložené do aplikace. SwiftUI používá nativní ovládací prvky a přizpůsobuje barvy světlému a tmavému režimu.

## Zachované vlastnosti komunikace

- Otevření stránky ani výběr rychlého příkazu nic nevysílá. Rychlý příkaz pouze vyplní vstupní řádek.
- Neprobíhají automatické opakované zápisy, synchronizace hodin ani automatické načtení vzdálených hodnot při výběru uzlu.
- Dostupnost uvádí čas skutečné odpovědi. Uložená cesta je označená jako uložená a negarantuje aktuální doručitelnost.
- Baterie je napětí ve voltech; procenta bez znalosti chemie baterie se neodhadují.
- Šum a poslední RSSI/SNR z repeateru mají vlastní popisky a původ měření.

## Kontrola

Verze 0.3 přidává samostatné Zprávy s přehledem konverzací a editorem, nepřečtenými počty a odlišením kanálů od soukromých kontaktů. Přijetí companionem, ACK protějšku a zachycené přeposlané kopie mají samostatné popisky. Čítač zachycených kopií se nezaměňuje s počtem hopů v cestě.

Ve verzi 0.3 `swift test` ověřoval 34 testů knihovny a 17 testů aplikačního modelu. Testy pokrývají zpětné ověření změny, zachování návrhu při rozdílu, souhrn před hromadným uložením, zastavení po chybě, potvrzení rádia bez automatického restartu a ochranu neuložených úprav. Nové testy zpráv kontrolují rámce, přesné párování rádiových kopií, ACK, deduplikaci, lokální historii a oddělení chatu od CLI.

`scripts/render-previews.sh` sestaví samostatný nástroj a vykreslí skutečné SwiftUI obrazovky do PNG. Obsahuje výslovně označené fixture hodnoty, nevytváří Bluetooth manager a nevolá protokolové operace. Nástroj je mimo aplikační target. Offscreen vykreslení ověřuje rozložení; nativní titulková lišta a interakce s fyzickým zařízením vyžadují skutečný běh aplikace.


## Rozšíření 0.4 podle oficiální aplikace

Podkladem je nabídka administrace repeateru v oficiální mobilní aplikaci (stav 24. 10. 2026). Jejich informační struktura byla převedena do nativních macOS skupin:

| Nástroj ze snímku | Umístění / chování v aplikaci |
|---|---|
| Owner info, poloha, intervaly, přeposílání | Nastavení; poloha se zadává souřadnicemi, mapa není implementovaná |
| Sync clock, verze, sousedé, telemetrie | Nástroje → Diagnostika; čtení a aktivní akce mají samostatná tlačítka |
| Network settings a regiony | Nástroje → Síť a regiony; souhrn před zápisem a trvalé uložení regionů |
| Řízení přístupu a hesla | Nástroje → Přístup; celé klíče pro zápis, omezení prefixového seznamu ACL viditelně v UI, hesla v SecureField |
| Advert a restart | Přehled i Nástroje; ruční vysílání a potvrzovaný restart |
| Změna identity | Výslovně označeno jako neimplementované; průvodce ani formuláře nepracují se soukromým klíčem |
| Český komunitní postup | Samostatné Prvotní nastavení: načíst → porovnat a vybrat → zkontrolovat souhrn → provést se zpětným čtením |

Připravený návrh není označen jako potvrzená změna. Komunitní profil se volí výslovně a hodnoty nepřepisuje po připojení. Při chybě zachová výsledek už dokončených kroků a zastaví další zápisy.

Aktuální ověření: 45 testů knihovny a 35 testů aplikační logiky (80 celkem), úspěšné Xcode Release sestavení a samostatné offscreen SwiftUI náhledy. Komunikace s fyzickým zařízením ani interaktivní obsluha okna nebyly ověřené.

## Rozšíření 0.5

Šest schválených návrhů je implementovaných: systémová oznámení a preference soukromí, obnova BLE, konfigurační snímky, historie zdraví, detail rádiových kopií a kontrola po restartu. Historie a snímky mají vlastní hlavní záložku ve správě, aby nevznikaly tři vnořené úrovně přepínačů. Záložka se dá použít i k prohlížení načtené lokální historie po odpojení.

Nastavení oznámení je skutečné macOS Settings okno s volitelným povolením systému; náhledy a testy nepoužívají UNUserNotificationCenter ani Dock. Čtenost konverzace závisí také na aktivní a viditelné hlavní aplikaci. Ztišení zachová příjem a nepřečtené počty.

Grafy používají systémové Swift Charts. Každý vzorek má čas a zdroj; monitoring má výraznou informaci o aktivním LoRa provozu a je vypnutý. Snímky zobrazují jednotlivá pole i jejich původní časy čtení; porovnání a obnova jsou dvě samostatné uživatelské akce. Rádio není předem zvolené pro obnovu.

Ověřeno 100 automatických testů (50 knihovna, 50 aplikační logika), nativní Release sestavení a označené offscreen náhledy ve světlém a tmavém režimu. Skutečné systémové bannery, zvuk, akce oznámení a uspání/probuzení nebyly interaktivně ověřené. Reálný BLE/LoRa test je popsán v HARDWARE_CHECKLIST.md a dosud nebyl proveden.


## Univerzální distribuce a konzole (0.6)

Rozhraní načítá názvy a modely z připojeného zařízení, bez osobní identity nebo předvoleného rádia. Výchozí průvodce zachovává současné hodnoty; česká komunita je volitelná předvolba. V běžném provozu nejsou ukázkové kontakty ani zprávy.

Konzole má místní katalog s českým hledáním a přehledem syntaxe, přepínatelným našeptáváním a historií. Výběr Tabem nebo kliknutím pouze upravuje vstup; odesílání zůstává samostatné. Změnové příkazy jsou označené a nabídka je ve výchozím stavu omezená na čtení. Nápověda má vlastní omezený prostor a posuvník, aby zůstaly viditelné skutečné odpovědi i vstup. Nativní Nastavení odděluje obecné volby a konzoli.


## Provozní spolehlivost a více zařízení (0.7)

Připojení obsahuje místní profily companionů s viditelnou veřejnou identitou, posledním použitím, přejmenováním a výslovným přepnutím. Bezpečnostní volby oznámení zůstávají společné, provozní volby konzole a obnovování jsou samostatné pro každý companion.

Hvězda v konzoli otevře oblíbené příkazy a pojmenované šablony. Vlastní argumenty se doplňují až při použití a neukládají se. Nápověda odděluje referenční katalog od skutečně přijaté odpovědi na daném uzlu a firmwaru.

Neověřené změny nabízejí konkrétní čtecí kontrolu, nikoliv další zápis. Diagnostika odděluje náhled bezpečného reportu a uživatelský checklist kompatibility. Oba obsahují jasný původ informací; fyzické testy začínají stavem Neprovedeno. Všechny nové obrazovky používají SwiftUI a systémové prvky, bez WebView.
