# DisplayPower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS Menu-Bar-App, die per Linksklick einen ausgewählten externen Monitor aktiviert/deaktiviert (via CGDisplayMirror), sodass Fenster neu angeordnet werden.

**Architecture:** Swift Package Manager Executable; AppKit für NSStatusItem und NSPopover; CoreGraphics für Display-Konfiguration. Linksklick = Toggle, Rechtsklick = Einstellungen-Popover mit Monitor-Auswahl.

**Tech Stack:** Swift 6.3, AppKit, CoreGraphics, UserDefaults, SF Symbols, macOS 12+

---

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Package.swift` | SPM-Paketdefinition |
| `Sources/DisplayPower/main.swift` | Einstiegspunkt, NSApplication ohne Dock-Icon |
| `Sources/DisplayPower/DisplayManager.swift` | Alle CoreGraphics-Aufrufe: Auflistung, Toggle, Namens-Cache |
| `Sources/DisplayPower/SettingsViewController.swift` | NSViewController für das Einstellungs-Popover |
| `Sources/DisplayPower/AppDelegate.swift` | NSStatusItem, Klick-Routing, Icon-Zustand |

---

### Task 1: Package.swift und Verzeichnisstruktur

**Files:**
- Create: `Package.swift`
- Create: `Sources/DisplayPower/.gitkeep` (Platzhalter, wird in Task 2 ersetzt)

- [ ] **Schritt 1: Verzeichnisse anlegen**

```bash
mkdir -p Sources/DisplayPower
```

- [ ] **Schritt 2: Package.swift erstellen**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DisplayPower",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "DisplayPower",
            path: "Sources/DisplayPower"
        )
    ]
)
```

- [ ] **Schritt 3: Temporäre main.swift anlegen, damit der Build nicht fehlschlägt**

```swift
// Sources/DisplayPower/main.swift
import AppKit
print("DisplayPower gestartet")
```

- [ ] **Schritt 4: Build prüfen**

```bash
swift build
```

Erwartete Ausgabe: `Build complete!`

- [ ] **Schritt 5: Commit**

```bash
git init
git add Package.swift Sources/
git commit -m "chore: SPM-Projektstruktur aufsetzen"
```

---

### Task 2: DisplayManager

**Files:**
- Create: `Sources/DisplayPower/DisplayManager.swift`

- [ ] **Schritt 1: DisplayManager.swift erstellen**

```swift
import AppKit
import CoreGraphics

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    // Speichert Namen von Displays, auch wenn diese gerade gespiegelt/offline sind
    private var nameCache: [CGDirectDisplayID: String] = [:]

    private init() {
        refreshNameCache()
    }

    // Alle angeschlossenen externen Displays (inkl. gespiegelter)
    func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids[0..<Int(count)]).filter { !CGDisplayIsBuiltin($0) }
    }

    // True = Display ist eigenständig (nicht gespiegelt)
    func isEnabled(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
    }

    // Display deaktivieren: spiegelt den Hauptmonitor → Fenster wandern dorthin
    func disable(_ id: CGDirectDisplayID) {
        let main = CGMainDisplayID()
        guard id != main else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, main)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    // Display aktivieren: Mirroring aufheben → Display wird wieder eigenständig
    func enable(_ id: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    func toggle(_ id: CGDirectDisplayID) {
        isEnabled(id) ? disable(id) : enable(id)
    }

    // Display-Namen: aktive Screens bevorzugt, Cache als Fallback
    func displayName(_ id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == id {
                nameCache[id] = screen.localizedName
                return screen.localizedName
            }
        }
        return nameCache[id] ?? "Bildschirm \(id)"
    }

    // Alle aktuell aktiven externen Displays im Cache speichern
    func refreshNameCache() {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let id = CGDirectDisplayID(num.uint32Value)
                if !CGDisplayIsBuiltin(id) {
                    nameCache[id] = screen.localizedName
                }
            }
        }
    }
}
```

- [ ] **Schritt 2: Build prüfen**

```bash
swift build
```

Erwartete Ausgabe: `Build complete!`

- [ ] **Schritt 3: Commit**

```bash
git add Sources/DisplayPower/DisplayManager.swift
git commit -m "feat: DisplayManager mit CoreGraphics Display-Toggle"
```

---

### Task 3: SettingsViewController

**Files:**
- Create: `Sources/DisplayPower/SettingsViewController.swift`

- [ ] **Schritt 1: SettingsViewController.swift erstellen**

