import Foundation

/// A random id for this install, sent to the hosted relay so it can rate-limit per install.
/// It names no person or device and resets when the app is deleted.
enum InstallIdentity {
    private static let key = "borderless.install.id"

    static var id: UUID {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key), let value = UUID(uuidString: stored) { return value }
        let value = UUID()
        defaults.set(value.uuidString, forKey: key)
        return value
    }
}
