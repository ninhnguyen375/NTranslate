import AppKit
import Foundation

struct CrashRecovery {
    private static let cleanShutdownKey = "local.ninh.ntranslate.cleanShutdown"
    private static let acknowledgedCrashReportKey = "local.ninh.ntranslate.acknowledgedCrashReport"
    private static let diagnosticReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath

    struct CrashSummary: Equatable {
        let timestamp: String?
        let exceptionType: String?
        let terminationReason: String?

        var displayText: String {
            var lines = ["NTranslate may have crashed during the previous run."]
            if let timestamp { lines.append("Time: \(timestamp)") }
            if let exceptionType { lines.append("Error: \(exceptionType)") }
            if let terminationReason { lines.append("Termination: \(terminationReason)") }
            lines.append("You can open crash logs to view details.")
            return lines.joined(separator: "\n")
        }
    }

    /// Returns `true` when the previous session did not call `markCleanShutdown`
    /// (force-quit, crash, or being replaced by install). Always marks this launch unclean
    /// until terminate.
    static func markUncleanLaunch() -> Bool {
        let defaults = UserDefaults.standard
        let hadCleanShutdown = defaults.object(forKey: cleanShutdownKey) as? Bool ?? true
        defaults.set(false, forKey: cleanShutdownKey)
        return !hadCleanShutdown
    }

    static func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: cleanShutdownKey)
    }

    /// Only alert when the previous session ended uncleanly AND there is a real
    /// NTranslate `.ips` crash report that the user has not already dismissed.
    /// Force-quit / install-replace without a crash report must not warn.
    static func shouldPresentCrashAlert(
        uncleanShutdown: Bool,
        crashReportURL: URL?,
        acknowledgedReportName: String?
    ) -> Bool {
        guard uncleanShutdown, let crashReportURL else { return false }
        return crashReportURL.lastPathComponent != acknowledgedReportName
    }

    @MainActor
    static func presentCrashAlertIfNeeded() {
        let unclean = markUncleanLaunch()
        let latestReport = latestCrashReportURL()
        let defaults = UserDefaults.standard
        let acknowledged = defaults.string(forKey: acknowledgedCrashReportKey)

        guard shouldPresentCrashAlert(
            uncleanShutdown: unclean,
            crashReportURL: latestReport,
            acknowledgedReportName: acknowledged
        ), let latestReport
        else { return }

        let summary = summary(fromCrashReportAt: latestReport)

        let alert = NSAlert()
        alert.messageText = "NTranslate Crashed Previously"
        alert.informativeText = summary?.displayText
            ?? "NTranslate may have crashed during the previous run. You can open crash logs to view details."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Crash Log")

        let response = alert.runModal()
        defaults.set(latestReport.lastPathComponent, forKey: acknowledgedCrashReportKey)
        if response == .alertSecondButtonReturn {
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

    static func latestCrashReportURL(
        in directory: URL = URL(fileURLWithPath: diagnosticReportsPath),
        fileManager: FileManager = .default
    ) -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return urls
            .filter { $0.lastPathComponent.hasPrefix("NTranslate-") && $0.pathExtension == "ips" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return left < right
            }
    }
}
