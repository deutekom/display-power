import Foundation

// Lädt die korrekte Sprachdatei explizit anhand der Systemeinstellungen.
// NSBundle-Sprachaushandlung liefert bei SPM-Bundles ohne vollständige Info.plist
// manchmal die Fallback-Sprache (en) statt der Systemsprache.
private let _localizedStrings: [String: String] = {
    for language in Locale.preferredLanguages {
        // "de-DE" → versuche erst "de-DE", dann "de"
        let codes = [language, String(language.prefix(2))]
        for code in codes {
            if let path = Bundle.module.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: "\(code).lproj"
            ), let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                return dict
            }
        }
    }
    // Fallback: Deutsch (Standardsprache der App)
    if let path = Bundle.module.path(
        forResource: "Localizable", ofType: "strings",
        inDirectory: "de.lproj"
    ), let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
        return dict
    }
    return [:]
}()

func L(_ key: String) -> String {
    _localizedStrings[key] ?? key
}
