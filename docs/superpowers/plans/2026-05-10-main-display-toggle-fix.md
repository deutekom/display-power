# Hauptmonitor-Toggle-Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wenn der Nutzer den aktuellen Hauptmonitor ausschaltet, wechselt die App automatisch den Hauptmonitor auf ein anderes aktives Display; beim Einschalten wird der ursprüngliche Hauptmonitor wiederhergestellt. Ist kein Wechsel möglich, wird das Menü-Item ausgegraut und mit dem Suffix `" (Primär)"` (lokalisiert) beschriftet.

**Architecture:** `DisplayManager` erhält drei neue Methoden (`promoteToMain`, `promoteAlternativeToMain`, `hasAlternativeForMain`) sowie aktualisierte `disable`/`enable`-Methoden. `AppDelegate.showMenu()` wertet den neuen Zustand aus. Die gemerkte Display-ID wird in `UserDefaults` persistiert. Alle 19 Lokalisierungsdateien erhalten den neuen Schlüssel `primary_suffix`.

**Tech Stack:** Swift 6, CoreGraphics (`CGConfigureDisplayOrigin`, `CGGetActiveDisplayList`), AppKit, UserDefaults

**Branch:** `fix/main-display-toggle` (bereits erstellt)  
**GitHub Issue:** #2

---

## Dateistruktur

| Datei | Änderung |
|---|---|
| `Sources/DisplayPower/DisplayManager.swift` | Neue Methoden + `disable`/`enable` aktualisiert |
| `Sources/DisplayPower/AppDelegate.swift` | `showMenu()` um Primär-Fall erweitert |
| `Sources/DisplayPower/Resources/{19 Sprachen}/Localizable.strings` | Neuer Schlüssel `primary_suffix` |
| `make_dmg.sh` | Neues Build-Script für App-Bundle + DMG |

---

### Task 1: DisplayManager – Neue Hilfsmethoden

**Files:**
- Modify: `Sources/DisplayPower/DisplayManager.swift`

- [ ] **Schritt 1: UserDefaults-Schlüssel als Konstante ergänzen und `hasAlternativeForMain()` hinzufügen**

  Direkt nach `private var nameCache` (Zeile 9) diese Zeile einfügen:

  ```swift
  private static let kPreviousMainKey = "previousMainDisplayID"
  ```

  Dann nach `isSupported()` (nach Zeile 81) diese Methode einfügen:

  ```swift
  // True wenn es außer dem aktuellen Hauptmonitor noch mindestens ein aktives Display gibt
  func hasAlternativeForMain() -> Bool {
      let main = CGMainDisplayID()
      var ids = [CGDirectDisplayID](repeating: 0, count: 16)
      var count: UInt32 = 0
      CGGetActiveDisplayList(16, &ids, &count)
      return ids[0..<Int(count)].contains { $0 != main }
  }
  ```

- [ ] **Schritt 2: `promoteToMain(_:)` und `promoteAlternativeToMain(excluding:)` hinzufügen**

  Direkt nach `hasAlternativeForMain()` einfügen:

  ```swift
  // Verschiebt alle aktiven Displays so, dass newMainID bei (0,0) landet → wird Hauptmonitor.
  // Relative Abstände zwischen allen Displays bleiben erhalten.
  @discardableResult
  func promoteToMain(_ newMainID: CGDirectDisplayID) -> Bool {
      guard newMainID != CGMainDisplayID() else { return true }
      let target = CGDisplayBounds(newMainID)
      let dx = Int32(-target.origin.x)
      let dy = Int32(-target.origin.y)

      var ids = [CGDirectDisplayID](repeating: 0, count: 16)
      var count: UInt32 = 0
      CGGetActiveDisplayList(16, &ids, &count)

      var config: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
      for id in ids[0..<Int(count)] {
          let b = CGDisplayBounds(id)
          CGConfigureDisplayOrigin(config, id, Int32(b.origin.x) + dx, Int32(b.origin.y) + dy)
      }
      return CGCompleteDisplayConfiguration(config, .forSession) == .success
  }

  // Sucht einen anderen aktiven Display (außer excluded) und macht ihn zum Hauptmonitor.
  private func promoteAlternativeToMain(excluding excluded: CGDirectDisplayID) -> Bool {
      var ids = [CGDirectDisplayID](repeating: 0, count: 16)
      var count: UInt32 = 0
      CGGetActiveDisplayList(16, &ids, &count)
      guard let candidate = ids[0..<Int(count)].first(where: { $0 != excluded }) else {
          return false
      }
      return promoteToMain(candidate)
  }
  ```

