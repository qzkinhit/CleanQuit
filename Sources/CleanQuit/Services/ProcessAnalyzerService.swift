import Darwin
import Foundation

enum ReclaimableKind: String, Codable, Equatable {
    case orphanHelper
    case bloatedTool

    var badgeText: String {
        switch self {
        case .orphanHelper:
            return "退出残留"
        case .bloatedTool:
            return "膨胀子进程"
        }
    }
}

struct ReclaimableProcessGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let kind: ReclaimableKind
    let pids: [pid_t]
    let memoryBytes: UInt64

    var formattedMemory: String {
        MemoryFormatter.string(fromBytes: memoryBytes)
    }
}

struct AppProcessMetrics: Equatable {
    let totalFootprintBytes: UInt64
    let processCount: Int
    let associatedPIDs: Set<pid_t>
}

struct ProcessNode {
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let name: String
    let executablePath: String
    let footprintBytes: UInt64
    let rootAppBundlePath: String?
    /// User plus system CPU time used so far, in nanoseconds.
    var cpuNanos: UInt64 = 0
    /// Process start time, seconds since 1970.
    var startSeconds: UInt64 = 0
}

struct ProcessSnapshotAnalysis {
    let metricsByAppPID: [pid_t: AppProcessMetrics]
    let childSponsoredAppPIDs: Set<pid_t>
    let reclaimableGroups: [ReclaimableProcessGroup]
    let allUserNodes: [pid_t: ProcessNode]
}

final class ProcessAnalyzerService {
    private static let pathBufferSize = 4096

    private let protectedProcessNames: Set<String> = [
        "launchd", "loginwindow", "WindowServer", "Dock", "Finder", "SystemUIServer",
        "ControlCenter", "NotificationCenter", "UserEventAgent", "cfprefsd", "distnoted",
        "ssh-agent", "ssh", "gpg-agent", "tmux", "zsh", "bash", "fish",
        "CleanQuit", "verge-mihomo", "clash-verge", "clash-verge-service", "Tailscale"
    ]

    func analyzeProcesses(
        candidateApps: [(pid: pid_t, bundleID: String?, bundlePath: String?, isProtected: Bool)]
    ) -> ProcessSnapshotAnalysis {
        let currentUID = getuid()
        let nodes = collectUserProcessNodes(uid: currentUID)

        var childrenByPPID: [pid_t: [pid_t]] = [:]
        for node in nodes.values {
            childrenByPPID[node.ppid, default: []].append(node.pid)
        }

        let candidatePIDMap = Dictionary(uniqueKeysWithValues: candidateApps.map { ($0.pid, $0) })

        var childSponsoredAppPIDs: Set<pid_t> = []
        for app in candidateApps {
            var cursor = nodes[app.pid]?.ppid ?? 0
            var visited: Set<pid_t> = [app.pid]
            while cursor > 1, !visited.contains(cursor) {
                visited.insert(cursor)
                if let ancestorApp = candidatePIDMap[cursor],
                   ancestorApp.bundleID != app.bundleID {
                    childSponsoredAppPIDs.insert(app.pid)
                    break
                }
                cursor = nodes[cursor]?.ppid ?? 0
            }
        }

        let topLevelApps = candidateApps.filter { !childSponsoredAppPIDs.contains($0.pid) }
        var appPIDByBundlePath: [String: pid_t] = [:]
        for app in topLevelApps {
            if let path = app.bundlePath, !path.isEmpty {
                appPIDByBundlePath[path] = app.pid
            }
        }

        var assignedPIDs: Set<pid_t> = []
        var metricsByAppPID: [pid_t: AppProcessMetrics] = [:]

        for app in topLevelApps {
            var treePIDs: Set<pid_t> = [app.pid]
            var queue: [pid_t] = [app.pid]
            while let current = queue.popLast() {
                if let children = childrenByPPID[current] {
                    for child in children where !treePIDs.contains(child) {
                        if candidatePIDMap[child] != nil && !childSponsoredAppPIDs.contains(child) {
                            continue
                        }
                        treePIDs.insert(child)
                        queue.append(child)
                    }
                }
            }

            if let bundlePath = app.bundlePath, !bundlePath.isEmpty {
                for node in nodes.values where node.rootAppBundlePath == bundlePath {
                    treePIDs.insert(node.pid)
                }
            }

            assignedPIDs.formUnion(treePIDs)
            let footprint = treePIDs.reduce(UInt64(0)) { partial, pid in
                partial + (nodes[pid]?.footprintBytes ?? 0)
            }
            metricsByAppPID[app.pid] = AppProcessMetrics(
                totalFootprintBytes: footprint,
                processCount: treePIDs.count,
                associatedPIDs: treePIDs
            )
        }

        let activeBundlePaths = Set(topLevelApps.compactMap(\.bundlePath))
        let reclaimable = detectReclaimableGroups(
            nodes: nodes,
            childrenByPPID: childrenByPPID,
            assignedPIDs: assignedPIDs,
            activeBundlePaths: activeBundlePaths
        )

        return ProcessSnapshotAnalysis(
            metricsByAppPID: metricsByAppPID,
            childSponsoredAppPIDs: childSponsoredAppPIDs,
            reclaimableGroups: reclaimable,
            allUserNodes: nodes
        )
    }

