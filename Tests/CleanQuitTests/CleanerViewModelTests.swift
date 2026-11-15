import Foundation
import Testing
@testable import CleanQuit

@Test func hotkeyComboDisplayString() {
    let combo = HotkeyCombo.defaultCleanup
    #expect(combo.displayString == "⌥⌘K")
}

@Test func cleanupPresetCodableRoundTrip() throws {
    let preset = CleanupPreset(
        name: "下班清理",
        appKeys: ["com.apple.Safari", "com.microsoft.VSCode"],
        closeFinderWindows: true,
        forceQuit: false
    )

    let data = try JSONEncoder().encode(preset)
    let decoded = try JSONDecoder().decode(CleanupPreset.self, from: data)

    #expect(decoded == preset)
}

@MainActor
@Test func whitelistExcludesAppFromSelectAll() {
    let suiteName = "CleanQuitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let viewModel = CleanerViewModel(defaults: defaults)
    guard let first = viewModel.runningApps.first else {
        return
    }

    viewModel.toggleWhitelist(for: first)
    #expect(viewModel.isWhitelisted(first))

    viewModel.selectAllNonWhitelisted()
    #expect(!viewModel.isSelected(first))
}