- [ ] **Schritt 3: Build prüfen**

  ```bash
  swift build 2>&1 | tail -5
  ```

  Erwartet: `Build complete!`

- [ ] **Schritt 4: Commit**

  ```bash
  git add Sources/DisplayPower/DisplayManager.swift
  git commit -m "feat: DisplayManager – promoteToMain und hasAlternativeForMain"
  ```

---

### Task 2: DisplayManager – `disable()` und `enable()` aktualisieren

**Files:**
- Modify: `Sources/DisplayPower/DisplayManager.swift:30-45`

- [ ] **Schritt 1: `disable()` ersetzen**

  Die bestehende `disable()`-Methode (Zeilen 30–37) vollständig ersetzen:

  ```swift
  // Display "ausschalten": als Spiegel des Hauptdisplays konfigurieren.
  // Wenn id der Hauptmonitor ist, wird zuerst ein anderer Display zum Hauptmonitor befördert.
  func disable(_ id: CGDirectDisplayID) {
      if id == CGMainDisplayID() {
          guard promoteAlternativeToMain(excluding: id) else { return }
          UserDefaults.standard.set(Int(id), forKey: Self.kPreviousMainKey)
      }
      let main = CGMainDisplayID()
      var config: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
      CGConfigureDisplayMirrorOfDisplay(config, id, main)
      CGCompleteDisplayConfiguration(config, .forSession)
  }
  ```

- [ ] **Schritt 2: `enable()` ersetzen**

  Die bestehende `enable()`-Methode (Zeilen 40–45) vollständig ersetzen:

  ```swift
  // Display "einschalten": Spiegelung aufheben.
  // War dieses Display vorher der Hauptmonitor, wird es nach 500 ms wiederhergestellt.
  func enable(_ id: CGDirectDisplayID) {
      var config: CGDisplayConfigRef?
      guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
      CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
      CGCompleteDisplayConfiguration(config, .forSession)

      let stored = CGDirectDisplayID(UInt32(
          UserDefaults.standard.integer(forKey: Self.kPreviousMainKey)
      ))
      guard stored == id else { return }
      UserDefaults.standard.removeObject(forKey: Self.kPreviousMainKey)
      Task { @MainActor [self] in
          try? await Task.sleep(nanoseconds: 500_000_000)
          promoteToMain(id)
      }
  }
  ```

- [ ] **Schritt 3: Build prüfen**

  ```bash
  swift build 2>&1 | tail -5
  ```

  Erwartet: `Build complete!`

- [ ] **Schritt 4: Commit**

  ```bash
  git add Sources/DisplayPower/DisplayManager.swift
  git commit -m "fix: Hauptmonitor-Toggle – Wechsel vor disable, Wiederherstellung bei enable"
  ```

---

### Task 3: AppDelegate – Menü-Item für gesperrten Hauptmonitor

**Files:**
- Modify: `Sources/DisplayPower/AppDelegate.swift:116-149`

- [ ] **Schritt 1: Display-Loop in `showMenu()` aktualisieren**

  Den Block im `showMenu()` von Zeile 116 bis 149 (der `for id in externals`-Block) ersetzen:

  ```swift
  for id in externals {
      let reason       = DisplayManager.shared.unsupportedReason(id)
      let supported    = reason == nil
      let isMain       = id == CGMainDisplayID()
      let canToggleOff = !isMain || DisplayManager.shared.hasAlternativeForMain()
      let isOn         = supported && DisplayManager.shared.isEnabled(id)

      // In menu-click-Modus: Hauptmonitor ohne Alternative ist nicht schaltbar
      let isActionable: Bool
      if isMenuClickMode {
          isActionable = supported && (!isOn || canToggleOff)
      } else {
          isActionable = supported
      }

      var title = DisplayManager.shared.displayName(id)
      if let r = reason {
          switch r {
          case .usbc:        title += L("usbc_suffix")
          case .displayPort: title += L("displayport_suffix")
          }
      } else if isMain && isOn && !canToggleOff {
          title += L("primary_suffix")
      } else if !isMenuClickMode && !isOn {
          title += L("display_off_suffix")
      }

      let action: Selector? = isActionable
          ? (isMenuClickMode ? #selector(toggleDisplay(_:)) : #selector(selectDisplay(_:)))
          : nil
      let item = NSMenuItem(
          title:         title,
          action:        action,
          keyEquivalent: ""
      )
      item.target    = isActionable ? self : nil
      item.tag       = Int(id)
      item.isEnabled = isActionable

      if isMenuClickMode {
          item.state = isOn ? .on : .off
      } else {
          item.state = (supported && id == selected) ? .on : .off
      }

      menu.addItem(item)
  }
  ```

