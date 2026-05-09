import Foundation

// Shortcut für NSLocalizedString mit dem SPM-Ressourcen-Bundle
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: Bundle.module, comment: "")
}
