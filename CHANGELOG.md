# Změny MeshCore Servicer

## 0.8.0 — 25. 10. 2026

- Neomezený monitoring nahrazuje ručně spuštěné diagnostické měření s intervalem
  a počtem vzorků. Výchozí plán: 3 vzorky po 30 minutách se známou trasou;
  pro flood nebo neznámou trasu nejméně 60 minut. Limit: 6 vzorků během 6 hodin.
- Každý vzorek aktivně vyšle požadavek přes LoRa a vyvolá odpověď.
  Rozhraní zobrazuje plán, průběh, zbývající vzorky a Zastavit.
- Ruční servis a diagnostika sdílejí omezení: nejvýše 60 požadavků za klouzavou
  hodinu, z toho nejvýše 12 přes flood nebo neznámou trasu. Prodleva je nejméně
  15 sekund při známé trase, jinak 60 sekund. Vícekrokové operace účtují každý
  vzdálený požadavek zvlášť; nejvýše 32 kroků nebo 20 minut na operaci.
- Žádné automatické opakování, dohánění zmeškaných vzorků ani obnovení měření
  po odpojení, spánku či restartu. Změna uzlu, ztráta oprávnění a chyba měření
  zastaví. Již odeslaný požadavek může dokončit čekání na odpověď.
- Historie a grafy zůstávají místní. Migrace zachová data a starý monitoring
  automaticky nezapne. Místní BLE čtení companionu se neúčtuje jako LoRa servis.
- macOS i Windows používají společné číslo verze 0.8.0; macOS sestavení 8.

Žádný interval není univerzálně bezpečný. Podrobnosti a zdůvodnění limitů:
[Provoz LoRa a diagnostika](docs/TRAFFIC_POLICY.md).

Ověření: 151 Swift testů, 111 C# testů a 25 testů balení bez skutečného zařízení;
Xcode Release pro arm64 a x86_64 a Windows WPF cross kompilace prošly.
macOS DMG se distribuuje s Developer ID podpisem a notarizací Apple;
Windows EXE jsou bez digitálního podpisu a mohou zobrazit SmartScreen.
Fyzické BLE/LoRa měření, čerstvá instalace na jiném Macu a instalace, aktualizace
či odinstalace ve Windows nebyly v tomto prostředí provedené.
