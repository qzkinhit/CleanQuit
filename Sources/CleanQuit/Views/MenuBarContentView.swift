import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @State private var showingSettings = false
    @State private var showingSavePreset = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                SettingsView(viewModel: viewModel, isPresented: $showingSettings)
            } else {
                mainContent
            }
        }
        .frame(width: 370)
        .onAppear {
            viewModel.refreshApps()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            headerBar

            if showingSavePreset {
                PresetSheetView(
                    presetName: $newPresetName,
                    selectedCount: viewModel.selectedRunningApps.count,
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
            Divider()
            optionsSection

            if let message = viewModel.statusMessage {
                statusBanner(message)
            }

            actionButtons
        }
        .padding(14)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "power.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("CleanQuit")
                    .font(.headline)
                Text("运行中 \(viewModel.runningApps.count) 个应用")
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
            .help("刷新运行中的应用")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置与快捷键")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("退出 CleanQuit")
        }
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
                            Text("\(preset.name) (\(preset.appKeys.count))")
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
                Label("预设 (\(viewModel.presets.count))", systemImage: "bookmark")
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
            .disabled(viewModel.selectedRunningApps.isEmpty)

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
                TextField("搜索应用...", text: $viewModel.searchText)
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

    private var appListSection: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if viewModel.filteredApps.isEmpty {
                    Text(viewModel.runningApps.isEmpty ? "没有可清理的运行中应用" : "没有匹配的应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(viewModel.filteredApps) { app in
                        AppRowView(
                            app: app,
                            isSelected: viewModel.isSelected(app),
                            isWhitelisted: viewModel.isWhitelisted(app),
                            onToggleSelect: { viewModel.toggleSelection(for: app) },
                            onToggleWhitelist: { viewModel.toggleWhitelist(for: app) }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 220)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $viewModel.closeFinderWindows) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.blue)
                    Text("同时关闭所有访达 (Finder) 窗口")
                        .font(.subheadline)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $viewModel.forceQuit) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(viewModel.forceQuit ? .orange : .secondary)
                    Text("强制退出 (Force Quit，跳过未保存提示)")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.forceQuit ? .orange : .primary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.showAutomationPermissionHelp {
                Button("打开系统设置 → 自动化") {
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

    private var actionButtons: some View {
        let count = viewModel.selectedRunningApps.count
        let title: String = {
            if count > 0 && viewModel.closeFinderWindows {
                return "一键清理 \(count) 个应用 + 关闭访达"
            } else if count > 0 {
                return "一键退出 \(count) 个应用"
            } else if viewModel.closeFinderWindows {
                return "一键关闭所有访达窗口"
            } else {
                return "请先勾选应用"
            }
        }()

        return Button {
            viewModel.runCleanup()
        } label: {
            HStack {
                Spacer()
                Text(title)
                    .fontWeight(.semibold)
                if viewModel.globalHotkeyEnabled {
                    Text(viewModel.hotkeyCombo.displayString)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.forceQuit ? .orange : .accentColor)
        .disabled(count == 0 && !viewModel.closeFinderWindows)
    }
}

private struct AppRowView: View {
    let app: AppItem
    let isSelected: Bool
    let isWhitelisted: Bool
    let onToggleSelect: () -> Void
    let onToggleWhitelist: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSelect) {
                Image(systemName: isWhitelisted ? "lock.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(isWhitelisted ? .secondary : (isSelected ? Color.accentColor : .secondary))
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(isWhitelisted)

            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isWhitelisted ? .secondary : .primary)
                if isWhitelisted {
                    Text("已加入白名单")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggleWhitelist) {
                Image(systemName: isWhitelisted ? "shield.fill" : "shield")
                    .font(.caption)
                    .foregroundStyle(isWhitelisted ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isWhitelisted ? "移出白名单" : "加入白名单（全选时自动跳过）")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isWhitelisted {
                onToggleSelect()
            }
        }
    }
}
