# Ověření 0.9.0 · macOS

26. 10. 2026: 158 Swift testů prošlo (83 jádro, 75 aplikační logika).
Univerzální Xcode Release arm64/x86_64 prošel. Distribuce přidává Sparkle
2.10.1, povinný podpis feedu a ověření archivu před rozbalením. Dva testy
skutečného nástroje BinaryDelta ověřují rekonstrukci a odmítnutí nesprávného
základu. Podepisování a notarizace se evidují ve validačním JSON vydání.
Fyzické BLE/LoRa, první spuštění na čistém jiném Macu a uživatelský přechod
mezi dvěma vydanými verzemi 0.9.x nebyly v tomto ověření provedené.

Následující záznamy popisují předchozí verze.

# Ověření zdrojové verze 0.8.2 pro macOS

Ověřeno 25. 10. 2026: **158 Swift testů prošlo** (83 jádro/politika, 75
aplikační logika). Univerzální Xcode Release pro arm64 a x86_64 prošel bez
podpisu vydání. Testování proběhlo na macOS; žádné skutečné zařízení se nepoužilo.

Verze 0.8.2, sestavení 10. Diagnostika používá výchozí plán 4 h × 3,
interval 3–24 h a nejvýše 6 vzorků během 24 h. Testy používají řízený čas
a falešný transport; nečekají skutečné hodiny. Měření zůstává ruční a jeho
stav se neukládá. Migrace platí i pro neaktivní profily.
Nový podepsaný archiv, notarizace ani instalační balíček 0.8.2 nevznikly.
Fyzické BLE/LoRa, airtime a dlouhodobý běh s uspáním nebyly ověřené.

## Dřívější ověření verze 0.8.1

Zdrojová verze 0.8.1 (sestavení 9): 151 automatických Swift testů prošlo;
Xcode Release sestavení pro arm64 i x86_64 prošlo. Distribuční DMG 0.8.1 má
Developer ID podpis, Hardened Runtime, sandbox a notarizaci Apple pro aplikaci
i obraz. Oba tickety jsou připojené; Gatekeeper a kontrola skutečně vložené
aplikace pomocí syspolicy_check distribution prošly. Stažení a první spuštění
na jiném čistém Macu nebyly vyzkoušené.

Žádná kombinace fyzického companionu a repeateru zatím nebyla v tomto projektu doloženě otestována. Úspěšné automatické testy, sestavení a renderované náhledy nejsou důkazem funkčního BLE/LoRa spojení.

| Oblast | Způsob ověření | Stav |
| --- | --- | --- |
| Binární protokol, rámcování, parser, sekvenční relace | Automatické testy s náhradním transportem | Ověřeno automaticky |
| Profily, šablony, evidence odpovědí, kontrolní čtení a anonymní report | Automatické testy | Ověřeno automaticky |
| macOS aplikace pro arm64 a x86_64 | Xcode Release Universal Binary, kontrola podpisu | Sestavení ověřeno; běh na Intel Macu neověřen |
| Rozložení SwiftUI ve světlém a tmavém režimu | Oddělený offscreen renderer, výslovně označené syntetické hodnoty | Vizuální kontrola; nenahrazuje interakci v okně |
| BLE, systémové párování, reconnect a výpadky | Skutečný companion a macOS | Neprovedeno |
| Zprávy, LoRa ACK, přihlášení a konfigurace repeateru | Companion připojený přes BLE; repeater dostupný po LoRa | Neprovedeno |
| Restart, aplikování rádia, čas a probuzení | Fyzické zařízení | Neprovedeno |
| Systémová oznámení, Keychain a klávesové ovládání | Interaktivní macOS test | Neprovedeno |

Protokolovým základem je MeshCore `81dbae592ffad40b4212bc0b37e82b38da08f4bc`, referenční verze 1.18.0. Názvy a možnosti konkrétní desky se načítají ze zařízení; dostupnost operací nelze z katalogu předpokládat.

## Jak zaznamenat reálné ověření

1. Postupujte podle [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md), nejprve čtení a potom pouze výslovně zvolené změny na vlastním uzlu. Nastavení si před změnou uložte do snímku.
2. V aplikaci načtěte firmware companionu a vybraného repeateru. V **Diagnostika → Kompatibilita** se zachytí konkrétní dvojice identit, plné načtené verze firmwaru, aplikace, macOS a architektura procesu.
3. U každého skutečně provedeného kroku ručně zvolte **Prošlo** nebo **Selhalo**. Výchozí stav je **Neprovedeno**. Uloží se datum uživatelského záznamu. Nejde o nezávislé nebo automatické potvrzení aplikací.
4. Záznam můžete doplnit i po přerušení spojení, pokud je otevřený pro původně zachycenou kombinaci. Po změně firmwaru, aplikace, macOS nebo architektury se starší záznam nepovažuje za nové ověření. Výsledky jiného uzlu se nepřebírají.
5. Vytvořte **Report s náhledem**. Obsahuje aktuálně odpovídající uživatelské výsledky a verze, bez identit a původního textu logu. Dokud nejsou verze znovu načtené, report testy s neznámou kombinací nespojuje. Report se jen uloží; nikam se automaticky neposílá.

Není-li zkouška provedená nebo je výsledek nejistý, ponechte **Neprovedeno**. Přijetí požadavku companionem není potvrzení doručení, změny nebo restartu repeateru.

Konečné měření a společné servisní limity jsou zdrojová úprava; fyzické ověření podle [checklistu](HARDWARE_CHECKLIST.md) a [politiky provozu](docs/TRAFFIC_POLICY.md) zbývá provést.
