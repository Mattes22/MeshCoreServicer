# Aktualizace od 0.9.0

Kontrola stahuje pouze metadata z `https://servicer.zavadilmatej.cz/updates/`.
Je zapnutá ve výchozím nastavení, lze ji vypnout. Proběhne při spuštění a za
běhu přibližně po 24 hodinách; ruční kontrola je v Nastavení. Neodesílají se
jména, adresy zařízení, profily, zprávy ani diagnostika; webový server vidí
běžné údaje HTTP spojení včetně IP klienta.

Stažení programu a instalace vyžadují potvrzení uživatele. Aktualizace není
spuštěna během servisní operace. Měření se zastaví, USB i BLE se uvolní a zapíší se
místní data. Po restartu se přihlášení správce a měření neobnovují. Aktualizace
nemění firmware ani konfiguraci companionu či repeateru.

## Windows a Linux

`stable/windows-x64.json`, `stable/windows-arm64.json`, `stable/linux-x64.json`
a `stable/linux-arm64.json`
obsahují obálku s Base64 JSON payloadem a podpisem ECDSA P-256/SHA-256
(IEEE P1363, 64 bajtů). Veřejný klíč je připnutý v aplikaci i launcheru.
HTTPS je povinné, přesměrování jsou odmítnutá. Kontroluje se platforma,
verze, platnost manifestu, cesty, duplicity, vstupní bod a velikostní limity.

Po potvrzení se stáhnou pouze objekty se změněným SHA-256/velikostí z
`objects/<sha256>`. Shodné soubory se ověří a zkopírují místně. Při poškození
souboru, neplatném podpisu nebo síťové chybě se nová verze neaktivuje. Každé
stažení má tříminutový časový limit. Žádný automatický retry.

Každá verze má vlastní úplný adresář `versions/<verze>` a podepsaný manifest.
Ověřené adresáře se nepřepisují za běhu. Oddělený launcher ověří původní proces,
počká na jeho ukončení, přepne `current.json` atomickým přejmenováním a spustí
novou aplikaci. `previous.json` a předchozí soubory zůstávají dostupné. Pokud
nový proces skončí před potvrzením startu, vrátí se předchozí ověřená verze a
znovu se spustí. Běžící proces bez potvrzení po 30 s se násilně neukončuje;
chyba se zaznamená pro ruční prověření. Potvrzení startu dokládá inicializaci
aplikace, nikoli bezchybnost všech jejích funkcí.

Profily/archivy a hesla leží mimo instalační adresáře. Zůstanou zachované i
při neúspěchu. Návrat staré aplikace však obecně nemusí být kompatibilní s
budoucí migrací dat; nové formáty musí zachovat kompatibilitu nebo mít vlastní
zálohovanou migraci. Verze 0.9.0 formát historie nemění. Předchozí verze i
neúspěšné pracovní adresáře se pro diagnostiku ponechávají a zabírají místo.

Launcher a jeho bootstrap runtime se tímto prvním mechanismem nepřepisují.
Změna bootstrapu vyžaduje nový instalátor; manifest `MinimumLauncher` to
vynucuje. Rozdíl je na úrovni souborů, nikoli jednotlivých bajtů velké DLL.
Maxima: 4096 souborů, 256 MiB/soubor, 1 GiB celkem, metadata 8 MB.

Ve Windows je instalace pro aktuální účet, včetně zástupců na stabilní launcher.
Nové ověřené soubory se přidávají do seznamu vlastnictví odinstalátoru. Linux
používá základ z APT a uživatelské verze bez sudo; viz [Linux](../Linux/README.md).

## macOS

Sparkle **2.10.1** je připnutá závislost. Aplikace zůstává v sandboxu s BLE, sériovými USB porty,
odchozí sítí a dvěma konkrétními Mach výjimkami pro služby Sparkle. Hardened
Runtime a kontrola knihoven zůstávají; nevypíná se Gatekeeper. Pomocné
komponenty se podepisují jednotlivě před podpisem aplikace.

Feed `macos/appcast.xml` je také podepsaný a ukazuje Ed25519 podepsané archivy a rozdíly.
Klient podpis feedu vyžaduje a archiv ověřuje ještě před rozbalením. Sparkle
ověří podpis a Developer ID aplikace před nahrazením a restartem. Pro známou
původní verzi lze vygenerovat binární delta aktualizaci. Není-li dostupná nebo
ji nelze aplikovat, použije se podepsaný úplný archiv. Nelze tedy slíbit malý
rozdílový download pro každý přechod. Automatické stahování/instalace jsou
vypnuté; release notes se nevykreslují ve WebView.

