import AppKit
import Foundation

enum FinderError: LocalizedError, Equatable {
    case permissionDenied
    case scriptError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "请在「系统设置 → 隐私与安全性 → 自动化」中允许 CleanQuit 控制访达 (Finder)。"
        case .scriptError(let message):
            return "关闭访达窗口失败：\(message)"
        }
    }
}

/// Closes all open Finder windows via Apple Events without killing Finder itself.
final class FinderService {
    func closeAllWindows() -> Result<Int, FinderError> {
        let source = """
        tell application "Finder"
            set winCount to count of windows
            if winCount > 0 then
                close every window
            end if
            return winCount
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptError("无法初始化 AppleScript"))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if errorNumber == -1743 {
                return .failure(.permissionDenied)
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "未知错误 (\(errorNumber))"
            return .failure(.scriptError(message))
        }

        return .success(Int(descriptor.int32Value))
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
