import AppKit
import Combine
import Foundation
import ServiceManagement

enum AppSortOrder: String, Codable, CaseIterable {
    case memoryDesc
    case nameAsc

    var label: String {
        switch self {
        case .memoryDesc:
            return "按内存"
        case .nameAsc:
            return "按名称"
        }
    }
}

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var runningApps: [AppItem] = []
    @Published var memorySnapshot: SystemMemorySnapshot
    @Published var reclaimableGroups: [ReclaimableProcessGroup] = []
    @Published var selectedReclaimableIDs: Set<String> = []
    @Published var idleDiskImages: [MountedDiskImage] = []

    @Published var cleanupMode: CleanupMode {
        didSet { defaults.set(cleanupMode.rawValue, forKey: Keys.cleanupMode) }
    }
    @Published var sortOrder: AppSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    @Published var keptAppKeys: Set<String> = [] {
        didSet { persistKeptAppKeys() }
    }
    @Published var selectedAppKeys: Set<String> = []

    @Published var whitelistedKeys: Set<String> = [] {
        didSet { persistWhitelist() }
    }
    @Published var removedBuiltInEssentialKeys: Set<String> = [] {
        didSet { persistRemovedBuiltInEssentials() }
    }
    @Published var autoProtectVPNKeywords: Bool {
        didSet { defaults.set(autoProtectVPNKeywords, forKey: Keys.autoProtectVPNKeywords) }
    }

    @Published var unlockEssentialCleanup: Bool = false {
        didSet {
            if !unlockEssentialCleanup {
                forcedEssentialQuitKeys.removeAll()
            }
        }
    }
    @Published var forcedEssentialQuitKeys: Set<String> = []

    @Published var presets: [CleanupPreset] = [] {
        didSet { persistPresets() }
    }

    @Published var closeFinderWindows: Bool {
        didSet { defaults.set(closeFinderWindows, forKey: Keys.closeFinderWindows) }
    }
    @Published var forceQuit: Bool {
        didSet { defaults.set(forceQuit, forKey: Keys.forceQuit) }
    }
    @Published var cleanOrphanProcesses: Bool {
        didSet {
            defaults.set(cleanOrphanProcesses, forKey: Keys.cleanOrphanProcesses)
            syncDefaultOrphanSelections()
        }
    }
    @Published var ejectIdleDiskImages: Bool {
        didSet { defaults.set(ejectIdleDiskImages, forKey: Keys.ejectIdleDiskImages) }
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
    @Published var isCleaning: Bool = false

    private let appCleaner: AppCleanerService
    private let finderService: FinderService
    private let hotkeyService: GlobalHotkeyService
    private let memoryService: SystemMemoryService
    private let diskImageCleaner: DiskImageCleanerService
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let cleanupMode = "cleanquit.cleanupMode"
        static let sortOrder = "cleanquit.sortOrder"
        static let keptAppKeys = "cleanquit.keptAppKeys"
        static let whitelist = "cleanquit.whitelist"
        static let removedBuiltInEssentials = "cleanquit.removedBuiltInEssentials"
        static let autoProtectVPNKeywords = "cleanquit.autoProtectVPNKeywords"
        static let presets = "cleanquit.presets"
        static let seededBuiltInPresets = "cleanquit.seededBuiltInPresets.v2"
        static let closeFinderWindows = "cleanquit.closeFinderWindows"
        static let forceQuit = "cleanquit.forceQuit"
        static let cleanOrphanProcesses = "cleanquit.cleanOrphanProcesses"
        static let ejectIdleDiskImages = "cleanquit.ejectIdleDiskImages"
        static let globalHotkeyEnabled = "cleanquit.globalHotkeyEnabled"
        static let hotkeyCombo = "cleanquit.hotkeyCombo"
    }

    init(
        appCleaner: AppCleanerService = AppCleanerService(),
        finderService: FinderService = FinderService(),
        hotkeyService: GlobalHotkeyService = GlobalHotkeyService(),
        memoryService: SystemMemoryService = SystemMemoryService(),
        diskImageCleaner: DiskImageCleanerService = DiskImageCleanerService(),
        defaults: UserDefaults = .standard
    ) {
        self.appCleaner = appCleaner
        self.finderService = finderService
        self.hotkeyService = hotkeyService
        self.memoryService = memoryService
        self.diskImageCleaner = diskImageCleaner
        self.defaults = defaults
        self.memorySnapshot = memoryService.captureSnapshot()

        if let rawMode = defaults.string(forKey: Keys.cleanupMode),
           let decodedMode = CleanupMode(rawValue: rawMode) {
            self.cleanupMode = decodedMode
        } else {
            self.cleanupMode = .keepSelected
        }

        if let rawSort = defaults.string(forKey: Keys.sortOrder),
           let decodedSort = AppSortOrder(rawValue: rawSort) {
            self.sortOrder = decodedSort
        } else {
            self.sortOrder = .memoryDesc
        }

        if defaults.object(forKey: Keys.closeFinderWindows) == nil {
            self.closeFinderWindows = true
        } else {
            self.closeFinderWindows = defaults.bool(forKey: Keys.closeFinderWindows)
        }

        self.forceQuit = defaults.bool(forKey: Keys.forceQuit)

        if defaults.object(forKey: Keys.cleanOrphanProcesses) == nil {
            self.cleanOrphanProcesses = true
        } else {
            self.cleanOrphanProcesses = defaults.bool(forKey: Keys.cleanOrphanProcesses)
        }

        if defaults.object(forKey: Keys.ejectIdleDiskImages) == nil {
            self.ejectIdleDiskImages = true
        } else {
            self.ejectIdleDiskImages = defaults.bool(forKey: Keys.ejectIdleDiskImages)
        }

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
        if let savedRemoved = defaults.stringArray(forKey: Keys.removedBuiltInEssentials) {
            self.removedBuiltInEssentialKeys = Set(savedRemoved)
        }
        if defaults.object(forKey: Keys.autoProtectVPNKeywords) == nil {
            self.autoProtectVPNKeywords = true
        } else {
            self.autoProtectVPNKeywords = defaults.bool(forKey: Keys.autoProtectVPNKeywords)
        }

        if let savedKept = defaults.stringArray(forKey: Keys.keptAppKeys) {
            self.keptAppKeys = Set(savedKept)
        } else {
            self.keptAppKeys = Set(CleanupPreset.builtInPaperStudy.appKeys)
            persistKeptAppKeys()
        }

        var loadedPresets: [CleanupPreset] = []
        if let presetData = defaults.data(forKey: Keys.presets),
           let decodedPresets = try? JSONDecoder().decode([CleanupPreset].self, from: presetData) {
            loadedPresets = decodedPresets
        }
        if !defaults.bool(forKey: Keys.seededBuiltInPresets) {
            if !loadedPresets.contains(where: { $0.name == CleanupPreset.builtInPaperStudy.name }) {
                loadedPresets.insert(.builtInPaperStudy, at: 0)
            }
            defaults.set(true, forKey: Keys.seededBuiltInPresets)
        }
        self.presets = loadedPresets
        persistPresets()

        refreshApps()
        observeWorkspaceNotifications()
        syncHotkeyRegistration()
        syncLaunchAtLoginState()
    }

    func isBuiltInEssential(_ item: AppItem) -> Bool {
        EssentialAppPolicy.isBuiltInEssential(
            name: item.name,
            bundleIdentifier: item.bundleIdentifier,
            bundlePath: item.bundlePath,
            enableKeywordMatch: autoProtectVPNKeywords
        )
    }

    func isEssential(_ item: AppItem) -> Bool {
        let key = item.persistenceKey
        if whitelistedKeys.contains(key) {
            return true
        }
        if removedBuiltInEssentialKeys.contains(key) {
            return false
        }
        return isBuiltInEssential(item)
    }

    var activeEssentialEntries: [EssentialEntryDisplay] {
        var result: [EssentialEntryDisplay] = []
        var seenKeys: Set<String> = []
        let runningByKey = Dictionary(runningApps.map { ($0.persistenceKey, $0) }, uniquingKeysWith: { first, _ in first })

        for app in essentialRunningApps {
            let key = app.persistenceKey
            seenKeys.insert(key)
            let builtIn = !whitelistedKeys.contains(key) && isBuiltInEssential(app)
            result.append(
                EssentialEntryDisplay(
                    key: key,
                    displayName: app.name,
                    icon: app.icon,
                    isBuiltIn: builtIn || EssentialAppPolicy.defaultEssentialBundleIDs.contains(key),
                    isRunning: true
                )
            )
        }

        for item in EssentialAppPolicy.defaultEssentialCatalog {
            let key = item.bundleID
            guard !seenKeys.contains(key), !removedBuiltInEssentialKeys.contains(key) else { continue }
            let resolved = EssentialAppPolicy.resolveAppDisplay(forKey: key, fallbackName: item.fallbackName)
            guard resolved.installed || whitelistedKeys.contains(key) else { continue }
            seenKeys.insert(key)
            result.append(
                EssentialEntryDisplay(
                    key: key,
                    displayName: resolved.name,
                    icon: resolved.icon,
                    isBuiltIn: true,
                    isRunning: runningByKey[key] != nil
                )
            )
        }

        for key in whitelistedKeys.sorted() where !seenKeys.contains(key) {
            seenKeys.insert(key)
            let resolved = EssentialAppPolicy.resolveAppDisplay(forKey: key)
            result.append(
                EssentialEntryDisplay(
                    key: key,
                    displayName: resolved.name,
                    icon: resolved.icon,
                    isBuiltIn: false,
                    isRunning: runningByKey[key] != nil
                )
            )
        }

        return result
    }

    func isWhitelisted(_ item: AppItem) -> Bool {
        isEssential(item)
    }

    var manageableApps: [AppItem] {
        sortedApps(runningApps.filter { !isEssential($0) })
    }

    var essentialRunningApps: [AppItem] {
        sortedApps(runningApps.filter { isEssential($0) })
    }

    var filteredManageableApps: [AppItem] {
        filterBySearch(manageableApps)
    }

    var filteredEssentialApps: [AppItem] {
        filterBySearch(essentialRunningApps)
    }

    var filteredApps: [AppItem] {
        filteredManageableApps
    }

    var selectedRunningApps: [AppItem] {
        appsToQuit
    }

    var keptRunningApps: [AppItem] {
        manageableApps.filter { keptAppKeys.contains($0.persistenceKey) }
    }

    var appsToQuit: [AppItem] {
        var targets: [AppItem]
        switch cleanupMode {
        case .keepSelected:
            targets = manageableApps.filter { !keptAppKeys.contains($0.persistenceKey) }
        case .quitSelected:
            targets = manageableApps.filter { selectedAppKeys.contains($0.persistenceKey) }
        }
        if unlockEssentialCleanup && !forcedEssentialQuitKeys.isEmpty {
            let forced = essentialRunningApps.filter { forcedEssentialQuitKeys.contains($0.persistenceKey) }
            targets.append(contentsOf: forced)
        }
        return targets
    }

    var selectedReclaimableGroups: [ReclaimableProcessGroup] {
        reclaimableGroups.filter { selectedReclaimableIDs.contains($0.id) }
    }

    var estimatedReclaimBytes: UInt64 {
        let appBytes = appsToQuit.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let groupBytes = selectedReclaimableGroups.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        return appBytes + groupBytes
    }

    var hasPendingActions: Bool {
        !appsToQuit.isEmpty ||
        !selectedReclaimableGroups.isEmpty ||
        (ejectIdleDiskImages && !idleDiskImages.isEmpty) ||
        closeFinderWindows
    }

    func refreshApps() {
        memorySnapshot = memoryService.captureSnapshot()
        let scan = appCleaner.scanWorkspace()
        runningApps = scan.apps
        reclaimableGroups = scan.reclaimableGroups

        let validGroupIDs = Set(reclaimableGroups.map(\.id))
        selectedReclaimableIDs = selectedReclaimableIDs.intersection(validGroupIDs)
        syncDefaultOrphanSelections()

        idleDiskImages = diskImageCleaner.findIdleMountedDiskImages(
            activeExecutablePaths: scan.activeExecutablePaths
        )

        let activeKeys = Set(runningApps.map(\.persistenceKey))
        selectedAppKeys = selectedAppKeys.intersection(activeKeys)
        forcedEssentialQuitKeys = forcedEssentialQuitKeys.intersection(activeKeys)
    }

    func isCheckedInCurrentMode(_ item: AppItem) -> Bool {
        let key = item.persistenceKey
        if isEssential(item) {
            return unlockEssentialCleanup && forcedEssentialQuitKeys.contains(key)
        }
        switch cleanupMode {
        case .keepSelected:
            return keptAppKeys.contains(key)
        case .quitSelected:
            return selectedAppKeys.contains(key)
        }
    }

    func isSelected(_ item: AppItem) -> Bool {
        guard !isEssential(item) else { return false }
        return selectedAppKeys.contains(item.persistenceKey)
    }

    func isKept(_ item: AppItem) -> Bool {
        keptAppKeys.contains(item.persistenceKey)
    }

    func toggleItemInCurrentMode(_ item: AppItem) {
        let key = item.persistenceKey
        if isEssential(item) {
            guard unlockEssentialCleanup else { return }
            if forcedEssentialQuitKeys.contains(key) {
                forcedEssentialQuitKeys.remove(key)
            } else {
                forcedEssentialQuitKeys.insert(key)
            }
            return
        }

        switch cleanupMode {
        case .keepSelected:
            if keptAppKeys.contains(key) {
                keptAppKeys.remove(key)
            } else {
                keptAppKeys.insert(key)
            }
        case .quitSelected:
            if selectedAppKeys.contains(key) {
                selectedAppKeys.remove(key)
            } else {
                selectedAppKeys.insert(key)
            }
        }
    }

    func toggleSelection(for item: AppItem) {
        guard !isEssential(item) else { return }
        let key = item.persistenceKey
        if selectedAppKeys.contains(key) {
            selectedAppKeys.remove(key)
        } else {
            selectedAppKeys.insert(key)
        }
    }

    func selectAllNonWhitelisted() {
        let keys = filteredManageableApps.map(\.persistenceKey)
        selectedAppKeys.formUnion(keys)
    }

    func deselectAll() {
        selectedAppKeys.removeAll()
    }

    func keepAllVisible() {
        let keys = filteredManageableApps.map(\.persistenceKey)
        keptAppKeys.formUnion(keys)
    }

    func clearKeptVisible() {
        let keys = Set(filteredManageableApps.map(\.persistenceKey))
        keptAppKeys.subtract(keys)
    }

    func toggleReclaimableGroup(_ group: ReclaimableProcessGroup) {
        if selectedReclaimableIDs.contains(group.id) {
            selectedReclaimableIDs.remove(group.id)
        } else {
            selectedReclaimableIDs.insert(group.id)
        }
    }

    func toggleWhitelist(for item: AppItem) {
        let key = item.persistenceKey
        if isEssential(item) {
            removeEssentialKey(key, displayName: item.name)
        } else {
            addEssentialKey(key, displayName: item.name)
        }
    }

    func addEssentialKey(_ key: String, displayName: String? = nil) {
        removedBuiltInEssentialKeys.remove(key)
        whitelistedKeys.insert(key)
        selectedAppKeys.remove(key)
        forcedEssentialQuitKeys.remove(key)
        let title = displayName ?? key
        statusMessage = "已将「\(title)」加入基础常驻保护"
    }

    func removeEssentialKey(_ key: String, displayName: String? = nil) {
        whitelistedKeys.remove(key)
        removedBuiltInEssentialKeys.insert(key)
        forcedEssentialQuitKeys.remove(key)
        let title = displayName ?? key
        statusMessage = "已将「\(title)」移出基础常驻保护，现可在主列表中管理"
    }

    func addEssentialFromBundleURL(_ url: URL) {
        let bundle = Bundle(url: url)
        let appName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let key = bundle?.bundleIdentifier ?? appName
        addEssentialKey(key, displayName: appName)
    }

    func restoreDefaultEssentials() {
        removedBuiltInEssentialKeys.removeAll()
        autoProtectVPNKeywords = true
        statusMessage = "已恢复默认基础常驻应用保护列表"
    }

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let keys: [String]
        switch cleanupMode {
        case .keepSelected:
            keys = Array(keptAppKeys).sorted()
        case .quitSelected:
            keys = manageableApps
                .filter { selectedAppKeys.contains($0.persistenceKey) }
                .map(\.persistenceKey)
        }

        let preset = CleanupPreset(
            name: trimmed,
            mode: cleanupMode,
            appKeys: keys,
            closeFinderWindows: closeFinderWindows,
            forceQuit: forceQuit,
            cleanOrphanProcesses: cleanOrphanProcesses,
            ejectIdleDiskImages: ejectIdleDiskImages
        )
        if let existingIdx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[existingIdx] = preset
        } else {
            presets.append(preset)
        }
        statusMessage = "已保存预设「\(trimmed)」（\(cleanupMode.title)）"
    }

    func applyPreset(_ preset: CleanupPreset) {
        cleanupMode = preset.mode
        closeFinderWindows = preset.closeFinderWindows
        forceQuit = preset.forceQuit
        cleanOrphanProcesses = preset.cleanOrphanProcesses
        ejectIdleDiskImages = preset.ejectIdleDiskImages

        switch preset.mode {
        case .keepSelected:
            keptAppKeys = Set(preset.appKeys)
            let keptCount = keptRunningApps.count
            let quitCount = appsToQuit.count
            statusMessage = "已切换预设「\(preset.name)」，保留 \(keptCount) 个应用，待清理 \(quitCount) 个应用"
        case .quitSelected:
            let activeKeys = Set(manageableApps.map(\.persistenceKey))
            let matched = Set(preset.appKeys).intersection(activeKeys)
            selectedAppKeys = matched
            statusMessage = "已应用预设「\(preset.name)」，匹配 \(matched.count) 个待退应用"
        }
    }

    func deletePreset(_ preset: CleanupPreset) {
        presets.removeAll { $0.id == preset.id }
    }

    func runCleanup() {
        guard !isCleaning else { return }
        showAutomationPermissionHelp = false
        isCleaning = true

        let beforeSnapshot = memoryService.captureSnapshot()
        let targets = appsToQuit
        let targetGroups = selectedReclaimableGroups
        let imagesToEject = ejectIdleDiskImages ? idleDiskImages : []
        let preEstimatedBytes = estimatedReclaimBytes

        let appResult = appCleaner.quitApps(targets, force: forceQuit)
        let reclaimedProcCount = appCleaner.reclaimProcessGroups(targetGroups, force: forceQuit)
        let ejectedDMGCount = imagesToEject.isEmpty ? 0 : diskImageCleaner.ejectDiskImages(imagesToEject)

        var parts: [String] = []
        if !targets.isEmpty {
            parts.append("退出 \(appResult.terminatedCount)/\(targets.count) 个应用")
        }
        if !appResult.failedApps.isEmpty {
            parts.append("未响应 \(appResult.failedApps.joined(separator: "、"))")
        }
        if reclaimedProcCount > 0 {
            parts.append("回收 \(reclaimedProcCount) 个后台进程")
        }
        if ejectedDMGCount > 0 {
            parts.append("卸载 \(ejectedDMGCount) 个闲置镜像")
        }

        if closeFinderWindows {
            switch finderService.closeAllWindows() {
            case .success(let count):
                if count > 0 {
                    parts.append("关闭 \(count) 个访达窗口")
                }
            case .failure(let error):
                if case .permissionDenied = error {
                    showAutomationPermissionHelp = true
                }
                parts.append(error.localizedDescription)
            }
        }

        forcedEssentialQuitKeys.removeAll()
        unlockEssentialCleanup = false

        if parts.isEmpty {
            statusMessage = "当前没有待清理的非保留应用或后台进程"
            isCleaning = false
            refreshApps()
            return
        }

        statusMessage = "正在回收内存..." + parts.joined(separator: " · ")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            let sweptResiduals = self.appCleaner.sweepResidualsAfterQuit(
                apps: targets,
                force: self.forceQuit
            )
            if sweptResiduals > 0 {
                parts.append("清扫 \(sweptResiduals) 个附属残留")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.refreshApps()
                let afterSnapshot = self.memorySnapshot
                let usedDrop = beforeSnapshot.usedBytes > afterSnapshot.usedBytes
                    ? (beforeSnapshot.usedBytes - afterSnapshot.usedBytes)
                    : 0
                let swapDrop = beforeSnapshot.swapUsedBytes > afterSnapshot.swapUsedBytes
                    ? (beforeSnapshot.swapUsedBytes - afterSnapshot.swapUsedBytes)
                    : 0
                let measuredDrop = max(usedDrop + swapDrop, preEstimatedBytes > 0 && appResult.terminatedCount > 0 ? min(usedDrop, preEstimatedBytes) : usedDrop)

                if measuredDrop >= 10 * 1_048_576 {
                    parts.append("实测释放 \(MemoryFormatter.string(fromBytes: measuredDrop))")
                } else if preEstimatedBytes >= 10 * 1_048_576 && appResult.terminatedCount > 0 {
                    parts.append("回收进程约 \(MemoryFormatter.string(fromBytes: preEstimatedBytes))")
                }

                self.statusMessage = parts.joined(separator: " · ")
                self.isCleaning = false
            }
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
            statusMessage = "设置开机自启动失败 (\(error.localizedDescription))"
        }
    }

    private func sortedApps(_ list: [AppItem]) -> [AppItem] {
        switch sortOrder {
        case .memoryDesc:
            return list.sorted {
                if $0.memoryBytes != $1.memoryBytes {
                    return $0.memoryBytes > $1.memoryBytes
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .nameAsc:
            return list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func filterBySearch(_ list: [AppItem]) -> [AppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func syncDefaultOrphanSelections() {
        for group in reclaimableGroups where group.kind == .orphanHelper {
            if cleanOrphanProcesses {
                selectedReclaimableIDs.insert(group.id)
            } else {
                selectedReclaimableIDs.remove(group.id)
            }
        }
    }

    private func syncLaunchAtLoginState() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func observeWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: nc.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
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

    private func persistKeptAppKeys() {
        defaults.set(Array(keptAppKeys).sorted(), forKey: Keys.keptAppKeys)
    }

    private func persistWhitelist() {
        defaults.set(Array(whitelistedKeys).sorted(), forKey: Keys.whitelist)
    }

    private func persistRemovedBuiltInEssentials() {
        defaults.set(Array(removedBuiltInEssentialKeys).sorted(), forKey: Keys.removedBuiltInEssentials)
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
