import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppCleanupResult: Equatable {
    let terminatedCount: Int
    let failedApps: [String]
    let cleanedResidualPIDCount: Int
}

struct WorkspaceScanResult {
    let apps: [AppItem]
    let reclaimableGroups: [ReclaimableProcessGroup]
    let activeExecutablePaths: [String]
}

final class AppCleanerService {
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    private let processAnalyzer: ProcessAnalyzerService

    init(processAnalyzer: ProcessAnalyzerService = ProcessAnalyzerService()) {
        self.processAnalyzer = processAnalyzer
    }

    func scanWorkspace() -> WorkspaceScanResult {
        let selfBundleID = Bundle.main.bundleIdentifier ?? "io.github.cleanquit.app"
        let defaultIcon = NSWorkspace.shared.icon(for: .applicationBundle)

        let rawCandidates: [NSRunningApplication] = NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }
            if let bundleID = app.bundleIdentifier {
                if bundleID == selfBundleID || excludedBundleIdentifiers.contains(bundleID) {
                    return false
                }
            }

            switch app.activationPolicy {
            case .regular:
                return true
            case .accessory:
                guard let bundlePath = app.bundleURL?.path else { return false }
                return Self.isTopLevelThirdPartyAppBundle(bundlePath)
            default:
                return false
            }
        }

        let candidateTuples = rawCandidates.map { app in
            let path = app.bundleURL?.path
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
            let builtInEssential = EssentialAppPolicy.isBuiltInEssential(
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                bundlePath: path
            )
            return (
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                bundlePath: path,
                isProtected: builtInEssential
            )
        }

        let analysis = processAnalyzer.analyzeProcesses(candidateApps: candidateTuples)

        let items: [AppItem] = rawCandidates
            .filter { !analysis.childSponsoredAppPIDs.contains($0.processIdentifier) }
            .map { app in
                let pid = app.processIdentifier
                let metrics = analysis.metricsByAppPID[pid]
                return AppItem(
                    pid: pid,
                    name: app.localizedName ?? app.bundleIdentifier ?? "Unknown App",
                    bundleIdentifier: app.bundleIdentifier,
                    bundlePath: app.bundleURL?.path,
                    icon: app.icon ?? defaultIcon,
                    isMenuBarAccessory: app.activationPolicy == .accessory,
                    memoryBytes: metrics?.totalFootprintBytes ?? 0,
                    processCount: metrics?.processCount ?? 1,
                    associatedPIDs: metrics?.associatedPIDs ?? [pid]
                )
            }

        let activeExecPaths = analysis.allUserNodes.values.map(\.executablePath).filter { !$0.isEmpty }
        return WorkspaceScanResult(
            apps: items,
            reclaimableGroups: analysis.reclaimableGroups,
            activeExecutablePaths: activeExecPaths
        )
    }

    func fetchRunningApps() -> [AppItem] {
        scanWorkspace().apps
    }

    func quitApps(_ apps: [AppItem], force: Bool) -> AppCleanupResult {
        var terminatedCount = 0
        var failedApps: [String] = []
        var quitAppPIDs: Set<pid_t> = []
        var quitBundlePaths: Set<String> = []
        var associatedPIDs: Set<pid_t> = []

        for item in apps {
            guard let runningApp = NSRunningApplication(processIdentifier: item.pid) else {
                terminatedCount += 1
                quitAppPIDs.insert(item.pid)
                if let bundlePath = item.bundlePath {
                    quitBundlePaths.insert(bundlePath)
                }
                associatedPIDs.formUnion(item.associatedPIDs)
                continue
            }
            if runningApp.isTerminated {
                terminatedCount += 1
                quitAppPIDs.insert(item.pid)
                if let bundlePath = item.bundlePath {
                    quitBundlePaths.insert(bundlePath)
                }
                associatedPIDs.formUnion(item.associatedPIDs)
                continue
            }

            let didRequestQuit = force ? runningApp.forceTerminate() : runningApp.terminate()
            if didRequestQuit {
                terminatedCount += 1
                quitAppPIDs.insert(item.pid)
                if let bundlePath = item.bundlePath {
                    quitBundlePaths.insert(bundlePath)
                }
                associatedPIDs.formUnion(item.associatedPIDs)
            } else {
                failedApps.append(item.name)
            }
        }

        return AppCleanupResult(
            terminatedCount: terminatedCount,
            failedApps: failedApps,
            cleanedResidualPIDCount: 0
        )
    }

    func sweepResidualsAfterQuit(apps: [AppItem], force: Bool) -> Int {
        var exitedAppPIDs: Set<pid_t> = []
        var exitedBundlePaths: Set<String> = []
        var associatedPIDs: Set<pid_t> = []

        for item in apps {
            let stillAlive: Bool
            if let running = NSRunningApplication(processIdentifier: item.pid), !running.isTerminated {
                stillAlive = true
            } else {
                stillAlive = false
            }
            guard !stillAlive else { continue }

            exitedAppPIDs.insert(item.pid)
            if let path = item.bundlePath {
                exitedBundlePaths.insert(path)
            }
            associatedPIDs.formUnion(item.associatedPIDs)
        }

        guard !exitedAppPIDs.isEmpty else { return 0 }
        return processAnalyzer.cleanupResidualProcesses(
            appPIDs: exitedAppPIDs,
            bundlePaths: exitedBundlePaths,
            associatedPIDs: associatedPIDs,
            force: force
        )
    }

    func reclaimProcessGroups(_ groups: [ReclaimableProcessGroup], force: Bool) -> Int {
        let allPIDs = groups.flatMap(\.pids)
        return processAnalyzer.terminatePIDs(allPIDs, force: force)
    }

    static func isTopLevelThirdPartyAppBundle(_ bundlePath: String) -> Bool {
        if bundlePath.hasPrefix("/System/") || bundlePath.hasPrefix("/usr/") || bundlePath.hasPrefix("/Library/Input Methods/") {
            return false
        }
        if bundlePath.contains(".app/Contents/") {
            return false
        }
        let userApps = NSHomeDirectory() + "/Applications/"
        return bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(userApps)
    }
}
