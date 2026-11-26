import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: CleanerViewModel
    let autoRefreshOnAppear: Bool
    @State private var showingSettings: Bool
    @State private var showingSavePreset = false
    @State private var showDeepCleanDetails: Bool
    @State private var showEssentialApps: Bool
    @State private var newPresetName = ""

    init(
        viewModel: CleanerViewModel,
        autoRefreshOnAppear: Bool = true,
        showingSettings: Bool = false,
        showDeepCleanDetails: Bool = false,
        showEssentialApps: Bool = false
    ) {
        self.viewModel = viewModel
        self.autoRefreshOnAppear = autoRefreshOnAppear
        self._showingSettings = State(initialValue: showingSettings)
        self._showDeepCleanDetails = State(initialValue: showDeepCleanDetails)
        self._showEssentialApps = State(initialValue: showEssentialApps)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsView(viewModel: viewModel, isPresented: $showingSettings)
            } else {
                mainContent
            }
        }
        .frame(width: 416)
        .onAppear {
            if autoRefreshOnAppear {
                viewModel.refreshApps()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 9) {
            headerBar
            memoryCard

            if viewModel.isPlanningSpeedUp || viewModel.speedUpPlan != nil {
                speedUpSection
            }

            modeBar

            if showingSavePreset {
                PresetSheetView(
                    presetName: $newPresetName,
                    mode: viewModel.cleanupMode,
                    targetCount: viewModel.cleanupMode == .keepSelected
                        ? viewModel.keptAppKeys.count
                        : viewModel.appsToQuit.count,
                    onSave: {
                        viewModel.savePreset(name: newPresetName)
                        newPresetName = ""
                        showingSavePreset = false
                    },
                    onCancel: {
                        newPresetName = ""
                        showingSavePreset = false
                    }
                )
            }

            presetBar
            searchAndBatchBar
            appListSection

            if !viewModel.reclaimableGroups.isEmpty || !viewModel.idleDiskImages.isEmpty {
                deepReclaimSection
            }

            essentialAppsSection

            Divider()
            optionsGrid

            if let message = viewModel.statusMessage {
                statusBanner(message)
            }

            actionButton
        }
        .padding(13)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip.fill")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("CleanQuit 智能内存清理")
                    .font(.headline)
                Text("非常驻 \(viewModel.manageableApps.count) 个 · 基础常驻 \(viewModel.essentialRunningApps.count) 个")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.refreshApps()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新内存与运行进程")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置与基础常驻管理")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("退出 CleanQuit")
        }
    }

    private var memoryCard: some View {
        let snap = viewModel.memorySnapshot
        let pressureColor = color(for: snap.pressureLevel)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("物理内存 \(MemoryFormatter.string(fromBytes: snap.usedBytes)) / \(MemoryFormatter.string(fromBytes: snap.totalBytes))")
                    .font(.caption.weight(.semibold))

                Spacer()

                Button {
                    viewModel.planSpeedUp()
                } label: {
                    Label(viewModel.isPlanningSpeedUp ? "检测中" : "一键加速", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isPlanningSpeedUp || viewModel.isRunningSpeedUp)
                .help("检测 2 秒，只回收没有主人且空闲的后台进程，正在使用的应用不动")

                Text(snap.pressureLevel.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pressureColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(pressureColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pressureColor)
                        .frame(width: max(6, geo.size.width * snap.usageRatio))
                }
            }
            .frame(height: 6)

            HStack(spacing: 10) {
                Text("应用 \(MemoryFormatter.string(fromBytes: snap.appMemoryBytes))")
                Text("压缩 \(MemoryFormatter.string(fromBytes: snap.compressedBytes))")
                Spacer()
                Text("交换区 Swap \(MemoryFormatter.string(fromBytes: snap.swapUsedBytes))")
                    .foregroundStyle(snap.swapUsedBytes >= 1_073_741_824 ? pressureColor : .secondary)
                    .fontWeight(snap.swapUsedBytes >= 1_073_741_824 ? .medium : .regular)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modeBar: some View {
        Picker("模式", selection: $viewModel.cleanupMode) {
            ForEach(CleanupMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var presetBar: some View {
        HStack(spacing: 6) {
            Menu {
                if viewModel.presets.isEmpty {
                    Text("暂无预设")
                } else {
                    ForEach(viewModel.presets) { preset in
                        Button {
                            viewModel.applyPreset(preset)
                        } label: {
                            let tag = preset.mode == .keepSelected ? "保留模式" : "退出模式"
                            Text("\(preset.name) · \(tag)")
                        }
                    }
                    Divider()
                    Menu("删除预设") {
                        ForEach(viewModel.presets) { preset in
                            Button(role: .destructive) {
                                viewModel.deletePreset(preset)
                            } label: {
                                Text(preset.name)
                            }
                        }
                    }
                }
            } label: {
                Label("场景预设 (\(viewModel.presets.count))", systemImage: "bookmark.fill")
                    .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            Button {
                showingSavePreset.toggle()
            } label: {
                Label("存为预设", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.cleanupMode == .quitSelected && viewModel.appsToQuit.isEmpty)

            Spacer()

            Button {
                viewModel.closeFinderOnly()
            } label: {
                Label("仅关访达", systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("立即关闭所有访达窗口，不退出其他应用")
        }
    }

    private var searchAndBatchBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    viewModel.cleanupMode == .keepSelected ? "搜索并勾选要保留的应用..." : "搜索要退出的应用...",
                    text: $viewModel.searchText
                )
                .textFieldStyle(.plain)
                .font(.caption)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button {
                viewModel.sortOrder = viewModel.sortOrder == .memoryDesc ? .nameAsc : .memoryDesc
            } label: {
                Text(viewModel.sortOrder.label)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("切换按内存占用排序或按应用名称排序")

            if viewModel.cleanupMode == .keepSelected {
                Button("全保") {
                    viewModel.keepAllVisible()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("全清") {
                    viewModel.clearKeptVisible()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("全选") {
                    viewModel.selectAllNonWhitelisted()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("清空") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.selectedAppKeys.isEmpty)
            }
        }
    }

    private var appListSection: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if viewModel.filteredManageableApps.isEmpty {
                    Text(viewModel.manageableApps.isEmpty ? "当前没有运行中的非常驻应用" : "没有匹配的应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    ForEach(viewModel.filteredManageableApps) { app in
                        AppRowView(
                            app: app,
                            mode: viewModel.cleanupMode,
                            isChecked: viewModel.isCheckedInCurrentMode(app),
                            isEssential: false,
                            isEssentialUnlocked: false,
                            onToggleCheck: { viewModel.toggleItemInCurrentMode(app) },
                            onToggleEssential: { viewModel.toggleWhitelist(for: app) }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 196)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var speedUpSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isPlanningSpeedUp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在检测进程活动（\(Int(CleanerViewModel.speedUpSampleSeconds)) 秒）…")
                        .font(.caption)
                }
            } else if let plan = viewModel.speedUpPlan {
                let chosen = viewModel.selectedSpeedUpItems
                let chosenBytes = chosen.reduce(UInt64(0)) { $0 + $1.memoryBytes }

                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    Text(plan.items.isEmpty ? "没有可安全回收的进程" : "加速方案 · 可回收 \(plan.items.count) 项")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if chosenBytes > 0 {
                        Text("已选 \(MemoryFormatter.string(fromBytes: chosenBytes))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                ForEach(plan.items) { item in
                    let checked = viewModel.selectedSpeedUpIDs.contains(item.id)
                    HStack(spacing: 7) {
                        Button {
                            viewModel.toggleSpeedUpItem(item)
                        } label: {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? Color.orange : .secondary)
                        }
                        .buttonStyle(.borderless)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(item.title).font(.caption).lineLimit(1)
                                Text(item.kind.badgeText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(item.formattedMemory)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if !plan.protectedApps.isEmpty {
                    let names = plan.protectedApps.prefix(6)
                        .map { "\($0.name)（\($0.reason)）" }
                        .joined(separator: "、")
                    Text("不会动：" + names + (plan.protectedApps.count > 6 ? " 等 \(plan.protectedApps.count) 个" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("取消") { viewModel.cancelSpeedUp() }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button(viewModel.isRunningSpeedUp ? "正在加速…" : "执行加速（\(chosen.count) 项）") {
                        viewModel.runSpeedUp()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(chosen.isEmpty || viewModel.isRunningSpeedUp)
                }
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var deepReclaimSection: some View {
        let selectedBytes = viewModel.selectedReclaimableGroups.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let dmgCount = viewModel.idleDiskImages.count

        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDeepCleanDetails.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDeepCleanDetails ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("深度回收发现 \(viewModel.reclaimableGroups.count) 组后台进程")
                        .font(.caption.weight(.medium))
                    if dmgCount > 0 {
                        Text("· \(dmgCount) 个闲置镜像")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedBytes > 0 {
                        Text("已选 \(MemoryFormatter.string(fromBytes: selectedBytes))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDeepCleanDetails {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.reclaimableGroups) { group in
                        let checked = viewModel.selectedReclaimableIDs.contains(group.id)
                        HStack(spacing: 7) {
                            Button {
                                viewModel.toggleReclaimableGroup(group)
                            } label: {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(checked ? Color.orange : .secondary)
                            }
                            .buttonStyle(.borderless)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(group.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(group.kind.badgeText)
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                Text(group.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(group.formattedMemory)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if !viewModel.idleDiskImages.isEmpty {
                        let names = viewModel.idleDiskImages.map(\.displayName).joined(separator: "、")
                        Text("闲置安装包镜像 (\(names)) 将随清理自动弹出")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var essentialAppsSection: some View {
        let totalEssentialBytes = viewModel.essentialRunningApps.reduce(UInt64(0)) { $0 + $1.memoryBytes }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showEssentialApps.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showEssentialApps ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "shield.checkered")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("基础常驻保护中 (\(viewModel.essentialRunningApps.count) 个)")
                            .font(.caption.weight(.medium))
                        Text(MemoryFormatter.string(fromBytes: totalEssentialBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showingSettings = true
                } label: {
                    Text("修改名单")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if showEssentialApps {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Toggle(isOn: $viewModel.unlockEssentialCleanup) {
                            Text("临时解锁勾选退出")
                                .font(.caption2)
                                .foregroundStyle(viewModel.unlockEssentialCleanup ? .red : .secondary)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        Text("点右侧「移出」可解除常驻")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.filteredEssentialApps) { app in
                                AppRowView(
                                    app: app,
                                    mode: .quitSelected,
                                    isChecked: viewModel.isCheckedInCurrentMode(app),
                                    isEssential: true,
                                    isEssentialUnlocked: viewModel.unlockEssentialCleanup,
                                    onToggleCheck: { viewModel.toggleItemInCurrentMode(app) },
                                    onToggleEssential: { viewModel.toggleWhitelist(for: app) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 148)
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var optionsGrid: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Toggle("关闭访达窗口", isOn: $viewModel.closeFinderWindows)
                Toggle("清退残留进程", isOn: $viewModel.cleanOrphanProcesses)
                Spacer()
            }
            HStack(spacing: 12) {
                Toggle("弹出闲置 DMG", isOn: $viewModel.ejectIdleDiskImages)
                Toggle(isOn: $viewModel.forceQuit) {
                    Text("强制退出 (跳过保存提示)")
                        .foregroundStyle(viewModel.forceQuit ? .orange : .primary)
                }
                Spacer()
            }
        }
        .font(.caption)
        .toggleStyle(.checkbox)
    }

    private func statusBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.showAutomationPermissionHelp {
                Button("打开系统设置 隐私与安全性 自动化") {
                    viewModel.openAutomationSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionButton: some View {
        let quitCount = viewModel.appsToQuit.count
        let procGroupCount = viewModel.selectedReclaimableGroups.count
        let estBytes = viewModel.estimatedReclaimBytes
        let estStr = estBytes >= 5 * 1_048_576 ? " · 预计释放 \(MemoryFormatter.string(fromBytes: estBytes))" : ""

        let title: String = {
            if viewModel.isCleaning {
                return "正在执行清理与内存回收..."
            }
            if quitCount > 0 {
                if viewModel.cleanupMode == .keepSelected {
                    return "保留 \(viewModel.keptRunningApps.count) 个 · 关闭其余 \(quitCount) 个应用\(estStr)"
                } else {
                    return "一键退出 \(quitCount) 个应用\(estStr)"
                }
            }
            if procGroupCount > 0 {
                return "一键回收 \(procGroupCount) 组后台进程\(estStr)"
            }
            if viewModel.ejectIdleDiskImages && !viewModel.idleDiskImages.isEmpty {
                return "弹出 \(viewModel.idleDiskImages.count) 个闲置镜像" + (viewModel.closeFinderWindows ? " + 关访达" : "")
            }
            if viewModel.closeFinderWindows {
                return "当前无待退应用 · 仅关闭访达窗口"
            }
            return "当前无待清理项"
        }()

        let isEnabled = viewModel.hasPendingActions && !viewModel.isCleaning
        let bgColor: Color = !isEnabled
            ? Color.secondary.opacity(0.25)
            : (viewModel.forceQuit ? .orange : .accentColor)

        return Button {
            viewModel.runCleanup()
        } label: {
            HStack(spacing: 6) {
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if viewModel.globalHotkeyEnabled && !viewModel.isCleaning {
                    Text(viewModel.hotkeyCombo.displayString)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func color(for pressure: MemoryPressureLevel) -> Color {
        switch pressure {
        case .normal:
            return .green
        case .elevated:
            return .orange
        case .critical:
            return .red
        }
    }
}

private struct AppRowView: View {
    let app: AppItem
    let mode: CleanupMode
    let isChecked: Bool
    let isEssential: Bool
    let isEssentialUnlocked: Bool
    let onToggleCheck: () -> Void
    let onToggleEssential: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if !isEssential || isEssentialUnlocked {
                    onToggleCheck()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: checkIconName)
                        .foregroundStyle(checkIconColor)
                        .font(.body)

                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(app.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            if app.isMenuBarAccessory {
                                Text("菜单栏")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }

                        Text("\(app.formattedMemory) · \(app.processCount) 个进程")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusTag
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isEssential || isEssentialUnlocked)

            if isEssential {
                Button(action: onToggleEssential) {
                    Text("移出")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("移出基础常驻保护名单，恢复为普通可管理应用")
            } else {
                Button(action: onToggleEssential) {
                    HStack(spacing: 2) {
                        Image(systemName: "shield")
                        Text("常驻")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("加入基础常驻保护名单（默认永不清理）")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var checkIconName: String {
        if isEssential && !isEssentialUnlocked {
            return "lock.shield.fill"
        }
        if mode == .keepSelected && !isEssential {
            return isChecked ? "checkmark.circle.fill" : "minus.circle"
        }
        return isChecked ? "checkmark.circle.fill" : "circle"
    }

    private var checkIconColor: Color {
        if isEssential && !isEssentialUnlocked {
            return .green
        }
        if mode == .keepSelected && !isEssential {
            return isChecked ? .green : .orange
        }
        return isChecked ? (isEssential ? .red : .accentColor) : .secondary
    }

    @ViewBuilder
    private var statusTag: some View {
        if isEssential {
            if isEssentialUnlocked && isChecked {
                badge("强制退出", color: .red)
            } else {
                badge("常驻", color: .green)
            }
        } else if mode == .keepSelected {
            if isChecked {
                badge("保留", color: .green)
            } else {
                badge("待关 \(app.formattedMemory)", color: .orange)
            }
        } else if isChecked {
            badge("待退 \(app.formattedMemory)", color: .accentColor)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
    }
}
