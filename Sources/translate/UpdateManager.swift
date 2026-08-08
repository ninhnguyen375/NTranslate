import Foundation
import AppKit

public struct ReleaseInfo: Sendable {
    public let tag: String
    public let notes: String
    public let dmgURL: URL
}

public final class UpdateManager: @unchecked Sendable {
    public static let shared = UpdateManager()

    struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    public static func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let cleanLatest = latest.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let latestParts = cleanLatest.split(separator: ".").compactMap { Int($0) }
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0..<maxCount {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    private static func macOSVersion(from tag: String) -> String? {
        let prefix = "macos-v"
        guard tag.hasPrefix(prefix) else { return nil }
        let version = String(tag.dropFirst(prefix.count))
        let range = NSRange(version.startIndex..., in: version)
        let pattern = #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$"#
        guard try! NSRegularExpression(pattern: pattern).firstMatch(in: version, range: range) != nil else {
            return nil
        }
        return version
    }

    public static func selectRelease(from data: Data, newerThan currentVersion: String) throws -> ReleaseInfo? {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        var best: (version: String, release: ReleaseInfo)?

        for release in releases {
            guard !release.draft,
                  !release.prerelease,
                  let version = macOSVersion(from: release.tag_name),
                  isVersion(version, newerThan: currentVersion)
            else { continue }

            let escapedVersion = NSRegularExpression.escapedPattern(for: version)
            let pattern = "^NTranslate-\(escapedVersion)-(arm64|x86_64|universal)\\.dmg$"
            let regex = try! NSRegularExpression(pattern: pattern)
            let assets = release.assets.filter { asset in
                regex.firstMatch(
                    in: asset.name,
                    range: NSRange(asset.name.startIndex..., in: asset.name)
                ) != nil
            }
            guard assets.count == 1,
                  let url = URL(string: assets[0].browser_download_url)
            else { continue }

            let candidate = ReleaseInfo(tag: release.tag_name, notes: release.body ?? "", dmgURL: url)
            if best == nil || isVersion(version, newerThan: best!.version) {
                best = (version, candidate)
            }
        }

        return best?.release
    }

    public func checkForUpdate() async throws -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/ninhnguyen375/NTranslate/releases?per_page=100") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NTranslate-AutoUpdater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return try UpdateManager.selectRelease(from: data, newerThan: currentVersion)
    }

    public func downloadDMG(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to download DMG"])
        }
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("NTranslate-Update.dmg")
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    public func installUpdateAndRestart(dmgURL: URL) throws {
        let appPid = ProcessInfo.processInfo.processIdentifier
        let appPath = Bundle.main.bundlePath

        let script = #"""
        #!/bin/bash
        PID=\#(appPid)
        DMG_PATH="\#(dmgURL.path)"
        TARGET_APP="\#(appPath)"

        while kill -0 $PID 2>/dev/null; do
            sleep 0.5
        done

        MOUNT_OUTPUT=$(hdiutil attach -nobrowse -plist "$DMG_PATH")
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -A1 '<key>mount-point</key>' | tail -n1 | sed -e 's/.*<string>\(.*\)<\/string>.*/\1/')

        if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT/NTranslate.app" ]; then
            rm -rf "$TARGET_APP"
            cp -R "$MOUNT_POINT/NTranslate.app" "$TARGET_APP"
            hdiutil detach "$MOUNT_POINT" -force
            rm -f "$DMG_PATH"
            open "$TARGET_APP"
        fi
        """#

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("install_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: String.Encoding.utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        try task.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
