# DisplayPower

Schlanke macOS-Menüleisten-App, die externe Monitore für macOS gezielt „unsichtbar" macht – per Klick.

## Wofür ist das nützlich?

Viele HDMI-Monitore bleiben für macOS dauerhaft als aktives Display sichtbar, auch wenn der Bildschirm physisch ausgeschaltet ist oder auf einen anderen Eingang umgeschaltet wurde. macOS bemerkt das nicht und behandelt den Monitor weiterhin als eingeschaltet:

- Fenster und Apps werden auf den „ausgeschalteten" Monitor verschoben
- Die Auflösung oder Anordnung der Desktops verändert sich
- Der Bildschirmschoner oder Ruhezustand greift nicht korrekt

DisplayPower löst das, indem es macOS per CoreGraphics-Mirroring mitteilt, dass der Monitor nicht mehr aktiv ist – unabhängig davon, was der Monitor physisch meldet.

## Funktionsweise

- **Linksklick** auf das Menüleisten-Icon schaltet den ausgewählten Monitor ein oder aus
- **Rechtsklick** öffnet das Einstellungsmenü
- Optional: **Linksklick öffnet Menü** (mehrere Monitore direkt togglen)

Das Aus- und Einschalten erfolgt über `CGConfigureDisplayMirrorOfDisplay` – ausschließlich öffentliche APIs, keine privaten Frameworks.

## Features

- Schneller Toggle per Linksklick
- Auswahl des Ziel-Monitors bei mehreren externen Displays
- Menu-Click-Modus: Menü statt direktem Toggle, Haken zeigt Ein-/Aus-Status
- Wählbares Menüleisten-Icon (Monitor, TV, HDMI, Kabel, …)
- Autostart beim Login
- Lokalisiert in 19 Sprachen

## Einschränkungen

Displays, die über **USB-C/Thunderbolt** oder **DisplayLink**-Adapter angeschlossen sind, lassen sich nicht über die öffentliche CoreGraphics-API steuern. Sie erscheinen ausgegraut im Menü mit dem entsprechenden Verbindungstyp als Hinweis.

## Installation

1. [`DisplayPower-v1.0.0.dmg`](https://github.com/deutekom/display-power/releases/latest) herunterladen
2. DMG öffnen und `DisplayPower.app` in den Programme-Ordner ziehen

> **Gatekeeper-Hinweis:** Da die App nicht mit einem kostenpflichtigen Apple Developer-Zertifikat signiert ist, blockiert macOS den Start.
>
> **macOS Tahoe (15/16) und neuer:** Nach dem ersten Startversuch unter **Systemeinstellungen → Datenschutz & Sicherheit** nach unten scrollen – dort erscheint ein Hinweis mit der Option „Trotzdem öffnen".
>
> **Ältere macOS-Versionen:** **Rechtsklick → Öffnen → Öffnen** bestätigen.
>
> Danach startet die App normal.
>
> **Nach einem Update fehlt der Hinweis in Datenschutz & Sicherheit?** Das kann passieren, wenn macOS das Quarantäne-Attribut nach einer Neuinstallation nicht erneut anzeigt. Abhilfe per Terminal:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/DisplayPower.app
> ```
>
> Danach lässt sich die App direkt starten.

## Voraussetzungen

- macOS 12 oder neuer
- Apple Silicon oder Intel Mac

## Selbst bauen

```bash
git clone https://github.com/deutekom/display-power
cd display-power
swift build -c release
```

Das fertige Binary liegt unter `.build/release/DisplayPower`.

## Lizenz

MIT
