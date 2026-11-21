import Foundation

enum CleanupMode: String, Codable, CaseIterable, Equatable {
    case keepSelected
    case quitSelected

    var title: String {
        switch self {
        case .keepSelected:
            return "选保留 · 关其余"
        case .quitSelected:
            return "勾选退出"
        }
    }
}

struct CleanupPreset: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var mode: CleanupMode
    var appKeys: [String]
    var closeFinderWindows: Bool
    var forceQuit: Bool
    var cleanOrphanProcesses: Bool
    var ejectIdleDiskImages: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mode: CleanupMode = .quitSelected,
        appKeys: [String],
        closeFinderWindows: Bool = true,
        forceQuit: Bool = false,
        cleanOrphanProcesses: Bool = true,
        ejectIdleDiskImages: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.appKeys = appKeys
        self.closeFinderWindows = closeFinderWindows
        self.forceQuit = forceQuit
        self.cleanOrphanProcesses = cleanOrphanProcesses
        self.ejectIdleDiskImages = ejectIdleDiskImages
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case appKeys
        case closeFinderWindows
        case forceQuit
        case cleanOrphanProcesses
        case ejectIdleDiskImages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.mode = try container.decodeIfPresent(CleanupMode.self, forKey: .mode) ?? .quitSelected
        self.appKeys = try container.decode([String].self, forKey: .appKeys)
        self.closeFinderWindows = try container.decode(Bool.self, forKey: .closeFinderWindows)
        self.forceQuit = try container.decode(Bool.self, forKey: .forceQuit)
        self.cleanOrphanProcesses = try container.decodeIfPresent(Bool.self, forKey: .cleanOrphanProcesses) ?? true
        self.ejectIdleDiskImages = try container.decodeIfPresent(Bool.self, forKey: .ejectIdleDiskImages) ?? true
    }

    static let builtInPaperStudy = CleanupPreset(
        name: "论文学习",
        mode: .keepSelected,
        appKeys: [
            "com.exafunction.windsurf",
            "com.google.GeminiMacOS",
            "com.apple.Preview",
            "com.google.Chrome",
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "org.zotero.zotero",
            "cn.edu.idea.paper",
            "app.biwrite.desktop",
            "texstudio"
        ],
        closeFinderWindows: true,
        forceQuit: false,
        cleanOrphanProcesses: true,
        ejectIdleDiskImages: true
    )
}
