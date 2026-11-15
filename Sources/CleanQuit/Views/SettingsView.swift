import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("设置")
                    .font(.headline)

                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("常规与快捷键")
                    .font(.subheadline.bold())

                Toggle(
                    "开机自启动",
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                .font(.subheadline)

                Toggle("启用全局快捷键一键清理", isOn: $viewModel.globalHotkeyEnabled)
                    .font(.subheadline)

                if viewModel.globalHotkeyEnabled {
                    Picker("触发快捷键", selection: $viewModel.hotkeyCombo) {
                        ForEach(HotkeyCombo.presets, id: \.combo) { item in
                            Text(item.label).tag(item.combo)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("白名单应用 (\(viewModel.whitelistedKeys.count))")
                    .font(.subheadline.bold())

                if viewModel.whitelistedKeys.isEmpty {
                    Text("在主列表点击右侧盾牌图标即可将应用加入白名单。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.whitelistedKeys).sorted(), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        viewModel.whitelistedKeys.remove(key)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }
            }

            Spacer()

            HStack {
                Text("CleanQuit · MIT Open Source")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(height: 380)
    }
}
