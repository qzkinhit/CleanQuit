import Darwin
import Foundation

/// What the speed-up check proposes to stop.
enum SpeedUpItemKind: String, Equatable {
    case orphanTool      // a tool server whose editor or agent has exited
    case residualHelper  // background services left behind by an app that has quit
    case idleBrowser     // an automation browser with no CPU activity
    case idleApp         // a large app with no activity, quit only when the user ticks it

    var badgeText: String {
        switch self {
        case .orphanTool: return "无主工具服务"
        case .residualHelper: return "退出残留"
        case .idleBrowser: return "自动化浏览器"
        case .idleApp: return "闲置应用"
        }
    }
}

struct SpeedUpItem: Identifiable, Hashable {
    let id: String
    let kind: SpeedUpItemKind
    let title: String
    let detail: String
    /// Processes to stop, each with its start time so a reused PID is never hit.
    let processes: [pid_t: UInt64]
    /// For idle apps: the app's main PID, quit through the normal app quit.
    let appPID: pid_t?
    let memoryBytes: UInt64
    let preselected: Bool

    var formattedMemory: String { MemoryFormatter.string(fromBytes: memoryBytes) }
}

/// An app the check leaves alone, with the reason.
struct ProtectedApp: Identifiable, Hashable {
    let id: String
    let name: String
    let reason: String
    let memoryBytes: UInt64
}

struct SpeedUpPlan {
    let items: [SpeedUpItem]
    let protectedApps: [ProtectedApp]
    let sampledSeconds: Double

    var preselectedIDs: Set<String> { Set(items.filter(\.preselected).map(\.id)) }
}

/// Facts about one running app that decide whether it is in use.
struct SpeedUpAppInput {
    let item: AppItem
    let isEssential: Bool
    let isKept: Bool
    let isFrontmost: Bool
    let usedRecently: Bool
}

/// Builds a speed-up plan from two process snapshots taken a few seconds apart.
///
/// Rules:
/// - An app is in use when it is essential, kept, frontmost, used in the last minutes, spends CPU
///   during the sample, or runs child tasks outside its own bundle (terminals, agents, language servers).
///   Apps in use are never touched.
/// - Processes are stopped automatically only when nothing owns them any more (the parent exited)
///   and they spent no CPU during the sample.
/// - Idle apps above `idleAppMinimumBytes` are listed unticked; the user decides.
enum SpeedUpPlanner {
    static let idleAppMinimumBytes: UInt64 = 300 * 1_048_576
    static let orphanMinimumAge: TimeInterval = 10 * 60
    static let toolKeywords = ["mcp", "playwright", "puppeteer", "/.npm/_npx/", "chrome-devtools"]
    static let toolInterpreters: Set<String> = ["node", "npm", "npx", "bun", "deno", "python", "python3", "uv", "uvx"]
    static let automationFlags = ["--remote-debugging-pipe", "--enable-automation", "--remote-debugging-port"]

    /// CPU time that counts as activity: 2% of one core over the sample window.
    static func busyThreshold(seconds: Double) -> UInt64 {
        UInt64(max(seconds, 0.5) * 0.02 * 1_000_000_000)
    }

