# Menu-Click-Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine neue Option „Linksklick öffnet Menü" einführen, die das Klick-Verhalten umschaltet: Statt den ausgewählten Bildschirm direkt per Linksklick zu toggeln, öffnet der Linksklick das Menü, in dem jeder Bildschirm einzeln per Klick (mit Haken = an, kein Haken = aus) gesteuert wird.

**Architecture:** Neue `UserDefaults`-Option `kMenuClickModeKey` (Bool, default `false`). `handleClick` wertet den Modus aus und routet Links­klick entweder zum direkten Toggle oder zum Menü. `showMenu` zeigt im Menu-Click-Modus für jeden Bildschirm den Ein/Aus-Zustand als Haken an und verbindet Klicks mit einem neuen `toggleDisplay`-Action statt `selectDisplay`.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, NSUserDefaults, SPM — kein Xcode-Projekt.

---

## Datei-Übersicht

| Datei | Änderung |
|-------|----------|
| `Sources/DisplayPower/AppDelegate.swift` | Neuer Key, neue Actions, `handleClick` + `showMenu` anpassen |
| `Sources/DisplayPower/Resources/ar.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/da.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/de.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/en.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/es.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/fi.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/fr.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/it.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/ja.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/ko.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/nb.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/nl.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/pl.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/pt-BR.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/ru.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/sv.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/tr.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/zh-Hans.lproj/Localizable.strings` | Neuer String-Key |
| `Sources/DisplayPower/Resources/zh-Hant.lproj/Localizable.strings` | Neuer String-Key |

---

## Task 1: Lokalisierungs-Key in alle 19 Sprachen eintragen

**Files:**
- Modify: alle 19 `*.lproj/Localizable.strings`

- [ ] **Step 1: Key in alle Strings-Dateien ergänzen**

Füge am Ende jeder Datei eine neue Zeile ein (nach `"display_off_suffix"`):

`ar.lproj`:
```
"left_click_opens_menu" = "النقر يفتح القائمة";
```

`da.lproj`:
```
"left_click_opens_menu" = "Klik åbner menuen";
```

`de.lproj`:
```
"left_click_opens_menu" = "Linksklick öffnet Menü";
```

`en.lproj`:
```
"left_click_opens_menu" = "Click opens menu";
```

`es.lproj`:
```
"left_click_opens_menu" = "Clic abre el menú";
```

`fi.lproj`:
```
"left_click_opens_menu" = "Napsautus avaa valikon";
```

`fr.lproj`:
```
"left_click_opens_menu" = "Clic ouvre le menu";
```

`it.lproj`:
```
"left_click_opens_menu" = "Clic apre il menu";
```

`ja.lproj`:
```
"left_click_opens_menu" = "クリックでメニューを開く";
```

`ko.lproj`:
```
"left_click_opens_menu" = "클릭하면 메뉴 열기";
```

`nb.lproj`:
```
"left_click_opens_menu" = "Klikk åpner menyen";
```

`nl.lproj`:
```
"left_click_opens_menu" = "Klik opent menu";
```

`pl.lproj`:
```
"left_click_opens_menu" = "Kliknięcie otwiera menu";
```

`pt-BR.lproj`:
```
"left_click_opens_menu" = "Clique abre o menu";
```

`ru.lproj`:
```
"left_click_opens_menu" = "Клик открывает меню";
```

`sv.lproj`:
```
"left_click_opens_menu" = "Klick öppnar menyn";
```

`tr.lproj`:
```
"left_click_opens_menu" = "Tıklama menüyü açar";
```

`zh-Hans.lproj`:
```
"left_click_opens_menu" = "点击打开菜单";
```

`zh-Hant.lproj`:
```
"left_click_opens_menu" = "點擊開啟選單";
```

