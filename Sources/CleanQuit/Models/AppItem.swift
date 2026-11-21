import AppKit
import Foundation

struct AppItem: Identifiable, Hashable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let icon: NSImage
    let isMenuBarAccessory: Bool
    var memoryBytes: UInt64
    var processCount: Int
    var associatedPIDs: Set<pid_t>

    var id: pid_t { pid }

    var persistenceKey: String {
        bundleIdentifier ?? name
    }

    var formattedMemory: String {
        MemoryFormatter.string(fromBytes: memoryBytes)
    }

    init(
        pid: pid_t,
        name: String,
        bundleIdentifier: String?,
        bundlePath: String? = nil,
        icon: NSImage,
        isMenuBarAccessory: Bool = false,
        memoryBytes: UInt64 = 0,
        processCount: Int = 1,
        associatedPIDs: Set<pid_t> = []
    ) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.icon = icon
        self.isMenuBarAccessory = isMenuBarAccessory
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.associatedPIDs = associatedPIDs.isEmpty ? [pid] : associatedPIDs
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.pid == rhs.pid &&
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.memoryBytes == rhs.memoryBytes &&
        lhs.processCount == rhs.processCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(bundleIdentifier)
    }
}
