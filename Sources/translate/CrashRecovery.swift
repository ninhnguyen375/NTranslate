import AppKit
import Foundation

struct CrashRecovery {
    private static let cleanShutdownKey = "local.ninh.ntranslate.cleanShutdown"
    private static let diagnosticReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath

    struct CrashSummary: Equatable {
        let timestamp: String?
        let exceptionType: String?
        let terminationReason: String?

        var displayText: String {
            var lines = ["NTranslate có thể đã bị crash ở lần chạy trước."]
            if let timestamp { lines.append("Thời gian: \(timestamp)") }
            if let exceptionType { lines.append("Lỗi: \(exceptionType)") }
            if let terminationReason { lines.append("Kết thúc: \(terminationReason)") }
            lines.append("Bạn có thể mở crash log để xem chi tiết.")
            return lines.joined(separator: "\n")
        }
    }

    static func markUncleanLaunch() -> Bool {
        let defaults = UserDefaults.standard
        let hadCleanShutdown = defaults.object(forKey: cleanShutdownKey) as? Bool ?? true
        defaults.set(false, forKey: cleanShutdownKey)
        return !hadCleanShutdown
    }

    static func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: cleanShutdownKey)
    }

    @MainActor
    static func presentCrashAlertIfNeeded() {
        guard markUncleanLaunch() else { return }
        let latestReport = latestCrashReportURL()
        let summary = latestReport == nil ? nil : summary(fromCrashReportAt: latestReport!)

        let alert = NSAlert()
        alert.messageText = "NTranslate gặp sự cố lần chạy trước"
        alert.informativeText = summary?.displayText ?? "NTranslate có thể đã bị crash ở lần chạy trước. Bạn có thể mở crash log để xem chi tiết."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Mở crash log")

        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: diagnosticReportsPath))
        }
    }

    static func summary(fromCrashReportAt url: URL) -> CrashSummary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return summary(fromCrashReportData: data)
    }

    static func summary(fromCrashReportData data: Data) -> CrashSummary? {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              let jsonData = String(firstLine).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        let exception = object["exception"] as? [String: Any]
        let termination = object["termination"] as? [String: Any]
        let terminationReason = [termination?["namespace"], termination?["indicator"]]
            .compactMap { $0 as? String }
            .joined(separator: ": ")

        return CrashSummary(
            timestamp: object["timestamp"] as? String,
            exceptionType: exception?["type"] as? String,
            terminationReason: terminationReason.isEmpty ? nil : terminationReason
        )
    }

    private static func latestCrashReportURL() -> URL? {
        let directory = URL(fileURLWithPath: diagnosticReportsPath)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return urls
            .filter { $0.lastPathComponent.hasPrefix("NTranslate-") && $0.pathExtension == "ips" }
            .max { lhs, rhs in
                (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast <
                    (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }
    }
}
