# MeshCore Servicer 0.10.0 · Linux

Nativní Avalonia 12.1.4 desktop, BlueZ přes Tmds.DBus.Protocol 0.95.1 a společné
jádro MeshCore. Avalonia používá vlastní desktopový backend X11/XWayland;
nejde o GTK aplikaci ani WebView. Balíčky pro **x86-64 (amd64)** a **AArch64 (arm64)**.
Cílové distribuce: Ubuntu 22.04/24.04/26.04 a Debian 12/13 s grafickou relací, BlueZ 5.64+,
systemd-logind a systémovou klíčenkou Secret Service.

## Instalace a první připojení

```sh
sudo apt install ./meshcore-servicer_0.9.1-1_amd64.deb
meshcore-servicer
```

Na ARM64 použijte `meshcore-servicer_0.9.1-1_arm64.deb` místo `amd64`.
Architekturu systému zjistíte příkazem `dpkg --print-architecture`. ARM64
vyžaduje 64bitový Linux s grafickým prostředím; balíček není pro 32bitové armhf.

APT doplní knihovny X11, fonty, BlueZ a `secret-tool`. Pokud desktop
neposkytuje Secret Service, doinstalujte například GNOME Keyring a odemkněte
přihlašovací klíčenku. Aplikaci nespouštějte jako root. Instalace nemění
firmware, BLE oprávnění systému ani konfiguraci sítě.

Revize balíčku **0.9.0-1** opravuje chybějící adresáře v původním archivu
0.9.0, které při nové instalaci způsobovaly chybu `dpkg-new: No such file or
directory`. Adresáře nyní předcházejí souborům a mají práva 0755/root:root.
Verze aplikace zůstává 0.9.0; oprava balení nemění její podepsané soubory,
historii ani profily. Původní DEB nahraďte opraveným balíčkem pomocí APT.

V Připojení spusťte skenování, vyberte vlastní companion a podle potřeby použijte
**Systémově spárovat**. PIN zadejte pouze v místním dialogu párování. Telefon
nebo jiný klient uvolní BLE spojení před připojením. Seznam zahrnuje kompatibilní
objekty známé BlueZ; dostupnost ověří až skutečné připojení.

Při neočekávaném výpadku lze povolit jeden pokus o obnovu BLE. Ověřuje původní
identitu; neobnovuje správce ani měření. Po neúspěchu pokračujte ručně. Uspání,
ruční odpojení a restart nepokračují v původním spojení. Pokud není dostupné
hlášení uspání od logind, plánované měření je zakázané; ruční správa zůstává.

Kontakty, kanály a fronta zpráv se čtou místně přes BLE. Přihlášení, ping,
discovery a vzdálené příkazy používají LoRa přes companion. Měření je výslovně
spouštěné, výchozí 4 h × 3, nejvýše 6 vzorků/24 h. Historie neodesílá žádosti.

## Systémové závislosti a ICU

Aplikace přibaluje .NET runtime 10.0.12. Verze 0.9.1 doplňuje ICU 78 do
alternativ závislosti DEB a certifikáty CA, tzdata, GSSAPI/Kerberos a Brotli.
APT vybírá knihovny z repozitáře dané distribuce. Není potřeba instalovat
starou ICU z jiné distribuce, vypínat kontroly závislostí ani přepínat na
invariantní kulturu; české řazení, diakritika a formátování zůstávají funkční.

| Distribuce | Systémová ICU | OpenSSL |
|---|---|---|
| Ubuntu 22.04 | libicu70 | libssl3 |
| Ubuntu 24.04 | libicu74 | libssl3t64 |
| Ubuntu 26.04 | libicu78 | libssl3t64 |
| Debian 12 | libicu72 | libssl3 |
| Debian 13 | libicu76 | libssl3t64 |

`python3 -m unittest discover -s Linux/packaging -p 'test_*.py'` na Debianu/Ubuntu
ověří závislosti parserem dpkg proti dočasným databázím balíčků, bez změn systému.
Na macOS se tři testy vyžadující dpkg přeskočí.
Samostatný běhový test bez aplikace, BLE a sítě:

