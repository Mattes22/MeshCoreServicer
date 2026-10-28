# MeshCore Servicer 0.10.0 · macOS

Nativní SwiftUI aplikace pro macOS 14+ s CoreBluetooth. Companion je místní BLE
spojení; vzdálený repeater se spravuje přes companion po LoRa. Hesla zůstávají
v macOS Keychain. [Společný přehled](../README.md).

Otevřete `MeshCoreServicer.xcodeproj`, zvolte schéma MeshCoreServicer a spusťte
aplikaci. Veřejný projekt má obecný bundle identifier a lokální ad-hoc podpis.
Pro vlastní distribuci je nutný vlastní Developer ID podpis a notarizace;
sestavení ze zdrojů nezískává podpis původního vydavatele.

```sh
swift test
```

Sparkle 2.10.1 je připnutá Swift Package závislost. Kontroly verzí používají
vlastní HTTPS server; stažení a instalace vyžadují potvrzení. Klient vyžaduje
podepsaný appcast a ověří archiv před rozbalením. Přednost mají rozdílové
aktualizace, případně se nabídne úplný podepsaný archiv. Správce a diagnostické
měření se po restartu neobnovují. První přechod ze starší 0.8.x je přes DMG.
[Aktualizační mechanismus](../docs/UPDATES.md).

Diagnostika je ručně spouštěná: výchozí 4 h × 3, interval 3–24 h, nejvýše
6 vzorků/24 h. Historie a grafy jsou místní. Staré nastavení se migruje bez
obnovení měření. [Limity LoRa](docs/TRAFFIC_POLICY.md).

- [Protokol a přesné referenční commity](PROTOCOL.md)
- [Ověření a omezení](COMPATIBILITY.md)
- [Fyzický kontrolní seznam](HARDWARE_CHECKLIST.md)
- [Distribuční podpis a notarizace](scripts/MACOS_DISTRIBUTION.md)

Sestavení, testy a notarizace samy neprokazují funkční BLE/LoRa spojení na
konkrétním zařízení. Žádná konfigurace ani diagnostika se po připojení sama
neodesílá. Chat a konzole používají skutečná data, nikoli ukázkové uzly.

## USB od 0.10.0

USB companion i přímý USB repeater: [připojení, protokol a ověření](../docs/USB.md).
Port se otevírá jen výslovně; BLE i USB současně se nepoužívají.