- [ ] **Schritt 2: Build prüfen**

  ```bash
  swift build 2>&1 | tail -5
  ```

  Erwartet: `Build complete!`

- [ ] **Schritt 3: Commit**

  ```bash
  git add Sources/DisplayPower/AppDelegate.swift
  git commit -m "feat: Hauptmonitor ohne Alternative im Menü ausgrauen mit (Primär)-Suffix"
  ```

---

### Task 4: Lokalisierung – `primary_suffix` in allen 19 Sprachen

**Files:**
- Modify: alle 19 `Sources/DisplayPower/Resources/*.lproj/Localizable.strings`

- [ ] **Schritt 1: Alle 19 Dateien aktualisieren**

  Jeweils **am Ende** der Datei (nach dem letzten `"displayport_suffix"`-Eintrag) die folgende sprachspezifische Zeile anhängen:

  **ar.lproj:**
  ```
  "primary_suffix" = " (رئيسي)";
  ```

  **da.lproj:**
  ```
  "primary_suffix" = " (Primær)";
  ```

  **de.lproj:**
  ```
  "primary_suffix" = " (Primär)";
  ```

  **en.lproj:**
  ```
  "primary_suffix" = " (Primary)";
  ```

  **es.lproj:**
  ```
  "primary_suffix" = " (Principal)";
  ```

  **fi.lproj:**
  ```
  "primary_suffix" = " (Ensisijainen)";
  ```

  **fr.lproj:**
  ```
  "primary_suffix" = " (Principal)";
  ```

  **it.lproj:**
  ```
  "primary_suffix" = " (Principale)";
  ```

  **ja.lproj:**
  ```
  "primary_suffix" = "（メイン）";
  ```

  **ko.lproj:**
  ```
  "primary_suffix" = " (기본)";
  ```

  **nb.lproj:**
  ```
  "primary_suffix" = " (Primær)";
  ```

  **nl.lproj:**
  ```
  "primary_suffix" = " (Primair)";
  ```

  **pl.lproj:**
  ```
  "primary_suffix" = " (Główny)";
  ```

  **pt-BR.lproj:**
  ```
  "primary_suffix" = " (Principal)";
  ```

  **ru.lproj:**
  ```
  "primary_suffix" = " (Основной)";
  ```

  **sv.lproj:**
  ```
  "primary_suffix" = " (Primär)";
  ```

  **tr.lproj:**
  ```
  "primary_suffix" = " (Birincil)";
  ```

  **zh-Hans.lproj:**
  ```
  "primary_suffix" = "（主屏幕）";
  ```

  **zh-Hant.lproj:**
  ```
  "primary_suffix" = "（主螢幕）";
  ```

- [ ] **Schritt 2: Vollständigkeit prüfen**

  ```bash
  grep -rl "primary_suffix" Sources/DisplayPower/Resources/ | wc -l
  ```

  Erwartet: `19`

- [ ] **Schritt 3: Build prüfen**

  ```bash
  swift build 2>&1 | tail -5
  ```

  Erwartet: `Build complete!`

- [ ] **Schritt 4: Commit**

  ```bash
  git add Sources/DisplayPower/Resources/
  git commit -m "i18n: primary_suffix in alle 19 Sprachen ergänzt"
  ```

---

### Task 5: Release-Script `make_dmg.sh` erstellen

