import AppKit
import CoreGraphics

private let kSelectedDisplayKey = "selectedDisplayID"
private let kIconStyleKey       = "iconStyle"
private let kLaunchAgentLabel   = "com.user.displaypower"

// Verfügbare Icon-Stile mit SF-Symbol-Name und Anzeige-Label
private let kIconStyles: [(symbol: String, label: String)] = [
    ("display",           "Monitor"),
    ("cable.connector",   "Kabel-Stecker (HDMI)"),
]

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

        // Monitor-Auswahl
        let externals = DisplayManager.shared.externalDisplayIDs()
        let selected  = resolvedSelectedID()

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
                item.tag    = Int(id)
                item.state  = id == selected ? .on : .off
                menu.addItem(item)
            }
        }

        // Optionen-Untermenü
        menu.addItem(.separator())
        let optionen     = NSMenuItem(title: "Optionen", action: nil, keyEquivalent: "")
        let optionenMenu = NSMenu(title: "Optionen")
        optionen.submenu = optionenMenu

        // Autostart
        let autoItem = NSMenuItem(
            title:          "Mit Computer starten",
            action:         #selector(toggleAutoStart(_:)),
            keyEquivalent:  ""
        )
        autoItem.target = self
        autoItem.state  = isAutoStartEnabled() ? .on : .off
        optionenMenu.addItem(autoItem)

        optionenMenu.addItem(.separator())

        // Icon-Auswahl
        let currentSymbol = UserDefaults.standard.string(forKey: kIconStyleKey) ?? kIconStyles[0].symbol
        for style in kIconStyles {
            let iconItem = NSMenuItem(
                title:         style.label,
                action:        #selector(selectIconStyle(_:)),
                keyEquivalent: ""
            )
            iconItem.target         = self
            iconItem.representedObject = style.symbol
            iconItem.state          = style.symbol == currentSymbol ? .on : .off
            // Kleines Vorschau-Icon links neben dem Text
            if let img = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil) {
                img.isTemplate   = true
                iconItem.image   = img
            }
            optionenMenu.addItem(iconItem)
        }

        menu.addItem(optionen)

        // Beenden
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        // Menü direkt unter dem Icon anzeigen
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: kSelectedDisplayKey)
        updateStatusIcon()
    }

    @objc private func selectIconStyle(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        UserDefaults.standard.set(symbol, forKey: kIconStyleKey)
        updateStatusIcon()
    }

    // MARK: - Icon

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let symbol = UserDefaults.standard.string(forKey: kIconStyleKey) ?? kIconStyles[0].symbol

        guard let id = resolvedSelectedID() else {
            button.image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark",
                                   accessibilityDescription: "Kein externer Monitor")
            button.image?.isTemplate = true
            button.contentTintColor  = nil
            return
        }

        let isOn = DisplayManager.shared.isEnabled(id)
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: isOn ? "Monitor an" : "Monitor aus")
        button.image?.isTemplate = true
        button.contentTintColor  = isOn ? nil : .tertiaryLabelColor
    }

    // MARK: - Autostart

    private var launchAgentPlistURL: URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        return support.appendingPathComponent("\(kLaunchAgentLabel).plist")
    }

    private func isAutoStartEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        if isAutoStartEnabled() {
            disableAutoStart()
        } else {
            enableAutoStart()
        }
    }

    private func enableAutoStart() {
        // Pfad zum aktuell laufenden Executable
        let execPath = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath().path

        let plist: NSDictionary = [
            "Label":           kLaunchAgentLabel,
            "ProgramArguments": [execPath],
            "RunAtLoad":       true,
            "KeepAlive":       false,
        ]

        try? FileManager.default.createDirectory(
            at: launchAgentPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        plist.write(to: launchAgentPlistURL, atomically: true)

        runLaunchctl(["load", launchAgentPlistURL.path])
    }

    private func disableAutoStart() {
        runLaunchctl(["unload", launchAgentPlistURL.path])
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
    }

    private func runLaunchctl(_ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments     = args
        try? proc.run()
        proc.waitUntilExit()
    }

    // MARK: - Hilfsmethoden

    // Gibt die gespeicherte Display-ID zurück, falls noch angeschlossen.
    // Fällt auf das erste verfügbare externe Display zurück.
    private func resolvedSelectedID() -> CGDirectDisplayID? {
        let externals = DisplayManager.shared.externalDisplayIDs()
        guard !externals.isEmpty else { return nil }

        let stored = CGDirectDisplayID(UInt32(UserDefaults.standard.integer(forKey: kSelectedDisplayKey)))
        if stored != 0, externals.contains(stored) { return stored }

        let first = externals[0]
        UserDefaults.standard.set(Int(first), forKey: kSelectedDisplayKey)
        return first
    }

    @objc private func displaysChanged() {
        DisplayManager.shared.refreshNameCache()
        updateStatusIcon()
    }
}
