import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var runningApps: [AppItem] = []
    @Published var selectedAppKeys: Set<String> = []
    @Published var whitelistedKeys: Set<String> = [] {
        didSet { persistWhitelist() }
    }
    @Published var presets: [CleanupPreset] = [] {
        didSet { persistPresets() }
    }
    @Published var closeFinderWindows: Bool {
        didSet { defaults.set(closeFinderWindows, forKey: Keys.closeFinderWindows) }
    }
    @Published var forceQuit: Bool {
        didSet { defaults.set(forceQuit, forKey: Keys.forceQuit) }
    }
    @Published var globalHotkeyEnabled: Bool {
        didSet {
            defaults.set(globalHotkeyEnabled, forKey: Keys.globalHotkeyEnabled)
            syncHotkeyRegistration()
        }
    }
    @Published var hotkeyCombo: HotkeyCombo {
        didSet {
            persistHotkeyCombo()
            syncHotkeyRegistration()
        }
    }

    @Published var searchText: String = ""
    @Published var statusMessage: String?
    @Published var showAutomationPermissionHelp: Bool = false
    @Published var launchAtLogin: Bool = false

    private let appCleaner: AppCleanerService
    private let finderService: FinderService
    private let hotkeyService: GlobalHotkeyService
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let whitelist = "cleanquit.whitelist"
        static let presets = "cleanquit.presets"
        static let closeFinderWindows = "cleanquit.closeFinderWindows"
        static let forceQuit = "cleanquit.forceQuit"
        static let globalHotkeyEnabled = "cleanquit.globalHotkeyEnabled"
        static let hotkeyCombo = "cleanquit.hotkeyCombo"
    }

    init(
        appCleaner: AppCleanerService = AppCleanerService(),
        finderService: FinderService = FinderService(),
        hotkeyService: GlobalHotkeyService = GlobalHotkeyService(),
        defaults: UserDefaults = .standard
    ) {
        self.appCleaner = appCleaner
        self.finderService = finderService
        self.hotkeyService = hotkeyService
        self.defaults = defaults

        if defaults.object(forKey: Keys.closeFinderWindows) == nil {
            self.closeFinderWindows = true
        } else {
            self.closeFinderWindows = defaults.bool(forKey: Keys.closeFinderWindows)
        }
        self.forceQuit = defaults.bool(forKey: Keys.forceQuit)

        if defaults.object(forKey: Keys.globalHotkeyEnabled) == nil {
            self.globalHotkeyEnabled = true
        } else {
            self.globalHotkeyEnabled = defaults.bool(forKey: Keys.globalHotkeyEnabled)
        }

        if let data = defaults.data(forKey: Keys.hotkeyCombo),
           let decoded = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkeyCombo = decoded
        } else {
            self.hotkeyCombo = .defaultCleanup
        }

        if let savedWhitelist = defaults.stringArray(forKey: Keys.whitelist) {
            self.whitelistedKeys = Set(savedWhitelist)
        }

        if let presetData = defaults.data(forKey: Keys.presets),
           let decodedPresets = try? JSONDecoder().decode([CleanupPreset].self, from: presetData) {
            self.presets = decodedPresets
        }

        refreshApps()
        observeWorkspaceNotifications()
        syncHotkeyRegistration()
        syncLaunchAtLoginState()
    }

    var filteredApps: [AppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return runningApps }
        return runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedRunningApps: [AppItem] {
        runningApps.filter {
            selectedAppKeys.contains($0.persistenceKey) && !whitelistedKeys.contains($0.persistenceKey)
        }
    }

    func refreshApps() {
        runningApps = appCleaner.fetchRunningApps()
        let activeKeys = Set(runningApps.map(\.persistenceKey))
        selectedAppKeys = selectedAppKeys.intersection(activeKeys)
    }

    func isSelected(_ item: AppItem) -> Bool {
        selectedAppKeys.contains(item.persistenceKey)
    }

    func isWhitelisted(_ item: AppItem) -> Bool {
        whitelistedKeys.contains(item.persistenceKey)
    }

    func toggleSelection(for item: AppItem) {
        guard !isWhitelisted(item) else { return }
        let key = item.persistenceKey
        if selectedAppKeys.contains(key) {
            selectedAppKeys.remove(key)
        } else {
            selectedAppKeys.insert(key)
        }
    }

    func selectAllNonWhitelisted() {
        let keys = filteredApps
            .filter { !whitelistedKeys.contains($0.persistenceKey) }
            .map(\.persistenceKey)
        selectedAppKeys.formUnion(keys)
    }

    func deselectAll() {
        selectedAppKeys.removeAll()
    }

    func toggleWhitelist(for item: AppItem) {
        let key = item.persistenceKey
        if whitelistedKeys.contains(key) {
            whitelistedKeys.remove(key)
        } else {
            whitelistedKeys.insert(key)
            selectedAppKeys.remove(key)
        }
    }

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let keys = selectedRunningApps.map(\.persistenceKey)
        let preset = CleanupPreset(
            name: trimmed,
            appKeys: keys,
            closeFinderWindows: closeFinderWindows,
            forceQuit: forceQuit
        )
        presets.append(preset)
        statusMessage = "已保存预设「\(trimmed)」"
    }

    func applyPreset(_ preset: CleanupPreset) {
        let activeKeys = Set(runningApps.map(\.persistenceKey))
        let matched = Set(preset.appKeys).intersection(activeKeys).subtracting(whitelistedKeys)
        selectedAppKeys = matched
        closeFinderWindows = preset.closeFinderWindows
        forceQuit = preset.forceQuit
        statusMessage = "已应用预设「\(preset.name)」（匹配 \(matched.count) 个运行中的应用）"
    }

    func deletePreset(_ preset: CleanupPreset) {
        presets.removeAll { $0.id == preset.id }
    }

    func runCleanup() {
        showAutomationPermissionHelp = false
        let targets = selectedRunningApps
        let appResult = appCleaner.quitApps(targets, force: forceQuit)

        var parts: [String] = []
        if !targets.isEmpty {
            parts.append("已请求退出 \(appResult.terminatedCount)/\(targets.count) 个应用")
        }
        if !appResult.failedApps.isEmpty {
            parts.append("未退出：\(appResult.failedApps.joined(separator: "、"))")
        }

        if closeFinderWindows {
            switch finderService.closeAllWindows() {
            case .success(let count):
                parts.append(count > 0 ? "已关闭 \(count) 个访达窗口" : "访达无打开窗口")
            case .failure(let error):
                if case .permissionDenied = error {
                    showAutomationPermissionHelp = true
                }
                parts.append(error.localizedDescription)
            }
        }

        if parts.isEmpty {
            statusMessage = "请先勾选要清理的应用，或开启「同时关闭访达窗口」"
        } else {
            statusMessage = parts.joined(separator: " · ")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.refreshApps()
        }
    }

    func closeFinderOnly() {
        showAutomationPermissionHelp = false
        switch finderService.closeAllWindows() {
        case .success(let count):
            statusMessage = count > 0 ? "已关闭 \(count) 个访达窗口" : "访达当前没有打开的窗口"
        case .failure(let error):
            if case .permissionDenied = error {
                showAutomationPermissionHelp = true
            }
            statusMessage = error.localizedDescription
        }
    }

    func openAutomationSettings() {
        finderService.openAutomationSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            statusMessage = "设置开机自启动失败：\(error.localizedDescription)"
        }
    }

    private func syncLaunchAtLoginState() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func observeWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: nc.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshApps()
            }
            .store(in: &cancellables)
    }

    private func syncHotkeyRegistration() {
        if globalHotkeyEnabled {
            hotkeyService.register(combo: hotkeyCombo) { [weak self] in
                Task { @MainActor in
                    self?.runCleanup()
                }
            }
        } else {
            hotkeyService.unregister()
        }
    }

    private func persistWhitelist() {
        defaults.set(Array(whitelistedKeys).sorted(), forKey: Keys.whitelist)
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Keys.presets)
        }
    }

    private func persistHotkeyCombo() {
        if let data = try? JSONEncoder().encode(hotkeyCombo) {
            defaults.set(data, forKey: Keys.hotkeyCombo)
        }
    }
}
