import Foundation

/// A saved cleanup configuration that can be applied or triggered with one click.
struct CleanupPreset: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var appKeys: [String]
    var closeFinderWindows: Bool
    var forceQuit: Bool

    init(
        id: UUID = UUID(),
        name: String,
        appKeys: [String],
        closeFinderWindows: Bool = true,
        forceQuit: Bool = false
    ) {
        self.id = id
        self.name = name
        self.appKeys = appKeys
        self.closeFinderWindows = closeFinderWindows
        self.forceQuit = forceQuit
    }
}