**Files:**
- Create: `make_dmg.sh`

- [ ] **Schritt 1: Script erstellen**

  Neue Datei `make_dmg.sh` im Projektstamm anlegen:

  ```bash
  #!/bin/bash
  set -euo pipefail

  VERSION="${1:-1.0.1}"
  APP="DisplayPower"
  BUILD=".build/release"
  DMG="${APP}-v${VERSION}.dmg"
  BUNDLE="${APP}.app"
  STAGING="$(mktemp -d)"

  echo "→ swift build -c release"
  swift build -c release

  echo "→ App-Bundle zusammenstellen"
  rm -rf "${BUNDLE}"
  mkdir -p "${BUNDLE}/Contents/MacOS"
  mkdir -p "${BUNDLE}/Contents/Resources"
  cp "${BUILD}/${APP}" "${BUNDLE}/Contents/MacOS/"
  cp -R "${BUILD}/${APP}_${APP}.bundle" "${BUNDLE}/Contents/Resources/"

  cat > "${BUNDLE}/Contents/Info.plist" << 'PLIST'
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleExecutable</key>      <string>DisplayPower</string>
      <key>CFBundleIdentifier</key>      <string>com.deutekom.displaypower</string>
      <key>CFBundleName</key>            <string>DisplayPower</string>
      <key>CFBundleVersion</key>         <string>VERSION_PLACEHOLDER</string>
      <key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
      <key>LSUIElement</key>             <true/>
      <key>CFBundlePackageType</key>     <string>APPL</string>
      <key>NSPrincipalClass</key>        <string>NSApplication</string>
      <key>CFBundleSupportedPlatforms</key>
      <array><string>MacOSX</string></array>
  </dict>
  </plist>
  PLIST
  sed -i '' "s/VERSION_PLACEHOLDER/${VERSION}/g" "${BUNDLE}/Contents/Info.plist"

  echo "→ DMG erstellen: ${DMG}"
  cp -R "${BUNDLE}" "${STAGING}/"
  hdiutil create -volname "${APP}" \
      -srcfolder "${STAGING}" \
      -ov -format UDZO \
      "${DMG}"

  rm -rf "${STAGING}" "${BUNDLE}"
  echo "✓ ${DMG} erstellt"
  ```

- [ ] **Schritt 2: Ausführbar machen**

  ```bash
  chmod +x make_dmg.sh
  ```

- [ ] **Schritt 3: Script committen**

  ```bash
  git add make_dmg.sh
  git commit -m "chore: make_dmg.sh für App-Bundle und DMG-Erstellung"
  ```

---

### Task 6: Manueller Test

> Da CoreGraphics-Display-Konfiguration keine Unit-Tests zulässt, wird manuell getestet.

**Vorbedingung:** Mindestens zwei externe Monitore angeschlossen.

- [ ] **Szenario A – Hauptmonitor wechseln + ausschalten:**
  1. `swift run` starten
  2. Menü öffnen → HDMI-Monitor (der gerade Hauptmonitor ist) auswählen/klicken
  3. Erwartung: App wechselt Hauptmonitor auf den anderen Monitor, HDMI-Monitor verschwindet aus der Anzeige
  4. Erwartung: Menüleiste ist auf dem anderen Monitor
  5. Erwartung: Status-Icon zeigt den „ausgeschaltet"-Zustand

- [ ] **Szenario B – Ausgeschalteten Hauptmonitor wieder einschalten:**
  1. Nach Szenario A: HDMI-Monitor im Menü wieder einschalten
  2. Erwartung: HDMI-Monitor erscheint wieder
  3. Erwartung: Nach ~500 ms wechselt Hauptmonitor zurück auf HDMI (Menüleiste wandert zurück)
  4. Erwartung: Status-Icon zeigt den „eingeschaltet"-Zustand

- [ ] **Szenario C – Einziger aktiver Monitor (kein Wechsel möglich):**
  1. Alle anderen Monitore physisch ausschalten (oder testen wenn nur 1 externer aktiv)
  2. Menü öffnen (Menu-Click-Modus aktiviert)
  3. Erwartung: Hauptmonitor-Item zeigt `" (Primär)"` Suffix und ist ausgegraut
  4. Erwartung: Linksklick im normalen Modus tut nichts (silent no-op)

