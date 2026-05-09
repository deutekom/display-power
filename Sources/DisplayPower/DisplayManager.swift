import AppKit
import CoreGraphics
import IOKit

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    private var nameCache: [CGDirectDisplayID: String] = [:]

    private init() {
        refreshNameCache()
    }

    // Nur externe Displays, die via CGConfigureDisplayMirrorOfDisplay steuerbar sind.
    // Gefiltert werden: DisplayLink-USB-Adapter und USB-C/Thunderbolt-Monitore.
    func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids[0..<Int(count)]).filter {
            CGDisplayIsBuiltin($0) == 0 && isSupportedDisplay($0)
        }
    }

    // True = Display ist aktiv (nicht gespiegelt)
    func isEnabled(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
    }

    // Display "ausschalten": als Spiegel des Hauptdisplays konfigurieren.
    // Fenster wandern automatisch auf andere Displays.
    func disable(_ id: CGDirectDisplayID) {
        let main = CGMainDisplayID()
        guard id != main else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, main)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    // Display "einschalten": Spiegelung aufheben.
    func enable(_ id: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    func toggle(_ id: CGDirectDisplayID) {
        isEnabled(id) ? disable(id) : enable(id)
    }

    // True = Display kann via CGConfigureDisplayMirrorOfDisplay gesteuert werden.
    // Unsupportet sind: DisplayLink-USB-Adapter (0x17E9) und USB-C/Thunderbolt-Displays.
    private func isSupportedDisplay(_ id: CGDirectDisplayID) -> Bool {
        let vendor  = CGDisplayVendorNumber(id)
        let product = CGDisplayModelNumber(id)
        let serial  = CGDisplaySerialNumber(id)

        guard let baseMatch = IOServiceMatching("IODisplayConnect") else { return true }
        let matchDict = baseMatch as NSMutableDictionary
        matchDict["DisplayVendorID"]  = NSNumber(value: vendor)
        matchDict["DisplayProductID"] = NSNumber(value: product)
        if serial != 0 {
            matchDict["DisplaySerialNumber"] = NSNumber(value: serial)
        }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return true
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }

            // DisplayLink-USB-Adapter: Synaptics Vendor-ID 0x17E9
            if let v = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "idVendor" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            ) as? NSNumber, v.uint32Value == 0x17E9 {
                return false
            }

            // USB-C/Thunderbolt: Thunderbolt-Controller im IOKit-Pfad vorhanden
            if hasThunderboltAncestor(service) {
                return false
            }
        }
        return true
    }

    // Traversiert den IOKit-Service-Baum nach oben und sucht nach einem
    // Thunderbolt-Controller (AppleThunderboltNHI*). Auf Apple Silicon laufen
    // alle USB-C-Ports über den Thunderbolt-Controller, auch DP-Alt-Mode.
    private func hasThunderboltAncestor(_ service: io_object_t) -> Bool {
        var current: io_object_t = service
        IOObjectRetain(current)
        var depth = 0

        while depth < 25 {
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                IOObjectRelease(current)
                return false
            }
            IOObjectRelease(current)
            current = parent
            depth += 1

            var nameBuf = [CChar](repeating: 0, count: 256)
            if IOObjectGetClass(current, &nameBuf) == KERN_SUCCESS,
               String(cString: nameBuf).contains("Thunderbolt") {
                IOObjectRelease(current)
                return true
            }
        }
        IOObjectRelease(current)
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
        return nameCache[id] ?? "\(L("display_fallback")) \(id)"
    }

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
