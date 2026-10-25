# Přispívání

Chyby a návrhy patří do Issues. Uveďte verzi systému a aplikace, firmware
companionu a repeateru, postup a očekávaný výsledek. Nezveřejňujte hesla,
klíče, obsah zpráv, souřadnice ani osobní kontakty.

Změny posílejte jako pull request. Protokolové změny doložte konkrétním
commitem oficiálního firmwaru a testem rámce nebo odpovědi. Transport,
parser, aplikační logiku a nativní UI udržujte oddělené. Testy nesmějí
vyžadovat zařízení ani vysílat přes BLE/LoRa.

Příkazy z kořene tohoto projektu:

```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Přiložte výsledek Xcode sestavení. Rozlište automatické kontroly od skutečně
provedených testů BLE/LoRa. Vlastní příspěvky poskytujte pod MIT licencí
projektu; u převzatých částí zachovejte původ a licenční podmínky.
