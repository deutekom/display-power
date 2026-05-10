# DisplayPower

Schlanke macOS-Menüleisten-App, die externe HDMI-Monitore für macOS gezielt „unsichtbar" macht – per Klick.

## Das Problem

Das Kabel steckt noch drin – und das reicht macOS, um den Monitor als aktiv zu behandeln.

Wer einen HDMI-Monitor an den Mac anschließt und ihn später ausschaltet oder auf einen anderen Eingang umschaltet, erlebt das klassische Problem: macOS bemerkt die physische Änderung nicht. Solange das HDMI-Kabel steckt, gilt der Monitor für das Betriebssystem als verbunden und aktiv – egal was auf dem Bildschirm zu sehen ist.

Die Folgen:

- Fenster und Apps wandern auf den „ausgeschalteten" Monitor und sind scheinbar verschwunden
- Die Desktop-Anordnung verändert sich, Spaces verschieben sich
- Der Bildschirmschoner oder Energiesparmodus greift möglicherweise nicht wie erwartet, weil macOS einen aktiven zweiten Bildschirm annimmt
- Das Kabel abziehen ist oft keine Option – etwa bei fest installierten Setups oder wenn der Monitor per KVM zwischen mehreren Geräten wechselt

## Die Lösung

DisplayPower nutzt einen gezielten Trick: Statt den Monitor zu „deaktivieren" (was macOS über öffentliche APIs gar nicht erlaubt), wird er als **Spiegel des Hauptbildschirms** konfiguriert.

Das Ergebnis: macOS behandelt den HDMI-Monitor nicht mehr als eigenständige Arbeitsfläche. Alle Fenster, Spaces und Apps bleiben auf dem Hauptbildschirm – der externe Monitor existiert für macOS zwar noch, belegt aber keinen eigenen Desktop-Bereich mehr. Der Bildschirmschoner und der Energiesparmodus orientieren sich wieder am Hauptbildschirm.

Das Kabel kann weiterhin stecken bleiben.

## Funktionsweise

- **Linksklick** auf das Menüleisten-Icon schaltet den ausgewählten Monitor ein oder aus
- **Rechtsklick** öffnet das Einstellungsmenü
- Optional: **Linksklick öffnet Menü** (mehrere Monitore direkt togglen)

Das Ein- und Ausschalten erfolgt über `CGConfigureDisplayMirrorOfDisplay` – ausschließlich öffentliche APIs, keine privaten Frameworks.

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

1. [`DisplayPower-v1.0.2.dmg`](https://github.com/deutekom/display-power/releases/latest) herunterladen
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