    func terminatePIDs(_ pids: [pid_t], force: Bool) -> Int {
        let selfPID = getpid()
        var terminated = 0
        let sig = force ? SIGKILL : SIGTERM

        for pid in Set(pids) where pid > 1 && pid != selfPID {
            if kill(pid, 0) != 0 {
                terminated += 1
                continue
            }
            if kill(pid, sig) == 0 {
                terminated += 1
            }
        }
        return terminated
    }

    func cleanupResidualProcesses(
        appPIDs: Set<pid_t>,
        bundlePaths: Set<String>,
        associatedPIDs: Set<pid_t>,
        force: Bool
    ) -> Int {
        let selfPID = getpid()
        let nodes = collectUserProcessNodes(uid: getuid())
        var targets: Set<pid_t> = []

        for pid in associatedPIDs where !appPIDs.contains(pid) && pid > 1 && pid != selfPID {
            guard let node = nodes[pid] else { continue }
            if protectedProcessNames.contains(node.name) { continue }
            if node.ppid == 1 || (node.rootAppBundlePath != nil && bundlePaths.contains(node.rootAppBundlePath!)) {
                targets.insert(pid)
            }
        }

        for node in nodes.values where !appPIDs.contains(node.pid) && node.pid != selfPID {
            if let rootBundle = node.rootAppBundlePath, bundlePaths.contains(rootBundle) {
                targets.insert(node.pid)
            }
        }

        guard !targets.isEmpty else { return 0 }
        return terminatePIDs(Array(targets), force: force)
    }

