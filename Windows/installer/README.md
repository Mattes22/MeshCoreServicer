# Windows instalátory MeshCore Servicer

Skutečné NSIS `.exe` instalátory, český průvodce, samostatný balíček x64 a ARM64. Aplikace zůstává nativní WPF. NSIS bootstrapper je x86 a na Windows ARM64 běží systémovou emulací; vložená aplikace a .NET/WPF runtime jsou skutečné ARM64. x64 balíček vyžaduje nativní procesor AMD64, ARM64 balíček nativní ARM64. Minimum je Windows 10 build 19041. Nejde o MSI/MSIX.

## Co uživatel dostane

- Instalaci pouze pro aktuální účet do `%LOCALAPPDATA%\Programs\MeshCore Servicer`, bez správce a bez samostatné instalace .NET.
- Povinného zástupce aplikace a odinstalace v nabídce Start, volitelného zástupce na ploše.
- Záznam v Nastavení Windows → Aplikace, s verzí a odinstalací.
- Aktualizaci/opravu spuštěním stejného nebo novějšího instalátoru. Starší verze je odmítnuta. Žádné automatické vyhledávání nebo stahování aktualizací.
- Kontrolu běžící aplikace včetně oznamovací oblasti, bez násilného ukončení procesu. Instalační proces drží stejný mutex jako aplikace, aby se během zápisu nespustila další instance. Při volitelném spuštění na závěrečné stránce se zámek uvolní.
- Odinstalaci jen souborů evidovaných jako součást instalace. Přidané soubory a neprázdné adresáře se rekurzivně nemažou. Seznam se při aktualizaci doplňuje, aby odinstalace znala i soubory z předchozích vydání. Osobní historie/profily v `%LOCALAPPDATA%\MeshCoreServicer` a položky Credential Manageru se nemažou. Přenosná ZIP kopie se neodinstaluje.

Instalátor nekomunikuje s BLE/LoRa, nespouští aplikaci bez zaškrtnutí volby a nezapisuje firmware ani nastavení zařízení. Cílová složka je pevná; přepínač `/D` se záměrně nepoužívá. Při chybě kopírování se instalace zastaví. Opravu lze zopakovat; nejde o transakční MSI s automatickým rollbackem. Před aktualizací ukončete aplikaci v oznamovací oblasti.

Balíčky **nejsou digitálně podepsané**. Windows proto může zobrazit neznámého vydavatele/SmartScreen. Není přiložený vydavatelský certifikát ani předstíraný podpis. Před veřejnou distribucí lze EXE podepsat vlastním důvěryhodným certifikátem; po podpisu je nutné znovu spočítat SHA-256.

## Sestavení

Bezplatné nástroje: .NET 10 SDK, Python 3.9+ a NSIS (ověřeno 3.13). Python nemá další balíčky. [NSIS lze používat i na macOS/Linux](https://nsis.sourceforge.io/Docs/AppendixG.html). Skripty nepoužívají `File /r`: publikovaný obsah projde kontrolou architektury, vlastní přibalené verze, runtime, názvů souborů a vyloučením osobních archivů. Ke každému instalátoru vznikne `.payload.json` se SHA-256 všech vložených souborů a `.sha256` samotného EXE. NSIS varování jsou chyby sestavení.

Ve Windows z adresáře `Windows`:

```powershell
.\build.ps1 -Runtime win-x64 -Installer
.\build.ps1 -Runtime win-arm64 -Installer
# Pokud NSIS není na standardním místě:
.\build.ps1 -Runtime win-x64 -Installer -Makensis 'C:\Tools\NSIS\makensis.exe'
```

Pouze z již vytvořené publikace:

```powershell
python -m unittest discover -s installer -p 'test_*.py'
python installer/build_installer.py --runtime win-x64
```

Na Macu může být potřeba nastavit `NSISDIR` na složku obsahující `Include`, `Stubs`, `Plugins` a `COPYING`, a `MAKENSIS` na spustitelný kompilátor. Nástroje ani zkompilované cache nejsou součástí zdrojového projektu. NSIS licence je přiložená jako `ThirdParty/NSIS-COPYING.txt` v instalované aplikaci.

## Ověření a jeho omezení

Zde na macOS prošlo osm testů generátoru, obě skutečné kompilace NSIS s varováními jako chybami, rozbalení instalátorů pomocí 7-Zip a porovnání SHA-256 všech 415 vložených souborů x64 a 414 ARM64 (včetně NSIS licence). Obsah aplikace odpovídá již sestavené verzi 0.7.3 s 92 testy jádra. Kontrola zahrnuje skutečnou architekturu aplikace/runtime, uninstaller a nepřítomnost osobních údajů v balíčku. Nevydáváme statickou kontrolu za provedenou instalaci.

**Běh průvodce, změny registru, zástupci, aktualizace, odinstalace a SmartScreen zde na Windows nebyly vyzkoušené.** Pro kontrolu v čistém účtu/VM Windows je přiložen skript:

```powershell
.\installer\verify-installer.ps1 `
  -Installer '.\out\MeshCoreServicer-0.7.3-Windows-x64-Setup.exe' `
  -PayloadManifest '.\out\MeshCoreServicer-0.7.3-Windows-x64-Setup.payload.json' `
  -DisposableTestEnvironment
```

Skript odmítne existující instalaci/historii. Ověřuje tichou instalaci, všechny soubory, registraci, opakovanou instalaci/opravu, blokaci běžící aplikace pomocí mutexu, odmítnutí downgrade, odinstalaci a zachování testovacích osobních a přidaných souborů. Aplikaci ani BLE nespouští. Otestujte zvlášť skutečný upgrade z budoucího staršího vydání, oba procesory, účet s diakritikou, volitelného zástupce na ploše, nabídku Start, závěrečné spuštění a normální odinstalaci přes Nastavení. V případě selhání neuklízí automaticky případnou instalaci ani testovací data, aby zůstaly podklady pro kontrolu.

Tiché použití: `Setup.exe /S`, odinstalace `Uninstall.exe /S`. Návratové kódy: `0` úspěch, `1603` chyba instalace/odinstalace, `1618` běžící aplikace nebo instalátor, `1633` nepodporované Windows/CPU, `1638` odmítnutí downgrade. Bez aplikace běžící na pozadí není potřeba restart PC.

## Nástroje tohoto sestavení

NSIS 3.13, macOS ARM64 Homebrew bottle SHA-256 `02605964f5fb05003331867c10cf89dbfa0bf4eeeca7ee397787a4d8084837ac`; 7-Zip 26.05 pouze pro kontrolu extrakce. Instalátory se kontrolovaly na macOS, ne ve Windows. Primární dokumentace: [per-user příklad NSIS](https://github.com/nsis-dev/nsis/blob/master/Examples/install-per-user.nsi), [příkazy a odinstalace](https://nsis.sourceforge.io/Docs/Chapter4.html), [Modern UI](https://nsis.sourceforge.io/Docs/Modern%20UI%202/Readme.html).