```swift
import AppKit
import CoreGraphics

@MainActor
final class SettingsViewController: NSViewController {
    var onDisplaySelected: ((CGDirectDisplayID) -> Void)?

    private var displays: [(id: CGDirectDisplayID, name: String)] = []
    private var selectedID: CGDirectDisplayID = 0

    override func loadView() {
        view = NSView()
    }

    // Wird vor jedem Öffnen des Popovers aufgerufen
    func update(displays: [(id: CGDirectDisplayID, name: String)], selectedID: CGDirectDisplayID) {
        self.displays = displays
        self.selectedID = selectedID
        if isViewLoaded { rebuildView() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildView()
    }

    private func rebuildView() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            view.widthAnchor.constraint(equalToConstant: 230),
        ])

        let title = NSTextField(labelWithString: "Aktiver Monitor")
        title.font = .boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(title)

        if displays.isEmpty {
            let label = NSTextField(labelWithString: "Kein externer Bildschirm")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        } else {
            for d in displays {
                let btn = NSButton(radioButtonWithTitle: d.name, target: self, action: #selector(radioTapped(_:)))
                btn.tag = Int(d.id)
                btn.state = d.id == selectedID ? .on : .off
                stack.addArrangedSubview(btn)
            }
        }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let quitBtn = NSButton(title: "Beenden", target: NSApp, action: #selector(NSApp.terminate(_:)))
        quitBtn.bezelStyle = .rounded
        stack.addArrangedSubview(quitBtn)

        // Größe für NSPopover berechnen
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    @objc private func radioTapped(_ sender: NSButton) {
        // Alle Radio-Buttons der Stack-View aktualisieren
        if let stack = sender.superview as? NSStackView {
            for case let btn as NSButton in stack.arrangedSubviews {
                if btn.cell?.isKind(of: NSButtonCell.self) == true {
                    btn.state = btn.tag == sender.tag ? .on : .off
                }
            }
        }
        selectedID = CGDirectDisplayID(sender.tag)
        onDisplaySelected?(selectedID)
    }
}
```

- [ ] **Schritt 2: Build prüfen**

```bash
swift build
```

Erwartete Ausgabe: `Build complete!`

- [ ] **Schritt 3: Commit**

```bash
git add Sources/DisplayPower/SettingsViewController.swift
git commit -m "feat: SettingsViewController Popover mit Monitor-Auswahl"
```

---

### Task 4: AppDelegate

**Files:**
- Create: `Sources/DisplayPower/AppDelegate.swift`

- [ ] **Schritt 1: AppDelegate.swift erstellen**

```swift
import AppKit
import CoreGraphics

private let kSelectedDisplayKey = "selectedDisplayID"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsVC: SettingsViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayManager.shared.refreshNameCache()
        setupStatusItem()
        setupPopover()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        updateStatusIcon()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick(_:))
        button.target = self
        // Linksklick UND Rechtsklick abfangen
        button.sendAction(on: [.leftMouseUp, .rightMouseDown])
    }

    private func setupPopover() {
        settingsVC = SettingsViewController()
        settingsVC.onDisplaySelected = { [weak self] id in
            UserDefaults.standard.set(Int(id), forKey: kSelectedDisplayKey)
            self?.updateStatusIcon()
        }
        popover = NSPopover()
        popover.contentViewController = settingsVC
        popover.behavior = .transient
    }

    // MARK: - Klick-Routing

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown {
            togglePopover(from: sender)
        } else {
            toggleSelectedDisplay()
        }
    }

    // MARK: - Display Toggle

    private func toggleSelectedDisplay() {
        guard let id = resolvedSelectedID() else { return }
        DisplayManager.shared.toggle(id)
        // Kurze Verzögerung: CoreGraphics braucht einen Moment für die Konfigurationsänderung
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.updateStatusIcon()
        }
    }

    // MARK: - Popover

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let externals = DisplayManager.shared.externalDisplayIDs()
        let list = externals.map { (id: $0, name: DisplayManager.shared.displayName($0)) }
        let selected = resolvedSelectedID() ?? externals.first ?? 0
        settingsVC.update(displays: list, selectedID: selected)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - Icon

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        guard let id = resolvedSelectedID() else {
            // Kein externer Monitor vorhanden
            button.image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark",
                                   accessibilityDescription: "Kein externer Monitor")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            return
        }

        let isOn = DisplayManager.shared.isEnabled(id)
        button.image = NSImage(systemSymbolName: "display",
                               accessibilityDescription: isOn ? "Monitor an" : "Monitor aus")
        button.image?.isTemplate = true
        // Gedimmt = Monitor deaktiviert (gespiegelt)
        button.contentTintColor = isOn ? nil : .tertiaryLabelColor
    }

    // MARK: - Hilfsmethoden

    // Gibt die gespeicherte Display-ID zurück, falls noch angeschlossen.
    // Fällt auf das erste verfügbare externe Display zurück.
    private func resolvedSelectedID() -> CGDirectDisplayID? {
        let externals = DisplayManager.shared.externalDisplayIDs()
        guard !externals.isEmpty else { return nil }

        let stored = CGDirectDisplayID(UInt32(UserDefaults.standard.integer(forKey: kSelectedDisplayKey)))
        if stored != 0, externals.contains(stored) { return stored }

        // Gespeicherte ID nicht mehr vorhanden → ersten externen Monitor wählen
        let first = externals[0]
        UserDefaults.standard.set(Int(first), forKey: kSelectedDisplayKey)
        return first
    }

    @objc private func displaysChanged() {
        DisplayManager.shared.refreshNameCache()
        updateStatusIcon()
    }
}
```

