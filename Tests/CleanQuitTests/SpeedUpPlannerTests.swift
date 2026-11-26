import AppKit
import Foundation
import Testing
@testable import CleanQuit

private let mb: UInt64 = 1_048_576
private let now = Date(timeIntervalSince1970: 2_000_000_000)
private let longAgo = UInt64(now.timeIntervalSince1970) - 3 * 3600

private func node(_ pid: pid_t, parent: pid_t, name: String, path: String,
                  memory: UInt64, cpu: UInt64 = 0, start: UInt64 = longAgo) -> ProcessNode {
    ProcessNode(pid: pid, ppid: parent, uid: 501, name: name, executablePath: path,
                footprintBytes: memory, rootAppBundlePath: ProcessAnalyzerService.extractRootAppBundlePath(from: path),
                cpuNanos: cpu, startSeconds: start)
}

private func app(_ pid: pid_t, _ name: String, bundle: String, tree: Set<pid_t>, memory: UInt64) -> AppItem {
    AppItem(pid: pid, name: name, bundleIdentifier: "test.\(name)", bundlePath: bundle,
            icon: NSImage(), memoryBytes: memory, processCount: tree.count, associatedPIDs: tree)
}

private func input(_ item: AppItem, frontmost: Bool = false) -> SpeedUpAppInput {
    SpeedUpAppInput(item: item, isEssential: false, isKept: false, isFrontmost: frontmost, usedRecently: false)
}

/// Builds before/after snapshots where `busy` processes gain one second of CPU time.
private func snapshots(_ nodes: [ProcessNode], busy: Set<pid_t> = []) -> ([pid_t: ProcessNode], [pid_t: ProcessNode]) {
    var before: [pid_t: ProcessNode] = [:]
    var after: [pid_t: ProcessNode] = [:]
    for n in nodes {
        before[n.pid] = n
        var later = n
        if busy.contains(n.pid) { later.cpuNanos += 1_000_000_000 }
        after[n.pid] = later
    }
    return (before, after)
}

@Test func idleLargeAppIsSuggestedButNotTicked() {
    let nodes = [
        node(100, parent: 1, name: "Reader", path: "/Applications/Reader.app/Contents/MacOS/Reader", memory: 400 * mb),
        node(101, parent: 100, name: "Reader Helper", path: "/Applications/Reader.app/Contents/Frameworks/H.app/Contents/MacOS/H", memory: 200 * mb)
    ]
    let (before, after) = snapshots(nodes)
    let reader = app(100, "Reader", bundle: "/Applications/Reader.app", tree: [100, 101], memory: 600 * mb)
    let plan = SpeedUpPlanner.makePlan(before: before, after: after, arguments: [:], seconds: 2,
                                       apps: [input(reader)], residualGroups: [], now: now)
    #expect(plan.items.count == 1)
    #expect(plan.items.first?.kind == .idleApp)
    #expect(plan.items.first?.preselected == false)
    #expect(plan.preselectedIDs.isEmpty)
}

@Test func appsWithCPUOrChildTasksAreProtected() {
    let nodes = [
        node(200, parent: 1, name: "Code", path: "/Applications/Code.app/Contents/MacOS/Code", memory: 500 * mb),
        node(201, parent: 200, name: "zsh", path: "/bin/zsh", memory: 5 * mb),
        node(300, parent: 1, name: "Busy", path: "/Applications/Busy.app/Contents/MacOS/Busy", memory: 500 * mb)
    ]
    let (before, after) = snapshots(nodes, busy: [300])
    let code = app(200, "Code", bundle: "/Applications/Code.app", tree: [200, 201], memory: 505 * mb)
    let busy = app(300, "Busy", bundle: "/Applications/Busy.app", tree: [300], memory: 500 * mb)
    let plan = SpeedUpPlanner.makePlan(before: before, after: after, arguments: [:], seconds: 2,
                                       apps: [input(code), input(busy)], residualGroups: [], now: now)
    #expect(plan.items.isEmpty)
    let reasons = Dictionary(uniqueKeysWithValues: plan.protectedApps.map { ($0.name, $0.reason) })
    #expect(reasons["Code"]?.contains("zsh") == true)
    #expect(reasons["Busy"] == "正在占用 CPU")
}

