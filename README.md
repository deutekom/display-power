# DisplayPower

Schlanke macOS-Menüleisten-App zum Ein- und Ausschalten externer Monitore per Klick.

## Funktionsweise

- **Linksklick** auf das Menüleisten-Icon schaltet den ausgewählten Monitor ein oder aus
- **Rechtsklick** öffnet das Einstellungsmenü

Das Aus- und Einschalten erfolgt über CoreGraphics-Mirroring – keine privaten APIs, App-Store-kompatibel.

## Features

- Schneller Toggle per Linksklick
- Auswahl des Ziel-Monitors bei mehreren externen Displays
- Wählbares Menüleisten-Icon (Monitor, TV, HDMI, Kabel, …)
- Autostart beim Login
- Lokalisiert in 19 Sprachen: Deutsch, Englisch, Arabisch, Dänisch, Spanisch, Finnisch, Französisch, Italienisch, Japanisch, Koreanisch, Norwegisch, Niederländisch, Polnisch, Portugiesisch (Brasilien), Russisch, Schwedisch, Türkisch, Chinesisch (vereinfacht), Chinesisch (traditionell)
- USB-C/Thunderbolt-Displays werden ausgegraut angezeigt (nicht steuerbar via Mirroring-API)

## Voraussetzungen

- macOS 12 oder neuer
- Apple Silicon oder Intel Mac
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
swift build -c release
```

Das fertige Binary liegt unter `.build/release/DisplayPower`.

## Einschränkungen

Displays, die über USB-C/Thunderbolt oder DisplayLink-Adapter angeschlossen sind, können nicht über die öffentliche CoreGraphics-API gesteuert werden und erscheinen ausgegraut im Menü.

## Lizenz

MIT
