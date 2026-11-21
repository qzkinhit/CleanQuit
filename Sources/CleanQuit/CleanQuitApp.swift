import SwiftUI

@main
struct CleanQuitApp: App {
    @StateObject private var viewModel = CleanerViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            Image(
                systemName: viewModel.memorySnapshot.pressureLevel == .critical
                    ? "exclamationmark.triangle.fill"
                    : "power.circle.fill"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
