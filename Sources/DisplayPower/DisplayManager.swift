import AppKit
import CoreGraphics
import IOKit

// CGS private API in CoreGraphics – verfügbar auf macOS 10.x bis 16+
// Signatur: (CGDisplayConfigRef, CGDirectDisplayID, Bool) → CGError
// Muss zusammen mit CGBeginDisplayConfiguration / CGCompleteDisplayConfiguration verwendet werden.
private typealias CGSConfigureDisplayEnabledFn = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError

// Ältere Fallback-API (CoreDisplay, macOS 10.x–15.x)
private typealias CoreDisplaySetUserEnabledFn = @convention(c) (CGDirectDisplayID, Bool) -> Void

private let kDisabledIDsKey = "disabledDisplayIDs"

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    // Speichert Namen von Displays, auch wenn diese gerade deaktiviert/gespiegelt sind
    private var nameCache: [CGDirectDisplayID: String] = [:]

    // IDs von via CGSConfigureDisplayEnabled deaktivierten Displays.
    // Diese verschwinden aus CGGetOnlineDisplayList und müssen separat verfolgt werden,
    // damit sie im Menü bleiben und wieder eingeschaltet werden können.
    private var disabledIDs: Set<CGDirectDisplayID> = {
        let stored = UserDefaults.standard.array(forKey: kDisabledIDsKey) as? [Int] ?? []
        return Set(stored.map { CGDirectDisplayID(UInt32($0)) })
    }()

    // Primär: CGSConfigureDisplayEnabled aus CoreGraphics (macOS 16+)
    private let cgsSetEnabled: CGSConfigureDisplayEnabledFn?

    // Fallback: CoreDisplay_Display_SetUserEnabled (macOS 10.x–15.x)
    private let coreDisplaySetEnabled: CoreDisplaySetUserEnabledFn?

    private init() {
        if let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
           let sym = dlsym(h, "CGSConfigureDisplayEnabled") {
            cgsSetEnabled = unsafeBitCast(sym, to: CGSConfigureDisplayEnabledFn.self)
        } else {
            cgsSetEnabled = nil
        }

        // CoreDisplay nur laden wenn CGS nicht verfügbar (älteres macOS)
        if cgsSetEnabled == nil,
           let h = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
           let sym = dlsym(h, "CoreDisplay_Display_SetUserEnabled") {
            coreDisplaySetEnabled = unsafeBitCast(sym, to: CoreDisplaySetUserEnabledFn.self)
        } else {
            coreDisplaySetEnabled = nil
        }

        refreshNameCache()
    }

    // Alle angeschlossenen externen Displays inkl. der von uns deaktivierten.
    // CGGetOnlineDisplayList liefert deaktivierte Displays nicht mehr zurück,
    // deshalb werden die gespeicherten IDs ergänzt.
    func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        var result = Set(Array(ids[0..<Int(count)]).filter { CGDisplayIsBuiltin($0) == 0 })
        result.formUnion(disabledIDs)
        return Array(result)
    }

    // True = Display ist aktiv (nicht deaktiviert oder gespiegelt)
    func isEnabled(_ id: CGDirectDisplayID) -> Bool {
        if cgsSetEnabled != nil || coreDisplaySetEnabled != nil {
            if disabledIDs.contains(id) { return false }
            return CGDisplayIsActive(id) != 0
        }
        return CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
    }

    // True wenn dieses Display gerade der einzige aktive Bildschirm ist.
    // In diesem Fall darf es nicht deaktiviert werden.
    func isLastActiveDisplay(_ id: CGDirectDisplayID) -> Bool {
        var activeIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var activeCount: UInt32 = 0
        CGGetActiveDisplayList(16, &activeIDs, &activeCount)
        let others = Array(activeIDs[0..<Int(activeCount)]).filter { $0 != id }
        return others.isEmpty
    }

    // Display deaktivieren: Fenster wandern auf andere Displays
    func disable(_ id: CGDirectDisplayID) {
        guard !isLastActiveDisplay(id) else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }

        if let fn = cgsSetEnabled {
            _ = fn(config, id, false)
            CGCompleteDisplayConfiguration(config, .forSession)
            disabledIDs.insert(id)
            saveDisabledIDs()
        } else if let fn = coreDisplaySetEnabled {
            CGCancelDisplayConfiguration(config)
            fn(id, false)
        } else {
            // Letzter Fallback: Mirroring (nur HDMI/DP, kein USB-C)
            let main = CGMainDisplayID()
            guard id != main else { CGCancelDisplayConfiguration(config); return }
            CGConfigureDisplayMirrorOfDisplay(config, id, main)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
    }

    // Display aktivieren
    func enable(_ id: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }

        if let fn = cgsSetEnabled {
            _ = fn(config, id, true)
            CGCompleteDisplayConfiguration(config, .forSession)
            disabledIDs.remove(id)
            saveDisabledIDs()
        } else if let fn = coreDisplaySetEnabled {
            CGCancelDisplayConfiguration(config)
            fn(id, true)
        } else {
            CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
    }

    func toggle(_ id: CGDirectDisplayID) {
        isEnabled(id) ? disable(id) : enable(id)
    }

    private func saveDisabledIDs() {
        UserDefaults.standard.set(Array(disabledIDs.map { Int($0) }), forKey: kDisabledIDsKey)
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
        // Displays die wieder online sind, aus der "deaktiviert"-Liste entfernen
        var onlineIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &onlineIDs, &count)
        let online = Set(Array(onlineIDs[0..<Int(count)]))
        let stale = disabledIDs.intersection(online)
        if !stale.isEmpty {
            disabledIDs.subtract(stale)
            saveDisabledIDs()
        }
    }
}
