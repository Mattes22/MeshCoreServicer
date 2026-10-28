# Přispívání

Hlášení chyb a návrhy posílejte přes Issues. Uveďte platformu, verzi aplikace,
firmware companionu a repeateru, postup a očekávaný výsledek. Hesla, klíče,
obsah zpráv, souřadnice a osobní kontakty do veřejných hlášení nepatří.

Pro změny použijte vlastní větev a pull request. Protokolové změny doložte
odkazem na konkrétní commit oficiálního firmwaru a testem rámce nebo odpovědi.
Transport, parser, aplikační logiku a nativní UI udržujte oddělené. Automatické
testy nesmějí vyžadovat zařízení ani vysílat po BLE/LoRa.

Kontroly z kořene repozitáře:

```sh
python3 -m unittest discover -s macOS/scripts -p 'test_*.py'
python3 -m unittest discover -s Windows/scripts -p 'test_*.py'
python3 -m unittest discover -s Windows/installer -p 'test_*.py'
python3 -m unittest discover -s Linux/packaging -p 'test_*.py'
python3 -m unittest discover -s tools -p 'test_*.py'
dotnet run --project Shared/tests/MeshCore.Updates.Tests -c Release
dotnet run --project Linux/tests/MeshCore.Linux.Tests -c Release
```

Na macOS navíc `swift test --package-path macOS`. Pro Windows z adresáře `Windows` spusťte
`dotnet run --project tests/MeshCore.Tests -c Release` a
`dotnet build MeshCoreServicer.slnx -c Release` na Windows s .NET 10 SDK.
Úspěšné sestavení nenahrazuje fyzický BLE/LoRa test; v pull requestu rozlište,
které kontroly skutečně proběhly.

Vlastní příspěvky poskytujte pod MIT licencí projektu. U převzatých částí
zachovejte jejich licenci a původ. Licence runtime komponent Windows jsou
v `Windows/ThirdParty`.

Sdílené .NET jádro patří do `Shared/MeshCore.Core`, transport a nativní UI
do příslušné platformy. Podpisové klíče ani údaje notarizace do zdrojů nepatří.