- [ ] **Step 2: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!` — keine Fehler.

- [ ] **Step 3: Commit**

```bash
git add Sources/DisplayPower/Resources/
git commit -m "i18n: Lokalisierungskey left_click_opens_menu in alle 19 Sprachen"
```

---

## Task 2: Neuen UserDefaults-Key und Option im Optionen-Untermenü

**Files:**
- Modify: `Sources/DisplayPower/AppDelegate.swift`

**Kontext:** In `AppDelegate.swift` gibt es oben die `private let`-Konstanten (`kSelectedDisplayKey`, `kIconStyleKey`, etc.) und weiter unten die `showMenu`-Methode, die das Optionen-Untermenü (`optionenMenu`) aufbaut. Der Autostart-Eintrag landet bei Zeile ~137.

- [ ] **Step 1: Konstante für neuen Key ergänzen**

In `AppDelegate.swift` die bestehenden `private let`-Konstanten oben (nach `kLaunchAgentLabel`) um eine Zeile erweitern:

```swift
private let kSelectedDisplayKey = "selectedDisplayID"
private let kIconStyleKey       = "iconStyle"
private let kMenuClickModeKey   = "menuClickMode"   // neu
private let kLaunchAgentLabel   = "com.user.displaypower"
```

- [ ] **Step 2: Neue Toggle-Action für die Option**

Direkt nach der bestehenden `toggleAutoStart`-Methode (die bei ca. Zeile 229 endet) eine neue Methode einfügen:

```swift
@objc private func toggleMenuClickMode(_ sender: NSMenuItem) {
    let current = UserDefaults.standard.bool(forKey: kMenuClickModeKey)
    UserDefaults.standard.set(!current, forKey: kMenuClickModeKey)
}
```

- [ ] **Step 3: Option ins Optionen-Untermenü eintragen**

In `showMenu`, direkt nach dem Autostart-Item (`optionenMenu.addItem(autoItem)`) und vor `optionenMenu.addItem(.separator())` einfügen:

```swift
let menuClickItem = NSMenuItem(
    title:         L("left_click_opens_menu"),
    action:        #selector(toggleMenuClickMode(_:)),
    keyEquivalent: ""
)
menuClickItem.target = self
menuClickItem.state  = UserDefaults.standard.bool(forKey: kMenuClickModeKey) ? .on : .off
optionenMenu.addItem(menuClickItem)
```

- [ ] **Step 4: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!` — keine Fehler.

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplayPower/AppDelegate.swift
git commit -m "feat: Option 'Linksklick öffnet Menü' im Optionen-Untermenü"
```

---

## Task 3: handleClick – Linksklick im Menu-Click-Modus ans Menü weiterleiten

**Files:**
- Modify: `Sources/DisplayPower/AppDelegate.swift`

**Kontext:** `handleClick` (ca. Zeile 70) hat zwei Zweige: `.rightMouseDown` → `showMenu`, `.leftMouseUp` → `toggleSelectedDisplay`. Im Menu-Click-Modus soll Linksklick ebenfalls `showMenu` aufrufen.

- [ ] **Step 1: handleClick anpassen**

Den bestehenden `handleClick`-Body ersetzen:

```swift
@objc private func handleClick(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    switch event.type {
    case .rightMouseDown:
        showMenu(from: sender)
    case .leftMouseUp:
        if UserDefaults.standard.bool(forKey: kMenuClickModeKey) {
            showMenu(from: sender)
        } else {
            toggleSelectedDisplay()
        }
    default:
        break
    }
}
```

- [ ] **Step 2: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!` — keine Fehler.

- [ ] **Step 3: Manuell testen (Option deaktiviert)**

App starten. Option **nicht** aktiviert. Linksklick → direkter Toggle des ausgewählten Bildschirms (bisheriges Verhalten unverändert).

- [ ] **Step 4: Manuell testen (Option aktiviert)**