    static func makePlan(
        before: [pid_t: ProcessNode],
        after: [pid_t: ProcessNode],
        arguments: [pid_t: String],
        seconds: Double,
        apps: [SpeedUpAppInput],
        residualGroups: [ReclaimableProcessGroup],
        now: Date = Date()
    ) -> SpeedUpPlan {
        let threshold = busyThreshold(seconds: seconds)
        var children: [pid_t: [pid_t]] = [:]
        for node in after.values {
            children[node.ppid, default: []].append(node.pid)
        }

        func cpuDelta(_ pids: Set<pid_t>) -> UInt64 {
            pids.reduce(UInt64(0)) { sum, pid in
                guard let a = after[pid], let b = before[pid], a.startSeconds == b.startSeconds else { return sum }
                return sum + (a.cpuNanos > b.cpuNanos ? a.cpuNanos - b.cpuNanos : 0)
            }
        }

        func subtree(_ root: pid_t) -> Set<pid_t> {
            var result: Set<pid_t> = [root]
            var stack = [root]
            while let cur = stack.popLast() {
                for child in children[cur] ?? [] where !result.contains(child) {
                    result.insert(child)
                    stack.append(child)
                }
            }
            return result
        }

        func memory(_ pids: Set<pid_t>) -> UInt64 {
            pids.reduce(UInt64(0)) { $0 + (after[$1]?.footprintBytes ?? 0) }
        }

        func stamped(_ pids: Set<pid_t>) -> [pid_t: UInt64] {
            var out: [pid_t: UInt64] = [:]
            for pid in pids { if let n = after[pid] { out[pid] = n.startSeconds } }
            return out
        }

        var items: [SpeedUpItem] = []
        var protectedApps: [ProtectedApp] = []
        var claimed: Set<pid_t> = []
        var appTreePIDs: Set<pid_t> = []
        for app in apps { appTreePIDs.formUnion(app.item.associatedPIDs) }

        // Automation browsers: a browser started with automation flags, outside any app tree the
        // user opened. Stopped automatically only when its controller has exited.
        for node in after.values where !claimed.contains(node.pid) {
            let args = arguments[node.pid] ?? ""
            guard automationFlags.contains(where: { args.contains($0) }) else { continue }
            if let parent = after[node.ppid], automationFlags.contains(where: { (arguments[parent.pid] ?? "").contains($0) }) {
                continue   // a helper of a browser already counted through its root
            }
            let tree = subtree(node.pid)
            guard cpuDelta(tree) < threshold else { continue }
            let controllerAlive = node.ppid > 1 && after[node.ppid] != nil
            let controller = after[node.ppid]?.name ?? ""
            claimed.formUnion(tree)
            items.append(SpeedUpItem(
                id: "browser:\(node.pid):\(node.startSeconds)",
                kind: .idleBrowser,
                title: "\(node.name) 自动化实例（PID \(node.pid)）",
                detail: controllerAlive
                    ? "由 \(controller) 控制，本次检测无 CPU 活动，勾选后回收"
                    : "控制它的程序已退出，\(tree.count) 个进程",
                processes: stamped(tree),
                appPID: nil,
                memoryBytes: memory(tree),
                preselected: !controllerAlive
            ))
        }

        // Tool servers left behind by an editor or agent session that has exited.
        for node in after.values where node.ppid == 1 && !claimed.contains(node.pid) && !appTreePIDs.contains(node.pid) {
            let args = arguments[node.pid] ?? ""
            let haystack = (node.executablePath + " " + args).lowercased()
            guard toolInterpreters.contains(node.name.lowercased()) || haystack.contains("/.npm/_npx/") else { continue }
            guard toolKeywords.contains(where: { haystack.contains($0) }) else { continue }
            let age = now.timeIntervalSince1970 - Double(node.startSeconds)
            guard age >= orphanMinimumAge else { continue }
            let tree = subtree(node.pid)
            guard cpuDelta(tree) < threshold else { continue }
            claimed.formUnion(tree)
            let label = args.split(separator: " ").first(where: { $0.lowercased().contains("mcp") || $0.contains("@") })
                .map(String.init) ?? node.name
            items.append(SpeedUpItem(
                id: "tool:\(node.pid):\(node.startSeconds)",
                kind: .orphanTool,
                title: "无主工具服务 \(URL(fileURLWithPath: label).lastPathComponent)",
                detail: "启动它的编辑器或智能体已退出，已运行 \(Int(age / 3600)) 小时",
                processes: stamped(tree),
                appPID: nil,
                memoryBytes: memory(tree),
                preselected: true
            ))
        }

        // Services left by apps that have quit (found by the existing scan), when idle.
        for group in residualGroups where group.kind == .orphanHelper {
            let pids = Set(group.pids).subtracting(claimed)
            guard !pids.isEmpty, cpuDelta(pids) < threshold else { continue }
            claimed.formUnion(pids)
            items.append(SpeedUpItem(
                id: "residual:\(group.id)",
                kind: .residualHelper,
                title: group.title,
                detail: group.subtitle,
                processes: stamped(pids),
                appPID: nil,
                memoryBytes: memory(pids),
                preselected: true
            ))
        }

        // Apps: keep everything in use, list large idle ones unticked.
        for app in apps {
            let item = app.item
            if claimed.contains(item.pid) { continue }
            let tree = item.associatedPIDs
            let bytes = memory(tree)
            var reason: String?
            if app.isEssential {
                reason = "基础常驻"
            } else if app.isKept {
                reason = "已设为保留"
            } else if app.isFrontmost {
                reason = "当前前台"
            } else if app.usedRecently {
                reason = "最近 10 分钟用过"
            } else if cpuDelta(tree) >= threshold {
                reason = "正在占用 CPU"
            } else {
                let tasks = workChildren(of: item, tree: tree, nodes: after)
                if !tasks.isEmpty {
                    reason = "有子任务在运行（" + tasks.prefix(3).joined(separator: "、") + "）"
                }
            }
            if let reason {
                if bytes >= 100 * 1_048_576 {
                    protectedApps.append(ProtectedApp(id: "app:\(item.pid)", name: item.name, reason: reason, memoryBytes: bytes))
                }
                continue
            }
            guard bytes >= idleAppMinimumBytes else { continue }
            items.append(SpeedUpItem(
                id: "app:\(item.pid)",
                kind: .idleApp,
                title: item.name,
                detail: "本次检测无 CPU 活动，没有子任务，勾选后正常退出（未保存的文档会提示保存）",
                processes: stamped([item.pid]),
                appPID: item.pid,
                memoryBytes: bytes,
                preselected: false
            ))
        }

        let order: [SpeedUpItemKind: Int] = [.orphanTool: 0, .idleBrowser: 1, .residualHelper: 2, .idleApp: 3]
        items.sort {
            if $0.preselected != $1.preselected { return $0.preselected }
            if order[$0.kind]! != order[$1.kind]! { return order[$0.kind]! < order[$1.kind]! }
            return $0.memoryBytes > $1.memoryBytes
        }
        protectedApps.sort { $0.memoryBytes > $1.memoryBytes }
        return SpeedUpPlan(items: items, protectedApps: protectedApps, sampledSeconds: seconds)
    }

