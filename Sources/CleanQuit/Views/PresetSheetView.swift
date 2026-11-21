import SwiftUI

struct PresetSheetView: View {
    @Binding var presetName: String
    let mode: CleanupMode
    let targetCount: Int
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                mode == .keepSelected ? "预设名称（如 论文学习）" : "预设名称（如 下班清理）",
                text: $presetName
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onSubmit {
                if !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSave()
                }
            }

            Button("保存(\(targetCount))") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("取消") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
