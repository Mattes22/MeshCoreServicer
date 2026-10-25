# Podepsaná distribuce macOS

Vydání pro Apple Silicon a Intel používá Developer ID Application, Hardened Runtime, sandbox a notarizaci Apple. Pro DMG není potřeba Developer ID Installer; ten je určený pro balíčky PKG. Zdrojový Xcode projekt ani jeho lokální tým/podpis se tímto postupem nepřepisují.

## Jednorázově na vydavatelově Macu

1. Xcode → Settings → Accounts → vlastní tým → Manage Certificates → „+“ → **Developer ID Application**. Pro ruční podepisování musí být certifikát i odpovídající privátní klíč v místní Klíčence; Apple Development nestačí. Certifikát ani klíč se do projektu nekopírují.
2. Na [account.apple.com](https://account.apple.com/) vytvořte v Sign-In and Security → App-Specific Passwords heslo pro notarizaci.
3. V běžném Terminálu spusťte interaktivně:

   ```sh
   xcrun notarytool store-credentials MeshCore-notary
   ```

   Pokud se nejdříve objeví `Path to App Store Connect API private key:`, nechte pole prázdné a stiskněte Enter. Potom vyplňte vydavatelský Apple Account, heslo pro aplikaci a Team ID z členství Developer Program. Heslo se zadává do skryté výzvy a uloží se do macOS Keychain. Nedávejte ho do argumentů příkazů, souboru projektu nebo chatu. Alternativou je místně nakonfigurovaný profil s App Store Connect API klíčem; release skript přijímá pouze název profilu.

   V prostředí se sandboxem nemusí být Klíčenka viditelná. Ověření provádějte v normálním Terminálu; `0 valid identities` v omezeném procesu samo o sobě nedokazuje, že certifikát neexistuje.

## Vydání

Z kořenové složky projektu, pomocí Pythonu 3.9+ a Xcode. Nejsou potřeba další Python balíčky.

```sh
python3 -m unittest discover -s scripts -p 'test_release_macos.py'
python3 scripts/release-macos.py check
python3 scripts/release-macos.py prepare --work build/macos-release
python3 scripts/release-macos.py sign --work build/macos-release
```

`prepare` sestaví nový nepodepsaný univerzální `.xcarchive`. Použije aktuální bundle identifier a verzi Xcode projektu, přepíše nastavení architektur na arm64 + x86_64 a vypne automatickou správu podpisů pouze pro tento příkaz. Tým ani App ID v projektu nemění, neinstaluje aplikaci a nepřipojuje zařízení. Neprázdnou pracovní složku odmítne; pro nové sestavení použijte jiné `--work`.

`sign` vytvoří pracovní kopii, podepíše ji Developer ID s důvěryhodným časovým razítkem a ověří podpis, skutečné architektury a přesná oprávnění. Pokud macOS požádá o přístup `codesign` k privátnímu klíči, rozhoduje vydavatel v systémovém dialogu. Při více distribučních identitách přidejte `--identity SHA1`. Vznikne lokální podepsaná aplikace a ZIP pro kontrolu; zatím nejsou notarizované ani určené veřejnosti.

Po kontrole podepsaného produktu spusťte:

```sh
python3 scripts/release-macos.py notarize --work build/macos-release --keychain-profile MeshCore-notary
```

Tento příkaz už výslovně **odesílá aplikaci společnosti Apple**. Po odeslání uloží ID úlohy a nečeká neomezeně. Dokud služba pracuje, další kontrolu proveďte stejným pracovním adresářem:

```sh
python3 scripts/release-macos.py resume --work build/macos-release --keychain-profile MeshCore-notary
```

Příkaz se může opakovat při stavu In Progress. Již uložená ID úloh se nepřihlašují znovu jako nové uploady. Probíhají dva kroky: nejdříve ZIP aplikace, po schválení a připojení ticketu k aplikaci vznikne podepsané DMG a odešle se k notarizaci i ono. Dva kroky zajistí ticket také přímo u aplikace uvnitř DMG. Mezi kroky se kontrolují SHA-256 odesílaných artefaktů; upravený soubor se neodesílá jako původní vydání.

Skript vyžaduje stav Accepted a kontroluje také notary log. Při chybách nebo varováních se zastaví a ponechá podklady v pracovní složce. Nikdy nepoužívá `--force` pro vynucené přijetí ani nevypíná Gatekeeper. Do `dist` zkopíruje výsledek až po `stapler validate`, ověření podpisu DMG, `hdiutil verify`, posouzení Gatekeeper a kontrole aplikace pomocí `syspolicy_check distribution`. Přidá SHA-256 a validační JSON. Jiný existující DMG stejného jména automaticky nepřepisuje.

Záznam vydání a notary/build logy zůstávají v ignorovaném `build/` a nemají se přibalovat ke zdrojům nebo běžné aplikaci. Hesla se skriptu nepředávají; využívá pouze Keychain profil. MacOS může kvůli své bezpečnostní politice vyžadovat schválení přístupu ke Klíčence i při dříve uloženém profilu.

## Před prvním veřejným vydáním

Zvolte stabilní bundle identifier a vydavatelský tým. Skript zachovává hodnoty aktuálního projektu. Jiný bundle identifier může znamenat jiný sandboxový kontejner a změna vydavatelského podpisu může vyvolat nový dotaz ke Klíčence; osobní data se automaticky nepřesouvají ani nemažou.

Testujte konečné DMG stažené přes prohlížeč na druhém/čistém Macu, včetně odpojeného internetu po stažení, přetažení do Aplikací, aktualizace, prvního spuštění, systémového Bluetooth oprávnění a přístupu k uloženým heslům. Automatické kontroly vydání nejsou skutečný test čerstvě stažené aplikace na jiném Macu ani test BLE. Běžné potvrzení prvního otevření a žádost o Bluetooth zůstávají součástí macOS.

Aktuální skript je pro jednu staticky linkovanou aplikaci. Pokud projekt později získá frameworky, extension, XPC nebo přihlašovací helper, zastaví se a bude nutné doplnit podepisování vnořeného kódu od nejvnitřnější položky. Pro podpis nepoužívá plošné `codesign --deep`; parametr `--deep` používá jen pro ověření.

Primární zdroje: [Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [vytváření identity v Xcode](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates), [notarizace](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [balení a stapling](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). Konkrétní syntaxi příkazů ověřujte také přes `xcrun notarytool --help` v použitém Xcode.