    /// Command line of a process (arguments after the executable path), or "" when unreadable.
    static func arguments(of pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return "" }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }   // executable path
        while index < size && buffer[index] == 0 { index += 1 }
        var args: [String] = []
        var start = index
        while index < size && args.count < argc {
            if buffer[index] == 0 {
                args.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return args.joined(separator: " ")
    }

    func activeExecutablePaths() -> [String] {
        collectUserProcessNodes(uid: getuid()).values.map(\.executablePath).filter { !$0.isEmpty }
    }

    private func detectReclaimableGroups(
        nodes: [pid_t: ProcessNode],
        childrenByPPID: [pid_t: [pid_t]],
        assignedPIDs: Set<pid_t>,
        activeBundlePaths: Set<String>
    ) -> [ReclaimableProcessGroup] {
        var groups: [ReclaimableProcessGroup] = []
        var orphanBuckets: [String: [ProcessNode]] = [:]

        for node in nodes.values where !assignedPIDs.contains(node.pid) {
            if isSystemOrProtectedPath(node.executablePath) || protectedProcessNames.contains(node.name) {
                continue
            }
            // App extensions (.appex) are started on demand by the system, for Finder or share menus.
            if node.executablePath.contains(".appex/") {
                continue
            }
            if let rootBundle = node.rootAppBundlePath, !activeBundlePaths.contains(rootBundle),
               Self.isResidualAppBundle(rootBundle) {
                orphanBuckets[rootBundle, default: []].append(node)
            }
        }

        for (bundlePath, bucket) in orphanBuckets {
            let totalBytes = bucket.reduce(UInt64(0)) { $0 + $1.footprintBytes }
            guard totalBytes >= 2 * 1_048_576 else { continue }
            let appName = URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
            if EssentialAppPolicy.matchesEssentialKeyword(name: appName, bundleIdentifier: nil, path: bundlePath) {
                continue
            }
            groups.append(
                ReclaimableProcessGroup(
                    id: "orphan:\(bundlePath)",
                    title: "\(appName) 后台残留服务",
                    subtitle: "\(bucket.count) 个已退出应用的遗留进程",
                    kind: .orphanHelper,
                    pids: bucket.map(\.pid),
                    memoryBytes: totalBytes
                )
            )
        }

        let bloatedThreshold: UInt64 = 300 * 1_048_576
        var visitedSubtreePIDs: Set<pid_t> = []

        for node in nodes.values {
            let lowerPath = node.executablePath.lowercased()
            let isHeadlessBrowserLeak = lowerPath.contains("playwright") || lowerPath.contains("puppeteer")
            guard isHeadlessBrowserLeak, !visitedSubtreePIDs.contains(node.pid) else { continue }

            let subtree = collectSubtree(root: node.pid, childrenByPPID: childrenByPPID)
            let subtreeBytes = subtree.reduce(UInt64(0)) { $0 + (nodes[$1]?.footprintBytes ?? 0) }
            guard subtreeBytes >= bloatedThreshold else { continue }

            visitedSubtreePIDs.formUnion(subtree)
            groups.append(
                ReclaimableProcessGroup(
                    id: "bloated:\(node.pid)",
                    title: "无头浏览器自动化实例 (PID \(node.pid))",
                    subtitle: "包含 \(subtree.count) 个关联进程，闲置时可安全回收",
                    kind: .bloatedTool,
                    pids: Array(subtree),
                    memoryBytes: subtreeBytes
                )
            )
        }

        return groups.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private func collectSubtree(root: pid_t, childrenByPPID: [pid_t: [pid_t]]) -> Set<pid_t> {
        var result: Set<pid_t> = [root]
        var stack: [pid_t] = [root]
        while let cur = stack.popLast() {
            for child in childrenByPPID[cur] ?? [] where !result.contains(child) {
                result.insert(child)
                stack.append(child)
            }
        }
        return result
    }

    private func isSystemOrProtectedPath(_ path: String) -> Bool {
        if path.isEmpty { return true }
        let prefixes = [
            "/System/",
            "/usr/",
            "/sbin/",
            "/bin/",
            "/Library/Apple/",
            "/Library/Input Methods/",
            "/Library/SystemExtensions/",
            "/Library/PrivilegedHelperTools/"
        ]
        if prefixes.contains(where: { path.hasPrefix($0) }) {
            return true
        }
        if path.contains("/Library/Input Methods/") {
            return true
        }
        return false
    }

    /// rusage CPU times are in Mach absolute time units on Apple silicon.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    func collectUserProcessNodes(uid: uid_t) -> [pid_t: ProcessNode] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(estimated) * 2)
        let bufferBytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = Int(proc_listallpids(&pids, bufferBytes))
        guard count > 0 else { return [:] }

        var nodes: [pid_t: ProcessNode] = [:]
        nodes.reserveCapacity(count)

        for idx in 0..<min(count, pids.count) {
            let pid = pids[idx]
            guard pid > 0 else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize else {
                continue
            }
            guard bsdInfo.pbi_uid == uid else { continue }

            var pathBuffer = [CChar](repeating: 0, count: Self.pathBufferSize)
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(Self.pathBufferSize))
            let execPath = pathLen > 0 ? String(cString: pathBuffer) : ""

            let procName: String = withUnsafePointer(to: bsdInfo.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                    let name = String(cString: cStr)
                    if !name.isEmpty { return name }
                    return URL(fileURLWithPath: execPath).lastPathComponent
                }
            }

            var footprint: UInt64 = 0
            var cpuNanos: UInt64 = 0
            var rusage = rusage_info_v4()
            let rusageStatus = withUnsafeMutablePointer(to: &rusage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
                }
            }
            if rusageStatus == 0 {
                footprint = rusage.ri_phys_footprint
                let ticks = rusage.ri_user_time &+ rusage.ri_system_time
                cpuNanos = ticks.multipliedReportingOverflow(by: Self.timebase.numer).partialValue / Self.timebase.denom
            } else {
                var taskInfo = proc_taskinfo()
                let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
                if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize {
                    footprint = taskInfo.pti_resident_size
                }
            }

            nodes[pid] = ProcessNode(
                pid: pid,
                ppid: Int32(bsdInfo.pbi_ppid),
                uid: bsdInfo.pbi_uid,
                name: procName,
                executablePath: execPath,
                footprintBytes: footprint,
                rootAppBundlePath: Self.extractRootAppBundlePath(from: execPath),
                cpuNanos: cpuNanos,
                startSeconds: UInt64(bsdInfo.pbi_start_tvsec)
            )
        }

        return nodes
    }

    /// Only apps installed in /Applications or ~/Applications can leave residual services.
    /// Interpreters and frameworks that ship as .app folders (Homebrew's Python.app, for example)
    /// run scripts and agents and are never treated as leftovers.
    static func isResidualAppBundle(_ bundlePath: String) -> Bool {
        AppCleanerService.isTopLevelThirdPartyAppBundle(bundlePath)
    }

    static func extractRootAppBundlePath(from executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        let rootPath = String(executablePath[..<range.upperBound].dropLast())
        if rootPath.hasPrefix("/System/Library/") {
            return nil
        }
        return rootPath
    }
}
