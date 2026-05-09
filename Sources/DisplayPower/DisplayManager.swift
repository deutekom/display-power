import AppKit
import CoreGraphics
import IOKit

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
        return Array(ids[0..<Int(count)]).filter { CGDisplayIsBuiltin($0) == 0 }
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

    // True = Display ist per USB-DisplayLink angebunden (Synaptics/DisplayLink, Vendor-ID 0x17E9).
    // Solche Displays lassen sich nicht per CGConfigureDisplayMirrorOfDisplay steuern.
    //
    // HDMI über USB-C-Adapter gilt NICHT als DisplayLink und wird korrekt als nativ behandelt.
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
            // DisplayLink-Adapter haben Hersteller-ID 0x17E9 in der Elternkette
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
        // Gespiegelte/deaktivierte Displays erscheinen nicht in NSScreen.screens
        // → Cache liefert den zuletzt bekannten Namen
        return nameCache[id] ?? "Bildschirm \(id)"
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
