import AppKit
import Foundation

struct EssentialEntryDisplay: Identifiable, Equatable {
    let key: String
    let displayName: String
    let icon: NSImage
    let isBuiltIn: Bool
    let isRunning: Bool

    var id: String { key }
}

enum EssentialAppPolicy {
    static let defaultEssentialCatalog: [(bundleID: String, fallbackName: String)] = [
        ("io.github.clash-verge-rev.clash-verge-rev", "Clash Verge"),
        ("io.tailscale.ipn.macsys", "Tailscale"),
        ("com.tailscale.ipn.macos", "Tailscale (App Store)"),
        ("com.tencent.xinWeChat", "微信"),
        ("com.tencent.qq", "QQ"),
        ("com.ccswitch.desktop", "CC Switch"),
        ("com.netease.uuremote", "UU远程"),
        ("com.caldis.Mos", "Mos"),
        ("me.waydabber.BetterDummy", "BetterDisplay"),
        ("cn.better365.iBar", "iBar"),
        ("com.bartelsmedia.ShareMouse", "ShareMouse"),
        ("com.tencent.inputmethod.wetype", "微信输入法"),
        ("local.pool-router", "Pool Router"),
        ("local.booster.mac.prototype", "加速棒共享"),
        ("com.nssurge.surge-mac", "Surge"),
        ("com.west2online.ClashX", "ClashX"),
        ("com.west2online.ClashX.Pro", "ClashX Pro"),
        ("com.zerotier.ZeroTier-One", "ZeroTier")
    ]

    static let defaultEssentialBundleIDs: Set<String> = Set(
        defaultEssentialCatalog.map(\.bundleID)
    )

    private static let essentialKeywords: [String] = [
        "clash",
        "mihomo",
        "verge",
        "v2ray",
        "xray",
        "sing-box",
        "shadowrocket",
        "quantumult",
        "hiddify",
        "nekoray",
        "proxifier",
        "wireguard",
        "openvpn",
        "letsvpn",
        "astrill",
        "tailscale",
        "uuremote",
        "uu远程",
        "ccswitch",
        "cc switch",
        "inputmethod"
    ]

    static func isBuiltInEssential(
        name: String,
        bundleIdentifier: String?,
        bundlePath: String?,
        enableKeywordMatch: Bool = true
    ) -> Bool {
        if let bundleID = bundleIdentifier, defaultEssentialBundleIDs.contains(bundleID) {
            return true
        }
        if enableKeywordMatch {
            return matchesEssentialKeyword(name: name, bundleIdentifier: bundleIdentifier, path: bundlePath)
        }
        return false
    }

    static func matchesEssentialKeyword(
        name: String,
        bundleIdentifier: String?,
        path: String?
    ) -> Bool {
        if let path, path.contains("/Input Methods/") {
            return true
        }
        let haystack = [
            name.lowercased(),
            bundleIdentifier?.lowercased() ?? "",
            path?.lowercased() ?? ""
        ].joined(separator: " ")

        return essentialKeywords.contains { haystack.contains($0) }
    }

    static func resolveAppDisplay(forKey key: String, fallbackName: String? = nil) -> (name: String, icon: NSImage, installed: Bool) {
        let defaultIcon = NSWorkspace.shared.icon(for: .applicationBundle)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            let bundle = Bundle(url: appURL)
            let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return (displayName, icon, true)
        }
        return (fallbackName ?? key, defaultIcon, false)
    }
}
