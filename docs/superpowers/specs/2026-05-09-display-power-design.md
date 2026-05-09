# DisplayPower — Design-Dokument

**Datum:** 2026-05-09  
**Status:** Genehmigt

---

## Problem

HDMI-Monitore senden keinen sauberen Disconnect-Befehl, wenn sie auf ein anderes Eingangssignal umschalten. macOS erkennt das nicht und behandelt den Monitor weiterhin als aktiv verbunden — Fenster bleiben auf dem "unsichtbaren" Display stecken.

## Ziel

Eine minimale macOS-Menu-Bar-App, die einen ausgewählten externen Monitor per Klick deaktiviert und wieder aktiviert, sodass macOS die Fenster neu anordnet. Mehr soll die App nicht tun.

---

## Architektur

Swift Package Manager (kein Xcode-Projekt), drei Quelldateien:

| Datei | Zweck |
|---|---|
| `Sources/DisplayPower/main.swift` | Einstiegspunkt: `NSApplication` ohne Dock-Icon starten |
| `Sources/DisplayPower/AppDelegate.swift` | `NSStatusItem`, Linksklick-Toggle, Rechtsklick-Popover |
| `Sources/DisplayPower/DisplayManager.swift` | Alle CoreGraphics-Aufrufe, Display-Zustand, Namenscache |

---

## Interaktion

### Linksklick auf den Menu-Bar-Icon

Toggled sofort den in den Einstellungen gewählten Monitor:
- Ist er aktiv (eigenständig) → wird auf `CGMainDisplayID()` gespiegelt → alle Fenster wandern auf den Hauptmonitor
- Ist er gespiegelt → Mirroring wird aufgehoben → Display wird wieder eigenständig

### Rechtsklick auf den Menu-Bar-Icon

Öffnet ein `NSPopover` mit:
- Überschrift: "Aktiver Monitor"
- Radio-Button-Liste aller aktuell angeschlossenen externen Displays (Name via `NSScreen.localizedName`, Fallback aus Cache)
- Trennlinie
- Schaltfläche "Beenden"

Die Auswahl wird in `UserDefaults` unter dem Key `selectedDisplayID` gespeichert und beim nächsten App-Start wiederhergestellt. Ist die gespeicherte ID nicht mehr vorhanden, wird automatisch der erste verfügbare externe Monitor gewählt.

---

## Icon-Zustände

| Zustand | SF Symbol | Darstellung |
|---|---|---|
| Monitor **an** (eigenständig) | `display` | Template-Farbe (schwarz/weiß je nach Menüleiste) |
| Monitor **aus** (gespiegelt) | `display` | Gedimmt (alpha 0.4) |
| Kein externer Monitor konfiguriert | `display.trianglebadge.exclamationmark` | Template-Farbe |

---

## Kern-APIs

| Funktion | Verwendung |
|---|---|
| `CGGetOnlineDisplayList` | Alle angeschlossenen Displays (auch gespiegelte) |
| `CGDisplayIsBuiltin` | Eingebautes Display (MacBook-Screen) herausfiltern |
| `CGDisplayMirrorsDisplay(id)` | Prüft ob Display gerade gespiegelt ist (`!= kCGNullDirectDisplay`) |
| `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` | Konfigurationsblock |
| `CGConfigureDisplayMirrorOfDisplay(config, id, target)` | Spiegeln ein- oder ausschalten |
| `NSApplication.didChangeScreenParametersNotification` | Automatisches Aktualisieren bei Display-Änderungen |

---

## Display-Namen (Cache)

Da gespiegelte Displays nicht in `NSScreen.screens` erscheinen:
- Beim letzten aktiven Zustand wird der `NSScreen.localizedName` im `DisplayManager` gecacht (Dictionary `[CGDirectDisplayID: String]`)
- Fallback: `"Bildschirm \(displayID)"`

---

## Persistenz

Nur ein einziger `UserDefaults`-Key:

| Key | Typ | Bedeutung |
|---|---|---|
| `selectedDisplayID` | `Int` | `CGDirectDisplayID` des gewählten Monitors |

---

## Plattform & Build

- **Minimum:** macOS 12 (für `NSScreen.localizedName`)
- **Swift:** 6.x (kompatibel mit Swift 6.3.1 / macOS Tahoe 26.x)
- **Build:** `swift build -c release`
- **Ausführen:** `.build/release/DisplayPower` (oder als Login-Item einrichten)

---

## Nicht im Scope

- Helligkeit steuern
- Display-Reihenfolge/-Anordnung ändern
- Notch-/Einblend-Animationen
- Automatische Trigger (z.B. bei bestimmter Uhrzeit)
