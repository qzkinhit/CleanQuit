# CleanQuit

一个轻量、原生的 macOS 菜单栏小工具：**一键退出你勾选的所有应用程序，并一键关闭所有访达 (Finder) 窗口**。下班或结束工作时，告别一个一个手动关闭窗口和应用的繁琐操作。

## 核心特性

- **菜单栏常驻**：纯 SwiftUI 原生界面，不占 Dock 栏图标，点开即用。
- **勾选批量退出**：自动列出当前运行中的桌面应用，支持搜索、全选、清空。
- **一键关闭访达窗口**：通过 Apple Events 安全关闭所有打开的 Finder 窗口（不会杀掉 Finder 进程本身），也支持「仅关访达」快捷按钮。
- **优雅退出 / 强制退出切换**：默认使用优雅退出（保留未保存文档的确认提示）；遇到卡死或顽固应用可开启「强制退出」。
- **白名单保护**：点击应用右侧盾牌图标加入白名单，全选和预设匹配时自动跳过。
- **常用清理预设**：可将当前勾选列表与选项保存为预设（如「下班清理」「专注模式」），一键复用。
- **全局快捷键**：基于 Carbon `RegisterEventHotKey` 实现，无需辅助功能权限即可在任意界面通过快捷键（默认 `⌥⌘K`）一键清理。

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Swift 5.9+ / Xcode 15+（如需从源码构建）

## 快速构建与运行

```bash
git clone https://github.com/qzkinhit/CleanQuit.git
cd CleanQuit
chmod +x scripts/build_app.sh
./scripts/build_app.sh --install
open /Applications/CleanQuit.app
```

也可以直接用 Xcode 打开 `Package.swift` 进行开发和调试。

## 权限说明

首次使用「关闭所有访达窗口」功能时，macOS 会弹出自动化权限提示，允许 CleanQuit 控制 **访达 (Finder)** 即可。如果此前误点拒绝，可在：
`系统设置 → 隐私与安全性 → 自动化` 中重新开启。

## 开源协议

[MIT License](LICENSE)
