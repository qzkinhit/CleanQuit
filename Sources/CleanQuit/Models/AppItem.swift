import AppKit
import Foundation

/// Represents a currently running user-facing macOS application.
struct AppItem: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage

    var id: pid_t { pid }

    /// Stable key used for persisting whitelist entries and cleanup presets.
    var persistenceKey: String {
        bundleIdentifier ?? name
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.pid == rhs.pid && lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(bundleIdentifier)
    }
}
