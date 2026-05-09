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
