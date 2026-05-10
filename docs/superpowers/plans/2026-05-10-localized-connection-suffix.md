# Lokalisierter Verbindungs-Suffix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den hardkodierten `" (USB-C)"`-Suffix für nicht steuerbare Displays durch lokalisierte Keys ersetzen und die Infrastruktur für einen separaten `" (DisplayPort)"`-Suffix vorbereiten.

**Architecture:** `DisplayManager` erhält ein neues `UnsupportedReason`-Enum (`.usbc` / `.displayPort`) und eine `unsupportedReason(_:)`-Methode, die `isSupported` intern verwendet. `AppDelegate` wählt anhand des Enum-Falls den richtigen lokalisierten Suffix. Beide neuen Keys werden in allen 19 Sprachen eingetragen — technische Bezeichnungen wie `USB-C` und `DisplayPort` sind sprachunabhängig.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, IOKit, SPM — kein Xcode-Projekt.

---

## Datei-Übersicht

| Datei | Änderung |
|-------|----------|
| `Sources/DisplayPower/DisplayManager.swift` | Neues `UnsupportedReason`-Enum, neue `unsupportedReason(_:)`-Methode, `isSupported` nutzt sie intern |
| `Sources/DisplayPower/AppDelegate.swift` | Schleife in `showMenu` auf `unsupportedReason` umstellen, `" (USB-C)"` entfernen |
| Alle 19 `*.lproj/Localizable.strings` | Neue Keys `usbc_suffix` und `displayport_suffix` |

---

## Task 1: `UnsupportedReason`-Enum und `unsupportedReason(_:)` in DisplayManager

**Files:**
- Modify: `Sources/DisplayPower/DisplayManager.swift`

**Kontext:** `isSupportedDisplay` (privat, ca. Zeile 59) gibt aktuell `Bool` zurück. `isSupported` (öffentlich, ca. Zeile 25) ruft sie auf. Beide bleiben erhalten; `isSupported` wird auf die neue Methode umgestellt.

- [ ] **Step 1: Enum direkt vor `isSupportedDisplay` einfügen**

In `DisplayManager.swift`, direkt vor `private func isSupportedDisplay` (ca. Zeile 59), einfügen:

```swift
enum UnsupportedReason {
    case usbc
    case displayPort
}
```

- [ ] **Step 2: Neue private Methode `unsupportedReasonFor` ergänzen**

Die bestehende `private func isSupportedDisplay` ERSETZEN durch:

```swift
private func unsupportedReasonFor(_ id: CGDirectDisplayID) -> UnsupportedReason? {
    let vendor  = CGDisplayVendorNumber(id)
    let product = CGDisplayModelNumber(id)

    if vendor == 0x17E9 { return .usbc }
    if isATCDPDisplay(vendor: vendor, product: product) { return .usbc }
    if isThunderboltViaLegacyIOKit(vendor: vendor, product: product) { return .usbc }
    return nil
}
```

- [ ] **Step 3: Öffentliche `unsupportedReason`-Methode ergänzen und `isSupported` anpassen**

Die bestehende `func isSupported` (ca. Zeile 25–27):
```swift
func isSupported(_ id: CGDirectDisplayID) -> Bool {
    isSupportedDisplay(id)
}
```

ERSETZEN durch:
```swift
func unsupportedReason(_ id: CGDirectDisplayID) -> UnsupportedReason? {
    unsupportedReasonFor(id)
}

func isSupported(_ id: CGDirectDisplayID) -> Bool {
    unsupportedReason(id) == nil
}
```

- [ ] **Step 4: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!` — keine Fehler.

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplayPower/DisplayManager.swift
git commit -m "refactor: UnsupportedReason-Enum und unsupportedReason(_:) in DisplayManager"
```

---

## Task 2: Neue Lokalisierungs-Keys in alle 19 Sprachen eintragen

**Files:**
- Modify: alle 19 `*.lproj/Localizable.strings`

**Kontext:** Beide Keys sind technische Bezeichnungen (USB-C, DisplayPort) und daher in allen Sprachen identisch. Die Dateien liegen unter `Sources/DisplayPower/Resources/`.

- [ ] **Step 1: Beide Keys ans Ende jeder Strings-Datei anhängen**

Füge am Ende jeder der 19 Dateien (nach dem bestehenden `"left_click_opens_menu"`-Eintrag) zwei neue Zeilen ein:

```
"usbc_suffix" = " (USB-C)";
"displayport_suffix" = " (DisplayPort)";
```

Dieser Text ist für alle 19 Sprachen identisch (ar, da, de, en, es, fi, fr, it, ja, ko, nb, nl, pl, pt-BR, ru, sv, tr, zh-Hans, zh-Hant).

- [ ] **Step 2: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DisplayPower/Resources/
git commit -m "i18n: usbc_suffix und displayport_suffix in alle 19 Sprachen"
```

---

## Task 3: AppDelegate auf `unsupportedReason` umstellen

**Files:**
- Modify: `Sources/DisplayPower/AppDelegate.swift`

**Kontext:** In `showMenu` (ca. Zeile 113–144) gibt es eine `for id in externals`-Schleife. Aktuell:
```swift
let supported = DisplayManager.shared.isSupported(id)
let isOn      = supported && DisplayManager.shared.isEnabled(id)
var title     = DisplayManager.shared.displayName(id)
if !supported {
    title += " (USB-C)"
} else if !isMenuClickMode && !isOn {
    title += L("display_off_suffix")
}
```

- [ ] **Step 1: Schleifenkopf auf `unsupportedReason` umstellen**

Den obigen Block (die ersten 8 Zeilen der Schleife) ersetzen durch:

```swift
let reason    = DisplayManager.shared.unsupportedReason(id)
let supported = reason == nil
let isOn      = supported && DisplayManager.shared.isEnabled(id)
var title     = DisplayManager.shared.displayName(id)
if let r = reason {
    switch r {
    case .usbc:        title += L("usbc_suffix")
    case .displayPort: title += L("displayport_suffix")
    }
} else if !isMenuClickMode && !isOn {
    title += L("display_off_suffix")
}
```

Der Rest der Schleife (`action`, `item`, `item.target`, `item.tag`, `item.isEnabled`, `item.state`, `menu.addItem`) bleibt unverändert — er nutzt weiterhin die `supported`-Variable.

- [ ] **Step 2: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!`

- [ ] **Step 3: Manuell testen**

App starten (nach `swift build` und Neustart):
1. Rechtsklick → nicht steuerbare Displays zeigen `" (USB-C)"` als Suffix (lokalisiert, nicht mehr hardkodiert).
2. Im Normal-Modus: Verhalten aller anderen Menü-Einträge unverändert.
3. Im Menu-Click-Modus: Verhalten unverändert.

- [ ] **Step 4: Commit**

```bash
git add Sources/DisplayPower/AppDelegate.swift
git commit -m "feat: lokalisierte Verbindungs-Suffixe (USB-C / DisplayPort)"
```