```sh
dotnet run --project Linux/tests/MeshCore.Globalization.Tests -c Release
# Publikovaný Linux test může vynutit kontrolu načtené verze:
./MeshCore.Globalization.Tests --require-icu-major 78
```

Test čte názvy načtených ICU knihoven z `/proc/self/maps` a ověřuje česká
čísla, měsíce, změnu velikosti písmen, Unicode normalizaci a řazení „ch“.
Použijte stejnou verzi runtime jako distribuovaná aplikace; při publikaci lze
zadat `-p:RuntimeFrameworkVersion=10.0.12`. Úspěšný test kultur nenahrazuje
ověření instalace, desktopu nebo Bluetooth.

## Úložiště a aktualizace

Profily, zprávy a historie: `$XDG_DATA_HOME/MeshCoreServicer`, obvykle
`~/.local/share/MeshCoreServicer`. Hesla jsou v Secret Service; žádná
nešifrovaná náhrada v souboru se nevytváří. Zavření hlavního okna aplikaci
ukončí; oznámení se zobrazují za jejího běhu.

Balíček APT instaluje podepsanou základní verzi do `/usr/lib/meshcore-servicer`.
Potvrzené aktualizace aplikace ukládají ověřené verze do místního adresáře
`MeshCoreServicer/Install`; nepotřebují sudo. Launcher vybere novější ověřenou
verzi z balíčku nebo uživatelského úložiště. Číslo balíčku v databázi dpkg se
aktualizací aplikace nemění. Odinstalace APT zachovává osobní data i uživatelské
verze; jejich odstranění je samostatné vědomé rozhodnutí uživatele.
[Aktualizační mechanismus](../docs/UPDATES.md).

## Sestavení

Z kořene kompletního repozitáře:

```sh
dotnet run --project Linux/tests/MeshCore.Linux.Tests -c Release
dotnet publish Linux/src/MeshCore.Linux -c Release -r linux-x64 --self-contained true -o build/linux-app
dotnet publish Shared/MeshCore.Launcher -c Release -r linux-x64 --self-contained true -o build/linux-launcher
```

Pro ARM64 nahraďte v obou příkazech `linux-x64` za `linux-arm64` a použijte
samostatné výstupní složky. Aplikace i launcher musí mít shodnou architekturu.
Balicí nástroj odvozuje Debian `Architecture` z platformy podepsané distribuce
a odmítá odlišnou architekturu apphostu nebo nativní knihovny.

Běžné vývojové sestavení je spustitelné bez podpisového klíče. Distribuci s
aktualizacemi sestavuje `tools/package_release.py`; vyžaduje privátní podpisový
klíč odpovídající veřejnému klíči daného vydavatele. Klíč nepatří do repozitáře.
Následně `Linux/packaging/build_deb.py --publication SLOZKA --output SOUBOR.deb`.
Debian verze 0.9.1 má příponu revize `-1`; pojmenujte výstup například
`meshcore-servicer_0.9.1-1_amd64.deb`. Testy balení ověřují také postupné
rozbalení do prázdného kořene bez implicitního vytváření rodičovských adresářů.
Celý repozitář je nutný: Linux odkazuje na sdílené jádro v `Shared/MeshCore.Core`
a na `Shared/`; samotné kopírování `Linux/src` nestačí.

## Ověření 0.9.1

Verze 0.9.1-1 byla přes APT aktualizována z 0.9.0-1 v Ubuntu 26.04.1 LTS
ARM64 VM; `dpkg-query` hlásí `install ok installed` a `apt-get check` prošel.
Samostatná simulace APT s dočasnou databází bez starší ICU reprodukovala
odmítnutí 0.9.0-1 a přijetí 0.9.1-1 pouze s ICU 78. Skutečný běh .NET 10.0.12
v izolovaném prostředí s nepřístupnou ICU 70 prošel devíti kontrolami české
kultury a načetl výhradně ICU 78.2. Bez jakékoli ICU kontrolní běh správně selhal.
Samotná aplikace 0.9.1 otevřela hlavní okno v témže prostředí s ICU 78;
profily byly oddělené a síť izolovaná. Všech 15 testů balení prošlo na Ubuntu,
včetně matic závislostí pro obě architektury a pět cílových distribucí.

