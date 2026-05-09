import AppKit
import CoreGraphics
import IOKit

// CGS private API in CoreGraphics – verfügbar auf macOS 10.x bis 16+
// Funktioniert für alle Verbindungsarten: HDMI, DisplayPort, USB-C, Thunderbolt
private typealias CGSConnectionID = UInt32
private typealias CGSConfigureDisplayEnabledFn = @convention(c) (CGSConnectionID, CGDirectDisplayID, Bool) -> Void
private typealias CGSMainConnectionIDFn      = @convention(c) () -> CGSConnectionID

// Ältere Fallback-API (CoreDisplay, macOS 10.x–15.x)
private typealias CoreDisplaySetUserEnabledFn = @convention(c) (CGDirectDisplayID, Bool) -> Void

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    // Speichert Namen von Displays, auch wenn diese gerade deaktiviert/gespiegelt sind
    private var nameCache: [CGDirectDisplayID: String] = [:]

    // Primär: CGSConfigureDisplayEnabled aus CoreGraphics (macOS 16+)
    private let cgsSetEnabled: CGSConfigureDisplayEnabledFn?
    private let cgsConnection: CGSConnectionID

    // Fallback: CoreDisplay_Display_SetUserEnabled (macOS 10.x–15.x)
    private let coreDisplaySetEnabled: CoreDisplaySetUserEnabledFn?

    private init() {
        var cgs: CGSConfigureDisplayEnabledFn? = nil
        var conn: CGSConnectionID = 0

        if let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
           let sym = dlsym(h, "CGSConfigureDisplayEnabled") {
            cgs = unsafeBitCast(sym, to: CGSConfigureDisplayEnabledFn.self)
            if let connSym = dlsym(h, "CGSMainConnectionID") {
                conn = unsafeBitCast(connSym, to: CGSMainConnectionIDFn.self)()
            }
        }
        cgsSetEnabled = cgs
        cgsConnection = conn

        // CoreDisplay nur laden wenn CGS nicht verfügbar (älteres macOS)
        if cgs == nil,
           let h = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
           let sym = dlsym(h, "CoreDisplay_Display_SetUserEnabled") {
            coreDisplaySetEnabled = unsafeBitCast(sym, to: CoreDisplaySetUserEnabledFn.self)
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
        if cgsSetEnabled != nil || coreDisplaySetEnabled != nil {
            return CGDisplayIsActive(id) != 0
        }
        // Fallback Mirroring: "an" = kein Spiegeln
        return CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
    }

    // Display deaktivieren: Fenster wandern auf andere Displays
    func disable(_ id: CGDirectDisplayID) {
        if let fn = cgsSetEnabled, cgsConnection != 0 {
            fn(cgsConnection, id, false)
            return
        }
        if let fn = coreDisplaySetEnabled {
            fn(id, false)
            return
        }
        // Letzter Fallback: CoreGraphics Mirroring
        let main = CGMainDisplayID()
        guard id != main else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, main)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    // Display aktivieren
    func enable(_ id: CGDirectDisplayID) {
        if let fn = cgsSetEnabled, cgsConnection != 0 {
            fn(cgsConnection, id, true)
            return
        }
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
