# DisplayPower – Projektkontext

macOS-Menüleisten-App (SPM, kein Xcode). Schaltet externe Monitore via CoreGraphics-Mirroring ein/aus. Ziel: App Store.

## Architektur

```
main.swift          – NSApplication, .accessory-Policy, Single-Instance-Guard
AppDelegate.swift   – StatusItem, Klick-Routing, Menü, Autostart (LaunchAgent)
DisplayManager.swift – Display-Enumeration, Mirroring-Toggle, IOKit-Erkennung
Localization.swift  – Explizite Locale-Auflösung (NSBundle-Bug-Workaround für SPM)
Resources/{lang}.lproj/Localizable.strings – 19 Sprachen, Standardsprache: de
```

## Kerntechnik

**Toggle-Mechanismus** (einzige erlaubte Methode):
```swift
CGBeginDisplayConfiguration(&config)
CGConfigureDisplayMirrorOfDisplay(config, id, main)   // "aus"
CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay) // "an"
CGCompleteDisplayConfiguration(config, .forSession)
```

**Display-Klassifikation** (`DisplayManager.isSupportedDisplay`):
- DisplayLink-Adapter: `CGDisplayVendorNumber == 0x17E9` → nicht steuerbar
- USB-C/DP-Alt-Mode (macOS 16+): `AppleATCDPAltModePort.DisplayHints["EDID UUID"]` beginnt mit `String(format: "%04X", vendor) + String(format: "%04X", CFSwapInt16(UInt16(product)))` → nicht steuerbar
- Legacy (macOS < 16): `IODisplayConnect` + Thunderbolt-Vorfahren-Suche → nicht steuerbar

**Nicht steuerbare Displays**: ausgegraut + Suffix " (USB-C)" im Menü, aber sichtbar.

**Lokalisierung**: `Localization.swift` iteriert `Locale.preferredLanguages`, öffnet direkt die `.strings`-Datei via `Bundle.module.path(forResource:ofType:inDirectory:)`. NSBundle-Sprachnegotiierung ist für SPM-Bundles ohne Info.plist fehlerhaft.

**isEnabled**: `CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay`

## Regeln

- **Keine privaten APIs** (`dlopen`, `dlsym`, `CGS*`, `CoreDisplay_*`, SkyLight, etc.) – App-Store-Ziel
- Neue lokalisierbare Strings immer in **alle 19** `.lproj`-Dateien eintragen: ar, da, de, en, es, fi, fr, it, ja, ko, nb, nl, pl, pt-BR, ru, sv, tr, zh-Hans, zh-Hant
- `@MainActor` auf `AppDelegate` und `DisplayManager` – Swift 6 Strict Concurrency aktiv
- Build: `swift build`; kein Xcode-Projekt vorhanden

## macOS 16 (Tahoe / Darwin 25) Besonderheiten

- `IODisplayConnect`-Services mit `DisplayVendorID`-Property existieren nicht mehr
- `CGDisplayIOServicePort` nicht verfügbar
- `CoreDisplay_Display_SetUserEnabled` entfernt
- USB-C-Display-Erkennung läuft über `AppleATCDPAltModePort` (siehe oben)
