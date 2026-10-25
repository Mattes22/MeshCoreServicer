# Kompatibilita a ověření vydání 0.7

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
