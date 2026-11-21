import AppKit
import Foundation
import Testing
@testable import CleanQuit

@Test func hotkeyComboDisplayString() {
    let combo = HotkeyCombo.defaultCleanup
    #expect(combo.displayString == "⌥⌘K")
}

@Test func cleanupPresetCodableRoundTripAndLegacyDecode() throws {
    let preset = CleanupPreset(
        name: "论文学习",
        mode: .keepSelected,
        appKeys: ["com.exafunction.windsurf", "com.google.GeminiMacOS"],
        closeFinderWindows: true,
        forceQuit: false,
        cleanOrphanProcesses: true,
        ejectIdleDiskImages: true
    )

    let data = try JSONEncoder().encode(preset)
    let decoded = try JSONDecoder().decode(CleanupPreset.self, from: data)
    #expect(decoded == preset)

    let legacyJSON = """
    {
        "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "name": "下班清理",
        "appKeys": ["com.microsoft.VSCode"],
        "closeFinderWindows": true,
        "forceQuit": false
    }
    """.data(using: .utf8)!
    let legacyDecoded = try JSONDecoder().decode(CleanupPreset.self, from: legacyJSON)
    #expect(legacyDecoded.mode == .quitSelected)
    #expect(legacyDecoded.cleanOrphanProcesses == true)
    #expect(legacyDecoded.ejectIdleDiskImages == true)
}

@Test func essentialAppPolicyRecognizesCoreBaseApps() {
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "Clash Verge",
        bundleIdentifier: "io.github.clash-verge-rev.clash-verge-rev",
        bundlePath: "/Applications/Clash Verge.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "微信",
        bundleIdentifier: "com.tencent.xinWeChat",
        bundlePath: "/Applications/WeChat.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "QQ",
        bundleIdentifier: "com.tencent.qq",
        bundlePath: "/Applications/QQ.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "Tailscale",
        bundleIdentifier: "io.tailscale.ipn.macsys",
        bundlePath: "/Applications/Tailscale.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "CC Switch",
        bundleIdentifier: "com.ccswitch.desktop",
        bundlePath: "/Applications/CC Switch.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "UU远程",
        bundleIdentifier: "com.netease.uuremote",
        bundlePath: "/Applications/UURemote.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "Mos",
        bundleIdentifier: "com.caldis.Mos",
        bundlePath: "/Applications/Mos.app"
    ))
    #expect(EssentialAppPolicy.isBuiltInEssential(
        name: "WeType",
        bundleIdentifier: "com.tencent.inputmethod.wetype",
        bundlePath: "/Library/Input Methods/WeType.app"
    ))

    #expect(!EssentialAppPolicy.isBuiltInEssential(
        name: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode",
        bundlePath: "/Applications/Visual Studio Code.app"
    ))
    #expect(!EssentialAppPolicy.isBuiltInEssential(
        name: "Devin",
        bundleIdentifier: "com.exafunction.windsurf",
        bundlePath: "/Applications/Devin.app"
    ))
}

@Test func rootAppBundleExtractionAndIdleDMGParsing() throws {
    let nestedHelper = "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/MacOS/WeChatAppEx"
    #expect(ProcessAnalyzerService.extractRootAppBundlePath(from: nestedHelper) == "/Applications/WeChat.app")

    let systemFramework = "/System/Library/Frameworks/WebKit.framework/XPCServices/Test.app/Contents/MacOS/Test"
    #expect(ProcessAnalyzerService.extractRootAppBundlePath(from: systemFramework) == nil)

    let samplePlist: [String: Any] = [
        "images": [
            [
                "image-path": "/Users/test/Downloads/Devin.dmg",
                "system-entities": [
                    ["dev-entry": "/dev/disk4"],
                    ["dev-entry": "/dev/disk4s1", "mount-point": "/Volumes/Devin"]
                ]
            ],
            [
                "image-path": "/Users/test/Downloads/ActiveApp.dmg",
                "system-entities": [
                    ["dev-entry": "/dev/disk5"],
                    ["dev-entry": "/dev/disk5s1", "mount-point": "/Volumes/ActiveApp"]
                ]
            ]
        ]
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: samplePlist, format: .xml, options: 0)
    let idle = DiskImageCleanerService.parseIdleImages(
        fromPlistData: plistData,
        activeExecutablePaths: ["/Volumes/ActiveApp/ActiveApp.app/Contents/MacOS/ActiveApp"]
    )
    #expect(idle.count == 1)
    #expect(idle.first?.mountPoint == "/Volumes/Devin")
    #expect(idle.first?.deviceEntry == "/dev/disk4")
}