Rechtsklick → Optionen → „Linksklick öffnet Menü" aktivieren (Haken erscheint). Linksklick → Menü öffnet sich.

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplayPower/AppDelegate.swift
git commit -m "feat: Linksklick im Menu-Click-Modus öffnet Menü"
```

---

## Task 4: showMenu – Bildschirm-Items im Menu-Click-Modus als Toggle

**Files:**
- Modify: `Sources/DisplayPower/AppDelegate.swift`

**Kontext:** In `showMenu` (ab ca. Zeile 96) werden die Bildschirm-Items in einer `for id in externals`-Schleife gebaut. Aktuell:
- `item.state = (supported && id == selected) ? .on : .off` → Haken = ausgewählter Bildschirm
- `item.action = #selector(selectDisplay(_:))` → Klick = Bildschirm auswählen
- `title += L("display_off_suffix")` wenn Bildschirm aus

Im Menu-Click-Modus soll gelten:
- `item.state = isOn ? .on : .off` → Haken = Bildschirm ist an
- `item.action = #selector(toggleDisplay(_:))` → Klick = Bildschirm toggeln
- Kein `(aus)`-Suffix nötig (Zustand durch Haken erkennbar)

- [ ] **Step 1: Neue `toggleDisplay`-Action einführen**

Direkt nach `selectDisplay` (ca. Zeile 183) einfügen:

```swift
@objc private func toggleDisplay(_ sender: NSMenuItem) {
    let id = CGDirectDisplayID(UInt32(sender.tag))
    DisplayManager.shared.toggle(id)
    Task { @MainActor [weak self] in
        try await Task.sleep(nanoseconds: 350_000_000)
        self?.updateStatusIcon()
    }
}
```

- [ ] **Step 2: Bildschirm-Schleife in showMenu aufteilen**

Den bestehenden `for id in externals`-Block ersetzen:

```swift
let isMenuClickMode = UserDefaults.standard.bool(forKey: kMenuClickModeKey)

for id in externals {
    let supported = DisplayManager.shared.isSupported(id)
    let isOn      = supported && DisplayManager.shared.isEnabled(id)
    var title     = DisplayManager.shared.displayName(id)
    if !supported {
        title += L("usb_suffix")
    } else if !isMenuClickMode && !isOn {
        title += L("display_off_suffix")
    }

    let action: Selector? = supported
        ? (isMenuClickMode ? #selector(toggleDisplay(_:)) : #selector(selectDisplay(_:)))
        : nil
    let item = NSMenuItem(
        title:         title,
        action:        action,
        keyEquivalent: ""
    )
    item.target    = supported ? self : nil
    item.tag       = Int(id)
    item.isEnabled = supported

    if isMenuClickMode {
        item.state = isOn ? .on : .off
    } else {
        item.state = (supported && id == selected) ? .on : .off
    }

    menu.addItem(item)
}
```

- [ ] **Step 3: Build prüfen**

```bash
cd /Users/deutekom/claude-code/display-power && swift build
```

Erwartetes Ergebnis: `Build complete!` — keine Fehler.

- [ ] **Step 4: Manuell testen – Menu-Click-Modus**

1. Option aktivieren (Rechtsklick → Optionen → „Linksklick öffnet Menü" → Haken setzen).
2. Linksklick → Menü öffnet sich.
3. Bildschirm ist an: Eintrag hat Haken. Bildschirm ist aus: kein Haken, kein `(aus)`-Suffix.
4. Auf einen Bildschirm-Eintrag klicken → Bildschirm schaltet um. Menü beim nächsten Öffnen zeigt aktualisierten Zustand.
5. Mehrere externe Bildschirme: jeder kann unabhängig per Klick getoggled werden.

- [ ] **Step 5: Manuell testen – Normalmodus (Regression)**

1. Option deaktivieren (Haken entfernen).
2. Linksklick → Toggle des ausgewählten Bildschirms, kein Menü.
3. Rechtsklick → Bildschirm-Einträge zeigen Haken beim ausgewählten Display, `(aus)`-Suffix wenn aus.

- [ ] **Step 6: Commit**

```bash
git add Sources/DisplayPower/AppDelegate.swift
git commit -m "feat: Bildschirm-Toggle direkt im Menü im Menu-Click-Modus"
```
