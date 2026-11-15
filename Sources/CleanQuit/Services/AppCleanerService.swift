import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppCleanupResult: Equatable {
    let terminatedCount: Int
    let failedApps: [String]
}

/// Discovers and terminates user-facing macOS applications.
final class AppCleanerService {
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder"
    ]

    func fetchRunningApps() -> [AppItem] {
        let selfBundleID = Bundle.main.bundleIdentifier
        let defaultIcon = NSWorkspace.shared.icon(for: .applicationBundle)

        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular else { return false }
                guard !app.isTerminated else { return false }
                if let bundleID = app.bundleIdentifier {
                    if bundleID == selfBundleID || excludedBundleIdentifiers.contains(bundleID) {
                        return false
                    }
                }
                return true
            }
            .map { app in
                AppItem(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
                    bundleIdentifier: app.bundleIdentifier,
                    icon: app.icon ?? defaultIcon
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func quitApps(_ apps: [AppItem], force: Bool) -> AppCleanupResult {
        var terminatedCount = 0
        var failedApps: [String] = []

        for item in apps {
            guard let runningApp = NSRunningApplication(processIdentifier: item.pid) else {
                continue
            }
            if runningApp.isTerminated {
                terminatedCount += 1
                continue
            }

            let didRequestQuit = force ? runningApp.forceTerminate() : runningApp.terminate()
            if didRequestQuit {
                terminatedCount += 1
            } else {
                failedApps.append(item.name)
            }
        }

        return AppCleanupResult(terminatedCount: terminatedCount, failedApps: failedApps)
    }
}
