import AppKit
import CoreGraphics
import IOKit

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    private var nameCache: [CGDirectDisplayID: String] = [:]
    private static let kPreviousMainKey = "previousMainDisplayID"

    private init() {
        refreshNameCache()
    }

    // Alle externen Displays (builtin ausgenommen).
    func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids[0..<Int(count)]).filter { CGDisplayIsBuiltin($0) == 0 }
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

    enum UnsupportedReason {
        case usbc
        case displayPort
    }

    // True = Display kann via CGConfigureDisplayMirrorOfDisplay gesteuert werden.
    // Unsupportet sind: DisplayLink-USB-Adapter (0x17E9) und USB-C/Thunderbolt-Displays.
    private func unsupportedReasonFor(_ id: CGDirectDisplayID) -> UnsupportedReason? {
        let vendor  = CGDisplayVendorNumber(id)
        let product = CGDisplayModelNumber(id)

        // DisplayLink-USB-Adapter direkt ausschließen
        if vendor == 0x17E9 { return .usbc }

        // macOS 16+: AppleATCDPAltModePort für USB-C/DP-Alt-Mode-Displays
        if isATCDPDisplay(vendor: vendor, product: product) { return .usbc }

        // macOS 16+: AppleATCDPHDMIPort für HDMI-Displays an Apple-Silicon-Macs
        if isHDMIDisplay(vendor: vendor, product: product) { return .displayPort }

        // Legacy (macOS < 16): IODisplayConnect mit Thunderbolt-Eltern-Suche
        if isThunderboltViaLegacyIOKit(vendor: vendor, product: product) { return .usbc }
        return nil
    }

    func unsupportedReason(_ id: CGDirectDisplayID) -> UnsupportedReason? {
        unsupportedReasonFor(id)
    }

    func isSupported(_ id: CGDirectDisplayID) -> Bool {
        unsupportedReason(id) == nil
    }

    // True wenn es außer dem aktuellen Hauptmonitor noch mindestens ein aktives Display gibt
    func hasAlternativeForMain() -> Bool {
        let main = CGMainDisplayID()
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids[0..<Int(count)].contains { $0 != main }
    }

    // Verschiebt alle aktiven Displays so, dass newMainID bei (0,0) landet → wird Hauptmonitor.
    // Relative Abstände zwischen allen Displays bleiben erhalten.
    @discardableResult
    func promoteToMain(_ newMainID: CGDirectDisplayID) -> Bool {
        guard newMainID != CGMainDisplayID() else { return true }
        let target = CGDisplayBounds(newMainID)
        let dxF = -target.origin.x
        let dyF = -target.origin.y

        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for id in ids[0..<Int(count)] {
            let b = CGDisplayBounds(id)
            CGConfigureDisplayOrigin(config, id,
                Int32((b.origin.x + dxF).rounded()),
                Int32((b.origin.y + dyF).rounded()))
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    // Sucht einen anderen aktiven Display (außer excluded) und macht ihn zum Hauptmonitor.
    private func promoteAlternativeToMain(excluding excluded: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        guard let candidate = ids[0..<Int(count)].first(where: { $0 != excluded }) else {
            return false
        }
        return promoteToMain(candidate)
    }

    // macOS 16+: Sucht in AppleATCDPAltModePort nach einem Display anhand
    // der EDID UUID (Format: VVVVPPPP-... mit big-endian product bytes).
    private func isATCDPDisplay(vendor: UInt32, product: UInt32) -> Bool {
        // EDID UUID beginnt mit Vendor (4 hex) + CFSwapInt16(product) (4 hex)
        let vendorHex  = String(format: "%04X", vendor)
        let productBE  = CFSwapInt16(UInt16(product & 0xFFFF))
        let productHex = String(format: "%04X", productBE)
        let uuidPrefix = vendorHex + productHex

        guard let matching = IOServiceMatching("AppleATCDPAltModePort") else { return false }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard let hints = IORegistryEntryCreateCFProperty(
                service, "DisplayHints" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let edidUUID = hints["EDID UUID"] as? String else { continue }
            if edidUUID.hasPrefix(uuidPrefix) { return true }
        }
        return false
    }

    // macOS 16+: Sucht in AppleATCDPHDMIPort nach einem Display anhand der EDID UUID.
    private func isHDMIDisplay(vendor: UInt32, product: UInt32) -> Bool {
        let vendorHex  = String(format: "%04X", vendor)
        let productBE  = CFSwapInt16(UInt16(product & 0xFFFF))
        let productHex = String(format: "%04X", productBE)
        let uuidPrefix = vendorHex + productHex

        guard let matching = IOServiceMatching("AppleATCDPHDMIPort") else { return false }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard let hints = IORegistryEntryCreateCFProperty(
                service, "DisplayHints" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let edidUUID = hints["EDID UUID"] as? String else { continue }
            if edidUUID.hasPrefix(uuidPrefix) { return true }
        }
        return false
    }

    // Legacy für macOS < 16: IODisplayConnect mit Thunderbolt-Vorfahren-Suche.
    private func isThunderboltViaLegacyIOKit(vendor: UInt32, product: UInt32) -> Bool {
        guard let baseMatch = IOServiceMatching("IODisplayConnect") else { return false }
        let matchDict = baseMatch as NSMutableDictionary
        matchDict["DisplayVendorID"]  = NSNumber(value: vendor)
        matchDict["DisplayProductID"] = NSNumber(value: product)

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            if hasThunderboltAncestor(service) { return true }
        }
        return false
    }

    // Traversiert den IOKit-Service-Baum nach oben und sucht nach einem Thunderbolt-Controller.
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