Toto není čistá instalace na všech cílových distribucích. Nativní běh x64,
BlueZ, párování, klíčenka a fyzické BLE/LoRa spojení čekají na ověření.

## Fyzické ověření

1. Na každé architektuře (x64 i ARM64) na čisté podporované distribuci instalovat `.deb`, ověřit menu a spuštění
   bez sudo, oba motivy, menší okno a druhou instanci.
2. S vypnutým Bluetooth ověřit čitelnou chybu. Zapnout adaptér, skenovat,
   spárovat a připojit companion; zaznamenat přesné firmware, BlueZ a adaptér.
3. Ověřit firmware, baterii, kontakty a kanály. Připojení nesmí vyvolat LoRa
   diagnostiku ani zápis konfigurace. Ověřit odpojení, nový pokus a obsazený spoj.
4. Na vlastním repeateru ručně přihlásit správce a načíst stav. Ověřit původ
   RSSI/SNR. Změny provádět jednotlivě se zpětným čtením; neprovádět testy na
   cizím uzlu. Rádio měnit až s plánem obnovení spojení.
5. Ověřit uložení a načtení hesla z odemčené klíčenky, zprávy a oznámení.
6. Spustit omezené měření, ověřit čekání před prvním termínem a jeho zastavení
   uspáním/odpojením; po probuzení ani restartu se nesmí obnovit.
7. Exportovat Diagnostika → fáze BLE i po selhání připojení. Export neobsahuje
   adresy, názvy, PINy, hesla, klíče, obsah paketů ani syrové výjimky.
8. S připraveným podepsaným testovacím vydáním ověřit odmítnutí/odsouhlasení
   aktualizace, pouze změněné HTTP objekty, restart a zachování historie.

Revize 0.9.0-1 byla nainstalována pomocí dpkg a aplikace otevřela hlavní okno
pod běžným účtem v Ubuntu 26.04.1 LTS ARM64 ve VirtualBoxu. Po původním
neúspěšném pokusu byla dokončena čekající konfigurace `libsecret-tools`.
Obě architektury prošly skutečným `dpkg --unpack` do prázdných oddělených
kořenů; u x64 byla na ARM64 vynucena architektura pouze pro kontrolu rozbalení.
To **neověřuje běh x64**, čistou instalaci APT na všech cílových distribucích,
BlueZ, párování, klíčenku, aktualizace ani fyzické BLE/LoRa. Automatické testy
a cross kompilace tato ověření také nenahrazují.

## Reference

- [BlueZ GATT API 5.64](https://github.com/bluez/bluez/blob/5.64/doc/gatt-api.txt):
  přesná NUS služba/charakteristiky, StartNotify, WriteValue typu request a MTU.
  Každý úplný MeshCore rámec je jeden zápis, bez svévolného dělení; ATT MTU ≥179.
- [Avalonia Linux](https://docs.avaloniaui.net/docs/platform-specific-guides/linux).
- [Tmds.DBus](https://tmds.github.io/Tmds.DBus/).
- [MeshCore protokol](../Windows/PROTOCOL.md), pinned MeshCore 1.18.0,
  commit `81dbae592ffad40b4212bc0b37e82b38da08f4bc`.

- [.NET 10 závislosti Ubuntu/Debian](https://github.com/dotnet/core/blob/main/release-notes/10.0/dotnet-dependencies.md).
- [Načítání ICU v .NET](https://learn.microsoft.com/dotnet/core/extensions/globalization-icu).

## USB od 0.10.0

USB companion i přímý USB repeater: [připojení, protokol a ověření](../docs/USB.md).
Port se otevírá jen výslovně; BLE i USB současně se nepoužívají.