@Test func frontmostAppIsProtected() {
    let nodes = [node(400, parent: 1, name: "Writer", path: "/Applications/Writer.app/Contents/MacOS/Writer", memory: 800 * mb)]
    let (before, after) = snapshots(nodes)
    let writer = app(400, "Writer", bundle: "/Applications/Writer.app", tree: [400], memory: 800 * mb)
    let plan = SpeedUpPlanner.makePlan(before: before, after: after, arguments: [:], seconds: 2,
                                       apps: [input(writer, frontmost: true)], residualGroups: [], now: now)
    #expect(plan.items.isEmpty)
    #expect(plan.protectedApps.first?.reason == "当前前台")
}

@Test func orphanedIdleToolServerIsTickedButBusyOrYoungOnesAreLeft() {
    let npx = "/Users/u/.npm/_npx/abc/node_modules/.bin/playwright-mcp"
    let nodes = [
        node(500, parent: 1, name: "node", path: "/opt/homebrew/bin/node", memory: 80 * mb),
        node(501, parent: 500, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", memory: 300 * mb),
        node(600, parent: 1, name: "node", path: "/opt/homebrew/bin/node", memory: 60 * mb),
        node(700, parent: 1, name: "node", path: "/opt/homebrew/bin/node", memory: 60 * mb,
             start: UInt64(now.timeIntervalSince1970) - 60),
        node(800, parent: 1, name: "python3", path: "/opt/homebrew/bin/python3", memory: 30 * mb)
    ]
    let (before, after) = snapshots(nodes, busy: [600])
    let args: [pid_t: String] = [500: npx, 600: npx, 700: npx, 800: "/Users/u/.local/bin/ccauth agy bridge"]
    let plan = SpeedUpPlanner.makePlan(before: before, after: after, arguments: args, seconds: 2,
                                       apps: [], residualGroups: [], now: now)
    #expect(plan.items.count == 1)
    let tool = plan.items[0]
    #expect(tool.kind == .orphanTool)
    #expect(tool.preselected)
    #expect(Set(tool.processes.keys) == [500, 501])
    #expect(tool.memoryBytes == 380 * mb)
}

@Test func automationBrowserWithLiveControllerIsNotTicked() {
    let nodes = [
        node(900, parent: 1, name: "devin", path: "/Applications/Devin.app/Contents/Resources/devin", memory: 100 * mb),
        node(901, parent: 900, name: "node", path: "/opt/homebrew/bin/node", memory: 40 * mb),
        node(902, parent: 901, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", memory: 350 * mb)
    ]
    let (before, after) = snapshots(nodes)
    let args: [pid_t: String] = [902: "--enable-automation --remote-debugging-pipe", 901: "playwright-mcp"]
    let plan = SpeedUpPlanner.makePlan(before: before, after: after, arguments: args, seconds: 2,
                                       apps: [], residualGroups: [], now: now)
    #expect(plan.items.count == 1)
    #expect(plan.items[0].kind == .idleBrowser)
    #expect(plan.items[0].preselected == false)
}

@Test func interpreterBundlesAreNeverResidualApps() {
    #expect(!ProcessAnalyzerService.isResidualAppBundle(
        "/opt/homebrew/Cellar/python@3.14/3.14.4/Frameworks/Python.framework/Versions/3.14/Resources/Python.app"))
    #expect(!ProcessAnalyzerService.isResidualAppBundle(
        "/Library/Application Support/Adobe/CoreSyncExtension/Core Sync.app"))
    #expect(ProcessAnalyzerService.isResidualAppBundle("/Applications/Dropbox.app"))
}
