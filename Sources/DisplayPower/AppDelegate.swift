import AppKit
import CoreGraphics

private let kSelectedDisplayKey = "selectedDisplayID"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated override init() {
        super.init()
    }

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayManager.shared.refreshNameCache()
        setupStatusItem()

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

    // MARK: - Klick-Routing

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseDown:
            showMenu(from: sender)
        case .leftMouseUp:
            toggleSelectedDisplay()
        default:
            break
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

    // MARK: - Menü

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let externals = DisplayManager.shared.externalDisplayIDs()
        let selected = resolvedSelectedID()

        if externals.isEmpty {
            let item = NSMenuItem(title: "Kein externer Bildschirm", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for id in externals {
                let item = NSMenuItem(
                    title: DisplayManager.shared.displayName(id),
                    action: #selector(selectDisplay(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = Int(id)
                item.state = id == selected ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        // Menü direkt unter dem Icon anzeigen
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        let id = CGDirectDisplayID(sender.tag)
        UserDefaults.standard.set(Int(id), forKey: kSelectedDisplayKey)
        updateStatusIcon()
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