Starší 0.8.x neobsahují Sparkle. **První instalace 0.9.0 je ruční**; automatické
zjišťování a potvrzené aktualizace jsou dostupné až z ní.

## Příprava obsahu serveru

`tools/package_release.py` sestaví verzi Windows/Linux z publikované aplikace
a launcheru, vytvoří podepsaný manifest přes `tools/UpdatePublisher` a objekty.
Vyžaduje odpovídající soukromý klíč PKCS#8. Ten nesmí být ve zdrojích, balíčcích
ani webovém adresáři. Nový fork musí vytvořit vlastní klíč a vložit jeho veřejnou
část do klienta i launcheru; přegenerování klíče původního vydavatele rozbije
důvěru existujících instalací. Privátní klíče zálohujte odděleně.

Sparkle nástroj `generate_appcast` dostane adresář notarizovaných archivů a
odpovídající klíč z Keychain. Pro budoucí rozdíly zachovejte skutečné předchozí
podepsané aplikace/archivy. Příprava nesmí měnit staré vydané archivy. Změna
serverového XML po vytvoření podpisu může podpis zneplatnit.

Serverový adresář má veřejné `stable/`, `objects/` a `macos/`; žádné klíče,
pracovní logy, profily nebo `.git`. Nejprve musí být dostupné úplné nové objekty
či archivy a teprve poté nový feed. Metadata mají mít krátkou cache, objekty
mohou mít dlouhou immutable cache. Obsah objektů nepřepisovat ani neobalovat
HTML stránkou. Podepsané .NET feedy mají platnost 90 dní a je potřeba je včas
obnovit, i když se verze aplikace nemění. Ověřené nainstalované aplikace po
uplynutí platnosti feedu nadále fungují offline.

Žádný přípravný skript soubory na server ani GitHub nenahrává. Bez vystavení
připraveného adresáře server zatím novou verzi nenabídne.

## Ověření

Automatické testy používají vlastní testovací klíč, náhradu HTTP serveru,
dočasná data a řízený čas. Pokrývají podpis, cesty, platformu, expiraci, rozsah
stahování, poškození, zrušení, souhlas, souběh se servisem, přepnutí/obnovu
ukazatele a rozhodnutí při potvrzení startu. Nenahrazují skutečný test přechodu
mezi dvěma vydanými verzemi na Windows/Linux/macOS, SmartScreen/Gatekeeper,
přerušení napájení ani fyzické BLE/LoRa ověření.

Oficiální podklady: [Sparkle](https://sparkle-project.org/documentation/),
[rozdílové aktualizace](https://sparkle-project.github.io/documentation/delta-updates/),
[sandbox](https://sparkle-project.github.io/documentation/sandboxing/).

Doplňkový vydavatelský procesový test v `Shared/tests/UpdateHarness` používá
krátce běžící zkušební procesy 0.0.x, místní náhradu HTTP a dočasné adresáře.
Na macOS nahrazuje pouze poskytovatele Linux instalačního adresáře v dočasné
kopii zdrojů; distribuované zdroje nemění. Prověřuje restart/rollback skutečným
pomocníkem v této simulaci. Není náhradou nativního Windows/Linux testu.

## Vydání 0.10.0

USB připojení se před instalací/restartem zavře stejně jako BLE. Probíhající
otevírání USB nebo příkaz přímému repeateru blokují zahájení instalace. Po
restartu se USB nepřipojuje a diagnostické měření se neobnovuje automaticky.
Distribuce zachovává původní bundle ID `cz.zavadilmatej.meshcoreservicer` a tým
Developer ID; veřejný Xcode projekt zůstává obecný pro vlastní sestavení.
Sériové porty v sandboxu vyžadují `com.apple.security.device.serial`, které
vynucuje i kontrola distribučního podpisu. [Dokumentace oprávnění Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

Všechny čtyři .NET feedy a macOS appcast mají verzi 0.10.0 (macOS build 15).
Rozdíl stahování záleží na původní instalaci; změna runtime může znamenat
větší objem souborů. Linux aktualizace uvnitř aplikace nemění závislosti ani
verzi zaznamenanou v dpkg; ty aktualizujte instalací DEB přes APT.
