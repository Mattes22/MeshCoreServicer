# Přispívání

Chyby a návrhy patří do Issues. Uveďte verzi systému a aplikace, firmware
companionu a repeateru, postup a očekávaný výsledek. Nezveřejňujte hesla,
klíče, obsah zpráv, souřadnice ani osobní kontakty.

Změny posílejte jako pull request. Protokolové změny doložte konkrétním
commitem oficiálního firmwaru a testem rámce nebo odpovědi. Transport,
parser, aplikační logiku a nativní UI udržujte oddělené. Testy nesmějí
vyžadovat zařízení ani vysílat přes BLE/LoRa.

Příkazy z kořene tohoto projektu:

```powershell
dotnet run --project tests/MeshCore.Tests -c Release
dotnet build MeshCoreServicer.slnx -c Release
python -m unittest discover -s installer -p 'test_*.py'
python -m unittest discover -s scripts -p 'test_*.py'
```

WPF sestavení a interaktivní zkoušky vyžadují Windows. Rozlište kompilaci,
automatické testy a skutečně provedené testy BLE/LoRa. Vlastní příspěvky
poskytujte pod MIT licencí projektu; u převzatých částí zachovejte původ
a licenční podmínky. Runtime oznámení zůstávají v `ThirdParty`.