    /// Distinct names of processes in an app's tree that run from outside the app bundle,
    /// such as terminal shells, agents and language servers.
    static func workChildren(of item: AppItem, tree: Set<pid_t>, nodes: [pid_t: ProcessNode]) -> [String] {
        guard let bundle = item.bundlePath, !bundle.isEmpty else { return [] }
        var names: [String] = []
        for pid in tree where pid != item.pid {
            guard let node = nodes[pid], !node.executablePath.isEmpty else { continue }
            if node.executablePath.hasPrefix(bundle + "/") { continue }
            if node.executablePath.hasPrefix("/System/Library/") || node.executablePath.hasPrefix("/usr/libexec/") { continue }
            if !names.contains(node.name) { names.append(node.name) }
        }
        return names.sorted()
    }
}

/// Samples processes, builds the plan and stops what the user confirmed.
final class SpeedUpService {
    private let analyzer: ProcessAnalyzerService

    init(analyzer: ProcessAnalyzerService = ProcessAnalyzerService()) {
        self.analyzer = analyzer
    }

    /// Takes two snapshots `seconds` apart. Call off the main thread.
    func sample(seconds: Double) -> (before: [pid_t: ProcessNode], after: [pid_t: ProcessNode], arguments: [pid_t: String]) {
        let uid = getuid()
        let before = analyzer.collectUserProcessNodes(uid: uid)
        Thread.sleep(forTimeInterval: seconds)
        let after = analyzer.collectUserProcessNodes(uid: uid)
        var arguments: [pid_t: String] = [:]
        for node in after.values {
            let name = node.name.lowercased()
            let interesting = node.ppid == 1
                || SpeedUpPlanner.toolInterpreters.contains(name)
                || name.contains("chrome") || name.contains("chromium") || name.contains("edge")
            if interesting {
                arguments[node.pid] = ProcessAnalyzerService.arguments(of: node.pid)
            }
        }
        return (before, after, arguments)
    }

    /// Sends SIGTERM to processes whose start time still matches, then SIGKILL to those still alive after `grace`.
    /// Returns the number of processes that are gone.
    func stop(_ processes: [pid_t: UInt64], grace: TimeInterval = 1.5) -> Int {
        let live = analyzer.collectUserProcessNodes(uid: getuid())
        let targets = processes.compactMap { pid, start -> pid_t? in
            guard pid > 1, pid != getpid(), let node = live[pid], node.startSeconds == start else { return nil }
            return pid
        }
        guard !targets.isEmpty else { return 0 }
        _ = analyzer.terminatePIDs(targets, force: false)
        Thread.sleep(forTimeInterval: grace)
        let survivors = targets.filter { kill($0, 0) == 0 }
        if !survivors.isEmpty {
            _ = analyzer.terminatePIDs(survivors, force: true)
        }
        return targets.count
    }
}
