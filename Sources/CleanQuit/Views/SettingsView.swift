import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Label("返回主面板", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("设置与常驻名单")
                    .font(.headline)

                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("常规与快捷键")
                    .font(.subheadline.bold())

                HStack(spacing: 16) {
                    Toggle(
                        "开机自启动",
                        isOn: Binding(
                            get: { viewModel.launchAtLogin },
                            set: { viewModel.setLaunchAtLogin($0) }
                        )
                    )
                    .font(.caption)

                    Toggle("启用全局快捷键", isOn: $viewModel.globalHotkeyEnabled)
                        .font(.caption)

                    Spacer()
                }

                if viewModel.globalHotkeyEnabled {
                    Picker("清理快捷键", selection: $viewModel.hotkeyCombo) {
                        ForEach(HotkeyCombo.presets, id: \.combo) { item in
                            Text(item.label).tag(item.combo)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("基础常驻保护名单 (\(viewModel.activeEssentialEntries.count))")
                        .font(.subheadline.bold())

                    Spacer()

                    if !viewModel.removedBuiltInEssentialKeys.isEmpty || !viewModel.autoProtectVPNKeywords {
                        Button("恢复默认") {
                            viewModel.restoreDefaultEssentials()
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 6) {
                    Menu {
                        if viewModel.manageableApps.isEmpty {
                            Text("当前没有其他运行中的应用")
                        } else {
                            ForEach(viewModel.manageableApps) { app in
                                Button {
                                    viewModel.addEssentialKey(app.persistenceKey, displayName: app.name)
                                } label: {
                                    Text(app.name)
                                }
                            }
                        }
                    } label: {
                        Label("添加运行中应用", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .fixedSize()

                    Button {
                        pickAppBundleFromDisk()
                    } label: {
                        Label("选择本地 .app...", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                Toggle("自动识别 VPN 代理与输入法类应用", isOn: $viewModel.autoProtectVPNKeywords)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if viewModel.activeEssentialEntries.isEmpty {
                            Text("当前常驻保护名单为空")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(viewModel.activeEssentialEntries) { entry in
                                HStack(spacing: 8) {
                                    Image(nsImage: entry.icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)

                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack(spacing: 4) {
                                            Text(entry.displayName)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(1)
                                            Text(entry.isBuiltIn ? "默认" : "自定义")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.14))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                            if entry.isRunning {
                                                Text("运行中")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.green)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.green.opacity(0.12))
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                        }
                                        Text(entry.key)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        viewModel.removeEssentialKey(entry.key, displayName: entry.displayName)
                                    } label: {
                                        Text("移出")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 222)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let msg = viewModel.statusMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("CleanQuit 2.0 · MIT Open Source")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(height: 476)
    }

    private func pickAppBundleFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "选择要加入基础常驻保护的应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls {
                viewModel.addEssentialFromBundleURL(url)
            }
        }
    }
}
