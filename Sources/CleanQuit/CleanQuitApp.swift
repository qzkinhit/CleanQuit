import SwiftUI

@main
struct CleanQuitApp: App {
    @StateObject private var viewModel = CleanerViewModel()

    var body: some Scene {
        MenuBarExtra("CleanQuit", systemImage: "power.circle.fill") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
