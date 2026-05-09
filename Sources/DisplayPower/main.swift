import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Nur eine Instanz erlauben
let alreadyRunning = NSWorkspace.shared.runningApplications.filter {
    $0.localizedName == ProcessInfo.processInfo.processName &&
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}
guard alreadyRunning.isEmpty else { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate

app.run()