- [ ] **Schritt 2: Build prüfen**

```bash
swift build
```

Erwartete Ausgabe: `Build complete!`

- [ ] **Schritt 3: Commit**

```bash
git add Sources/DisplayPower/AppDelegate.swift
git commit -m "feat: AppDelegate mit StatusItem, Toggle und Popover"
```

---

### Task 5: main.swift und erster vollständiger Build

**Files:**
- Modify: `Sources/DisplayPower/main.swift`

- [ ] **Schritt 1: main.swift mit finalem Inhalt ersetzen**

```swift
import AppKit

// Kein Dock-Icon, nur Menu-Bar-App
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
```

- [ ] **Schritt 2: Release-Build erstellen**

```bash
swift build -c release
```

Erwartete Ausgabe: `Build complete!`
Binary liegt unter: `.build/release/DisplayPower`

- [ ] **Schritt 3: App starten und manuell testen**

```bash
.build/release/DisplayPower &
```

Prüfen:
- [ ] Icon erscheint oben rechts in der Menüleiste (Display-Symbol)
- [ ] Rechtsklick → Popover öffnet sich mit Liste der externen Monitore
- [ ] Linksklick → Monitor wird deaktiviert (Icon gedimmt, Fenster wandern auf Hauptmonitor)
- [ ] Nochmal Linksklick → Monitor wird wieder aktiviert (Icon normal, Display eigenständig)
- [ ] Im Popover einen anderen Monitor auswählen → gespeichert, Icon aktualisiert sich
- [ ] Popover-Schaltfläche "Beenden" → App beendet sich

- [ ] **Schritt 4: App beenden und Commit**

```bash
# Falls noch läuft: killall DisplayPower
git add Sources/DisplayPower/main.swift
git commit -m "feat: main.swift – App ohne Dock-Icon starten"
```

---

### Task 6: Login-Item-Hinweis (optional, kein Code)

- [ ] **Schritt 1: App beim Login automatisch starten**

Die einfachste Methode für den Nutzer: unter **Systemeinstellungen → Allgemein → Anmeldeobjekte** die Binary `.build/release/DisplayPower` hinzufügen, oder ein Wrapper-Script anlegen.

Alternativ mit `launchctl` (kein Code in der App nötig):

```bash
# LaunchAgent anlegen (Pfad ggf. anpassen)
cat > ~/Library/LaunchAgents/com.user.displaypower.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.displaypower</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/deutekom/claude-code/display-power/.build/release/DisplayPower</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.user.displaypower.plist
```

---

## Selbst-Review Spec-Abdeckung

| Spec-Anforderung | Task |
|---|---|
| Menu-Bar Icon, kein Dock-Icon | Task 5 (`setActivationPolicy(.accessory)`) |
| Linksklick = Toggle ausgewählter Monitor | Task 4 (`handleClick`, `toggleSelectedDisplay`) |
| Rechtsklick = Einstellungen-Popover | Task 4 (`togglePopover`) |
| Monitor-Auswahl im Popover (Radio-Buttons) | Task 3 (`SettingsViewController`) |
| Auswahl in UserDefaults gespeichert | Task 4 (`kSelectedDisplayKey`) |
| Icon: an = normal, aus = gedimmt | Task 4 (`contentTintColor`) |
| Icon: kein externer Monitor = Warnsymbol | Task 4 (`display.trianglebadge.exclamationmark`) |
| CoreGraphics Mirror-API | Task 2 (`DisplayManager`) |
| Namens-Cache für gespiegelte Displays | Task 2 (`nameCache`) |
| Automatisches Update bei Display-Änderung | Task 4 (`displaysChanged`) |