- [ ] **Szenario D – Nicht-Hauptmonitor (normaler Toggle, Regression):**
  1. Nicht-Hauptmonitor aus- und einschalten
  2. Erwartung: Funktioniert wie bisher, kein unerwarteter Hauptmonitor-Wechsel

---

### Task 7: Push, PR, Release v1.0.1

- [ ] **Schritt 1: Branch pushen und PR öffnen**

  ```bash
  git push -u origin fix/main-display-toggle
  gh pr create \
    --title "fix: Hauptmonitor-Toggle – automatischer Wechsel + Fallback-Graying" \
    --body "$(cat <<'EOF'
  Schließt #2.

  ## Änderungen

  - **`DisplayManager`**: `promoteToMain(_:)` verschiebt alle aktiven Displays via `CGConfigureDisplayOrigin`, sodass das Ziel-Display bei (0,0) landet und damit Hauptmonitor wird.
  - **`disable()`**: Wenn das zu deaktivierende Display der Hauptmonitor ist, wird zuerst ein anderer aktiver Monitor per `promoteAlternativeToMain(excluding:)` befördert. Die ursprüngliche Hauptmonitor-ID wird in `UserDefaults` gesichert.
  - **`enable()`**: Nach dem Entfernen des Mirrorings wird geprüft, ob die ID in `UserDefaults` als vorheriger Hauptmonitor gespeichert ist. Falls ja, wird `promoteToMain` nach 500 ms aufgerufen.
  - **`AppDelegate`**: Im Menu-Click-Modus wird das Menü-Item des Hauptmonitors ausgegraut und mit dem Suffix `" (Primär)"` versehen, wenn kein Wechsel möglich ist.
  - **Lokalisierung**: `primary_suffix` in alle 19 Sprachen ergänzt.

  ## Testplan
  - [ ] Hauptmonitor ausschalten → Wechsel klappt, Menüleiste wandert
  - [ ] Wieder einschalten → Hauptmonitor-Rückkehr nach 500 ms
  - [ ] Einziger aktiver Monitor → Item ausgegraut mit `(Primär)`
  - [ ] Nicht-Hauptmonitor → normaler Toggle (Regression)

  🤖 Generated with [Claude Code](https://claude.ai/claude-code)
  EOF
  )" \
    --repo deutekom/display-power
  ```

- [ ] **Schritt 2: DMG bauen**

  ```bash
  bash make_dmg.sh 1.0.1
  ```

  Erwartet: `✓ DisplayPower-v1.0.1.dmg erstellt`

- [ ] **Schritt 3: PR mergen**

  ```bash
  gh pr merge --squash --repo deutekom/display-power
  ```

- [ ] **Schritt 4: Release v1.0.1 erstellen**

  ```bash
  git checkout master && git pull
  git tag v1.0.1
  git push origin v1.0.1

  gh release create v1.0.1 \
    --title "DisplayPower v1.0.1" \
    --notes "$(cat <<'EOF'
  ## Bugfix: Hauptmonitor-Toggle

  Schließt #2.

  ### Was war das Problem?
  Wenn der aktuell als Hauptmonitor konfigurierte Monitor über DisplayPower ausgeschaltet wurde, geschah nichts – macOS erlaubt kein Mirroring des Hauptmonitors.

  ### Was ist jetzt anders?
  - **Automatischer Hauptmonitor-Wechsel:** Beim Ausschalten des Hauptmonitors wechselt DisplayPower automatisch den Hauptmonitor auf ein anderes aktives Display.
  - **Automatische Wiederherstellung:** Beim Einschalten wird der ursprüngliche Hauptmonitor wiederhergestellt.
  - **Fallback:** Ist kein anderer aktiver Monitor vorhanden, wird das Menü-Item ausgegraut und mit dem Hinweis `(Primär)` versehen.

  ### Installation
  1. `DisplayPower-v1.0.1.dmg` herunterladen
  2. DMG öffnen und `DisplayPower.app` in **Programme** ziehen
  3. App starten – bei Gatekeeper-Warnung: **Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen**
  EOF
  )" \
    DisplayPower-v1.0.1.dmg \
    --repo deutekom/display-power
  ```