@MainActor
@Test func keepModeProtectsEssentialsAndSelectsUnkeptApps() {
    let suiteName = "CleanQuitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let viewModel = CleanerViewModel(defaults: defaults)
    #expect(viewModel.cleanupMode == .keepSelected)
    #expect(viewModel.memorySnapshot.totalBytes > 0)

    let dummyIcon = NSImage(size: NSSize(width: 16, height: 16))
    let devin = AppItem(pid: 1001, name: "Devin", bundleIdentifier: "com.exafunction.windsurf", icon: dummyIcon, memoryBytes: 500_000_000)
    let vscode = AppItem(pid: 1002, name: "Code", bundleIdentifier: "com.microsoft.VSCode", icon: dummyIcon, memoryBytes: 2_000_000_000)
    let wechat = AppItem(pid: 1003, name: "微信", bundleIdentifier: "com.tencent.xinWeChat", icon: dummyIcon, memoryBytes: 800_000_000)

    viewModel.runningApps = [devin, vscode, wechat]
    viewModel.keptAppKeys = ["com.exafunction.windsurf"]

    let quitKeys = Set(viewModel.appsToQuit.map(\.persistenceKey))
    #expect(quitKeys == ["com.microsoft.VSCode"])
    #expect(viewModel.isEssential(wechat))
    #expect(!quitKeys.contains("com.tencent.xinWeChat"))

    viewModel.unlockEssentialCleanup = true
    viewModel.toggleItemInCurrentMode(wechat)
    #expect(Set(viewModel.appsToQuit.map(\.persistenceKey)).contains("com.tencent.xinWeChat"))

    viewModel.unlockEssentialCleanup = false
    #expect(!Set(viewModel.appsToQuit.map(\.persistenceKey)).contains("com.tencent.xinWeChat"))
}

@MainActor
@Test func whitelistExcludesAppFromSelectAll() {
    let suiteName = "CleanQuitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let viewModel = CleanerViewModel(defaults: defaults)
    viewModel.cleanupMode = .quitSelected
    guard let first = viewModel.manageableApps.first else {
        return
    }

    viewModel.toggleWhitelist(for: first)
    #expect(viewModel.isWhitelisted(first))

    viewModel.selectAllNonWhitelisted()
    #expect(!viewModel.isSelected(first))
}

@MainActor
@Test func liveWorkspaceScanCategorizesAppsAccurately() {
    let suiteName = "CleanQuitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let viewModel = CleanerViewModel(defaults: defaults)
    #expect(viewModel.memorySnapshot.totalBytes >= 8 * 1_073_741_824)
    #expect(!viewModel.runningApps.isEmpty)

    for app in viewModel.essentialRunningApps {
        #expect(!viewModel.appsToQuit.contains(app))
    }
}

@MainActor
@Test func modifyingBuiltInAndCustomEssentialListWorks() {
    let suiteName = "CleanQuitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let viewModel = CleanerViewModel(defaults: defaults)
    let dummyIcon = NSImage(size: NSSize(width: 16, height: 16))
    let clash = AppItem(
        pid: 2001,
        name: "Clash Verge",
        bundleIdentifier: "io.github.clash-verge-rev.clash-verge-rev",
        bundlePath: "/Applications/Clash Verge.app",
        icon: dummyIcon
    )
    let zotero = AppItem(
        pid: 2002,
        name: "Zotero",
        bundleIdentifier: "org.zotero.zotero",
        bundlePath: "/Applications/Zotero.app",
        icon: dummyIcon
    )
    viewModel.runningApps = [clash, zotero]

    #expect(viewModel.isEssential(clash))
    #expect(!viewModel.isEssential(zotero))

    viewModel.removeEssentialKey(clash.persistenceKey, displayName: clash.name)
    #expect(!viewModel.isEssential(clash))

    viewModel.addEssentialKey(zotero.persistenceKey, displayName: zotero.name)
    #expect(viewModel.isEssential(zotero))

    viewModel.restoreDefaultEssentials()
    #expect(viewModel.isEssential(clash))
    #expect(viewModel.isEssential(zotero))

    viewModel.removeEssentialKey(zotero.persistenceKey, displayName: zotero.name)
    #expect(!viewModel.isEssential(zotero))
}
