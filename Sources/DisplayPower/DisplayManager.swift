import AppKit
import CoreGraphics
import IOKit

// Signatur der privaten CoreDisplay-Funktion
private typealias SetUserEnabledFn = @convention(c) (CGDirectDisplayID, Bool) -> Void

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    // Speichert Namen von Displays, auch wenn diese gerade deaktiviert/gespiegelt sind
    private var nameCache: [CGDirectDisplayID: String] = [:]

    // Zeiger auf CoreDisplay_Display_SetUserEnabled (privat, aber stabil seit macOS 10.x)
    // Funktioniert für alle Verbindungsarten: HDMI, DisplayPort, USB-C, Thunderbolt
    private let coreDisplaySetEnabled: SetUserEnabledFn?

    private init() {
        if let handle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY
        ), let sym = dlsym(handle, "CoreDisplay_Display_SetUserEnabled") {
            coreDisplaySetEnabled = unsafeBitCast(sym, to: SetUserEnabledFn.self)
        } else {
            coreDisplaySetEnabled = nil
        }
        refreshNameCache()
    }

    // Alle angeschlossenen externen Displays (inkl. deaktivierter)
    func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids[0..<Int(count)]).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    // True = Display ist aktiv (nicht deaktiviert oder gespiegelt)
    func isEnabled(_ id: CGDirectDisplayID) -> Bool {
        if coreDisplaySetEnabled != nil {
            // CoreDisplay: Display ist "an" wenn es in der aktiven Liste ist
            return CGDisplayIsActive(id) != 0
        }
        // Fallback Mirroring: "an" = kein Spiegeln
        return CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
    }

    // Display deaktivieren: Fenster wandern auf andere Displays
    func disable(_ id: CGDirectDisplayID) {
        if let fn = coreDisplaySetEnabled {
            fn(id, false)
            return
        }
        // Fallback: CoreGraphics Mirroring
        let main = CGMainDisplayID()
        guard id != main else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, main)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    // Display aktivieren
    func enable(_ id: CGDirectDisplayID) {
        if let fn = coreDisplaySetEnabled {
            fn(id, true)
            return
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    func toggle(_ id: CGDirectDisplayID) {
        isEnabled(id) ? disable(id) : enable(id)
    }

    // True = USB-DisplayLink-Adapter (Synaptics/DisplayLink, Vendor-ID 0x17E9).
    // Solche Displays lassen sich nicht über diese App steuern.
    func isDisplayLinkDisplay(_ id: CGDirectDisplayID) -> Bool {
        let vendor  = CGDisplayVendorNumber(id)
        let product = CGDisplayModelNumber(id)
        let serial  = CGDisplaySerialNumber(id)

        guard let baseMatch = IOServiceMatching("IODisplayConnect") else { return false }
        let matchDict = baseMatch as NSMutableDictionary
        matchDict["DisplayVendorID"]  = NSNumber(value: vendor)
        matchDict["DisplayProductID"] = NSNumber(value: product)
        if serial != 0 {
            matchDict["DisplaySerialNumber"] = NSNumber(value: serial)
        }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            if let vendorRef = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "idVendor" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            ) as? NSNumber, vendorRef.uint32Value == 0x17E9 {
                return true
            }
        }
        return false
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
        // Deaktivierte Displays erscheinen nicht in NSScreen.screens
        // → Cache liefert den zuletzt bekannten Namen
        return nameCache[id] ?? "\(L("display_fallback")) \(id)"
    }

    // Alle aktuell aktiven externen Displays im Cache speichern
    func refreshNameCache() {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let id = CGDirectDisplayID(num.uint32Value)
                if CGDisplayIsBuiltin(id) == 0 {
                    nameCache[id] = screen.localizedName
                }
            }
        }
    }
}
