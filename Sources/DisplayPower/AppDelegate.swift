import AppKit
import CoreGraphics

private let kSelectedDisplayKey = "selectedDisplayID"
private let kIconStyleKey       = "iconStyle"
private let kLaunchAgentLabel   = "com.user.displaypower"

// Kandidaten – zur Laufzeit auf Verfügbarkeit geprüft.
// Labels werden erst beim Menü-Aufbau lokalisiert (L() erfordert Bundle.module).
private let kIconStyleCandidates: [(symbol: String, labelKey: String)] = [
    // Monitor / Display
    ("display",                              "icon_monitor"),
    ("display.2",                            "icon_two_monitors"),
    ("desktopcomputer",                      "icon_desktop_computer"),
    ("tv",                                   "icon_tv"),
    ("tv.fill",                              "icon_tv_filled"),
    ("tv.inset.filled",                      "icon_tv_inset"),
    ("rectangle.inset.filled",               "icon_screen_area"),
    // Kabel / Anschluss / HDMI
    ("hdmi",                                 "icon_hdmi"),
    ("cable.connector",                      "icon_cable_connector"),
    ("cable.connector.horizontal",           "icon_cable_connector_h"),
    ("cable.coaxial",                        "icon_coaxial"),
    ("powerplug",                            "icon_plug"),
    ("powerplug.fill",                       "icon_plug_filled"),
]

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated override init() {
        super.init()
    }

    private var statusItem: NSStatusItem!

    // Nur Symbole die auf diesem System tatsächlich existieren
    private lazy var availableIconStyles: [(symbol: String, labelKey: String)] = {
        kIconStyleCandidates.filter {
            NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil
        }
    }()

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
            let item = NSMenuItem(title: L("no_external_display"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for id in externals {
                let isDisplayLink = DisplayManager.shared.isDisplayLinkDisplay(id)
                let isEnabled     = DisplayManager.shared.isEnabled(id)
                let isLast        = DisplayManager.shared.isLastActiveDisplay(id)

                var title = DisplayManager.shared.displayName(id)
                if isDisplayLink { title += L("usb_suffix") }
                if !isEnabled    { title += L("display_off_suffix") }

                // Deaktivierter letzter Bildschirm: nur auswählen, nicht umschalten
                let canToggle = !isDisplayLink && !(isEnabled && isLast)
                let item = NSMenuItem(
                    title:         title,
                    action:        canToggle ? #selector(selectDisplay(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target    = canToggle ? self : nil
                item.tag       = Int(id)
                item.state     = id == selected ? .on : .off
                item.isEnabled = canToggle
                menu.addItem(item)
            }
        }

        // Optionen-Untermenü
        menu.addItem(.separator())
        let optionen     = NSMenuItem(title: L("options_menu"), action: nil, keyEquivalent: "")
        let optionenMenu = NSMenu(title: L("options_menu"))
        optionen.submenu = optionenMenu

        // Autostart
        let autoItem = NSMenuItem(
            title:          L("launch_at_login"),
            action:         #selector(toggleAutoStart(_:)),
            keyEquivalent:  ""
        )
        autoItem.target = self
        autoItem.state  = isAutoStartEnabled() ? .on : .off
        optionenMenu.addItem(autoItem)

        optionenMenu.addItem(.separator())

        // Icon-Untermenü
        let iconEntry    = NSMenuItem(title: L("icon_menu"), action: nil, keyEquivalent: "")
        let iconMenu     = NSMenu(title: L("icon_menu"))
        iconEntry.submenu = iconMenu
        let currentSymbol = UserDefaults.standard.string(forKey: kIconStyleKey)
            ?? availableIconStyles.first?.symbol ?? "display"
        for style in availableIconStyles {
            let item = NSMenuItem(
                title:         L(style.labelKey),
                action:        #selector(selectIconStyle(_:)),
                keyEquivalent: ""
            )
            item.target            = self
            item.representedObject = style.symbol
            item.state             = style.symbol == currentSymbol ? .on : .off
            if let img = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil) {
                img.isTemplate = true
                item.image     = img
            }
            iconMenu.addItem(item)
        }
        optionenMenu.addItem(iconEntry)

        menu.addItem(optionen)

        // Beenden
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("quit_app"), action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

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

        let symbol = UserDefaults.standard.string(forKey: kIconStyleKey)
            ?? availableIconStyles.first?.symbol ?? "display"

        guard let id = resolvedSelectedID() else {
            button.image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark",
                                   accessibilityDescription: L("no_external_monitor"))
            button.image?.isTemplate = true
            button.contentTintColor  = nil
            return
        }

        let isOn = DisplayManager.shared.isEnabled(id)
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: isOn ? L("display_on") : L("display_off"))
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

    // Gibt die gespeicherte Display-ID zurück, falls noch angeschlossen und kein DisplayLink.
    // Fällt auf das erste verfügbare nicht-DisplayLink-Display zurück.
    private func resolvedSelectedID() -> CGDirectDisplayID? {
        let natives = DisplayManager.shared.externalDisplayIDs()
            .filter { !DisplayManager.shared.isDisplayLinkDisplay($0) }
        guard !natives.isEmpty else { return nil }

        let stored = CGDirectDisplayID(UInt32(UserDefaults.standard.integer(forKey: kSelectedDisplayKey)))
        if stored != 0, natives.contains(stored) { return stored }

        let first = natives[0]
        UserDefaults.standard.set(Int(first), forKey: kSelectedDisplayKey)
        return first
    }

    @objc private func displaysChanged() {
        DisplayManager.shared.refreshNameCache()
        updateStatusIcon()
    }
}
