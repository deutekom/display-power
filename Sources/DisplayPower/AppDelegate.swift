import AppKit
import CoreGraphics

private let kSelectedDisplayKey = "selectedDisplayID"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated override init() {
        super.init()
    }

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
        // AppDelegate besitzt settingsVC und lebt für die App-Lifetime;
        // weak self verhindert dennoch theoretische Zyklen bei künftigen Änderungen
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
        Task { @MainActor [weak self] in
            try await Task.sleep(nanoseconds: 350_000_000)
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
        let selected = resolvedSelectedID() ?? externals.first ?? kCGNullDirectDisplay
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
