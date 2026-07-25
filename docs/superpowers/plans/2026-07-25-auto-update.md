# Auto-Update via GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add auto-update check and installation via GitHub Releases to NTranslate.

**Architecture:** Create `UpdateManager.swift` to handle fetching GitHub releases API, parsing semver, comparing versions, downloading DMG, mounting via `hdiutil`, and replacing `/Applications/NTranslate.app` via a detached script. Integrate UI into `PopoverController.swift`.

**Tech Stack:** Swift 6.3 (Swift Testing framework, URLSession, Process, Foundation, AppKit).

## Global Constraints
- Target repo: `ninhnguyen375/NTranslate`
- App path: `/Applications/NTranslate.app`
- GitHub Releases API: `https://api.github.com/repos/ninhnguyen375/NTranslate/releases/latest`

---

### Task 1: Version Comparison Logic & Unit Tests

**Files:**
- Create: `Sources/translate/UpdateManager.swift`
- Create: `Tests/translateTests/UpdateManagerTests.swift`

**Interfaces:**
- Produces: `UpdateManager.isVersion(_:newerThan:) -> Bool`

- [ ] **Step 1: Write failing unit test for version comparison**

Create `Tests/translateTests/UpdateManagerTests.swift`:

```swift
import Testing
@testable import translate

struct UpdateManagerTests {
    @Test func testVersionComparison() {
        #expect(UpdateManager.isVersion("v1.0.3", newerThan: "1.0.2") == true)
        #expect(UpdateManager.isVersion("1.1.0", newerThan: "1.0.9") == true)
        #expect(UpdateManager.isVersion("1.0.2", newerThan: "1.0.2") == false)
        #expect(UpdateManager.isVersion("1.0.1", newerThan: "1.0.2") == false)
        #expect(UpdateManager.isVersion("v2.0.0", newerThan: "1.9.9") == true)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter UpdateManagerTests`
Expected: FAIL due to missing `UpdateManager`.

- [ ] **Step 3: Implement minimal Version comparison in UpdateManager.swift**

Create `Sources/translate/UpdateManager.swift`:

```swift
import Foundation

public final class UpdateManager: @unchecked Sendable {
    public static let shared = UpdateManager()

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
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/UpdateManager.swift Tests/translateTests/UpdateManagerTests.swift
git commit -m "feat: add version comparison logic to UpdateManager with tests"
```

---

### Task 2: GitHub Release Fetcher & Asset Downloader

**Files:**
- Modify: `Sources/translate/UpdateManager.swift`
- Modify: `Tests/translateTests/UpdateManagerTests.swift`

**Interfaces:**
- Consumes: `UpdateManager.isVersion(_:newerThan:)`
- Produces:
  - `struct ReleaseInfo { tag: String, notes: String, dmgURL: URL }`
  - `UpdateManager.checkForUpdate() async throws -> ReleaseInfo?`
  - `UpdateManager.downloadDMG(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL`

- [ ] **Step 1: Write failing unit test for Release Info JSON parsing**

In `Tests/translateTests/UpdateManagerTests.swift`, add:

```swift
    @Test func testParseReleaseJSON() throws {
        let json = """
        {
          "tag_name": "v1.0.3",
          "body": "Bug fixes and improvements",
          "assets": [
            {
              "name": "NTranslate-1.0.3-universal.dmg",
              "browser_download_url": "https://github.com/ninhnguyen375/NTranslate/releases/download/v1.0.3/NTranslate-1.0.3-universal.dmg"
            }
          ]
        }
        """.data(using: .utf8)!

        let release = try UpdateManager.parseRelease(from: json)
        #expect(release.tag == "v1.0.3")
        #expect(release.notes == "Bug fixes and improvements")
        #expect(release.dmgURL.absoluteString.contains("NTranslate-1.0.3-universal.dmg"))
    }
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter UpdateManagerTests`
Expected: FAIL due to missing `parseRelease`.

- [ ] **Step 3: Implement GitHub Release model, parsing, and check API in UpdateManager.swift**

In `Sources/translate/UpdateManager.swift`:

```swift
public struct ReleaseInfo: Sendable {
    public let tag: String
    public let notes: String
    public let dmgURL: URL
}

extension UpdateManager {
    struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let assets: [GitHubAsset]
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    public static func parseRelease(from data: Data) throws -> ReleaseInfo {
        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let url = URL(string: dmgAsset.browser_download_url) else {
            throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No DMG asset found in release"])
        }
        return ReleaseInfo(tag: release.tag_name, notes: release.body ?? "", dmgURL: url)
    }

    public func checkForUpdate() async throws -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/ninhnguyen375/NTranslate/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NTranslate-AutoUpdater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let release = try UpdateManager.parseRelease(from: data)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        if UpdateManager.isVersion(release.tag, newerThan: currentVersion) {
            return release
        }
        return nil
    }

    public func downloadDMG(from url: URL, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to download DMG"])
        }
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("NTranslate-Update.dmg")
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }
}
```

- [ ] **Step 4: Run test to verify failure/pass**

Run: `swift test --filter UpdateManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/UpdateManager.swift Tests/translateTests/UpdateManagerTests.swift
git commit -m "feat: add release parsing and download logic to UpdateManager"
```

---

### Task 3: Installation Script Executer (DMG Mount & Replace)

**Files:**
- Modify: `Sources/translate/UpdateManager.swift`

**Interfaces:**
- Consumes: `localDmgURL: URL`
- Produces: `UpdateManager.installUpdateAndRestart(dmgURL: URL) throws`

- [ ] **Step 1: Implement installUpdateAndRestart logic in UpdateManager.swift**

In `Sources/translate/UpdateManager.swift`:

```swift
import AppKit

extension UpdateManager {
    public func installUpdateAndRestart(dmgURL: URL) throws {
        let appPid = ProcessInfo.processInfo.processIdentifier
        let appPath = Bundle.main.bundlePath

        // Script mounts DMG, copies new app to /Applications/NTranslate.app (or current appPath), unmounts, relaunches
        let script = """
        #!/bin/bash
        PID=\(appPid)
        DMG_PATH="\(dmgURL.path)"
        TARGET_APP="\(appPath)"

        # Wait for host app to exit
        while kill -0 $PID 2>/dev/null; do
            sleep 0.5
        done

        # Mount DMG
        MOUNT_OUTPUT=$(hdiutil attach -nobrowse -plist "$DMG_PATH")
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -A1 '<key>mount-point</key>' | tail -n1 | sed -e 's/.*<string>\(.*\)<\/string>.*/\1/')

        if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT/NTranslate.app" ]; then
            rm -rf "$TARGET_APP"
            cp -R "$MOUNT_POINT/NTranslate.app" "$TARGET_APP"
            hdiutil detach "$MOUNT_POINT" -force
            rm -f "$DMG_PATH"
            open "$TARGET_APP"
        fi
        """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("install_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        try task.run()

        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Verify swift build passes**

Run: `swift build`
Expected: Build successfully without errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/translate/UpdateManager.swift
git commit -m "feat: implement DMG mounting and app replacement script in UpdateManager"
```

---

### Task 4: UI Integration in PopoverController

**Files:**
- Modify: `Sources/translate/PopoverController.swift`

**Interfaces:**
- Consumes: `UpdateManager.shared`
- Produces: Check for Updates button in popover header & update alert/progress handling

- [ ] **Step 1: Add update button to top bar & background update check in PopoverController**

Read `Sources/translate/PopoverController.swift` where header buttons are created (around top bar setup).
Add "Check for Updates" button or menu item, and trigger `performUpdateCheck(silent: true)` on launch.

Implementation in `PopoverController.swift`:
Add `@objc private func checkForUpdatesClicked()`:
- Calls `performUpdateCheck(silent: false)`

In `performUpdateCheck(silent: Bool)`:
- Show loading state or alert if non-silent.
- `Task { do { if let release = try await UpdateManager.shared.checkForUpdate() { showUpdateAlert(release: release) } else if !silent { showUpToDateAlert() } } catch { if !silent { showErrorAlert(error) } } }`

`showUpdateAlert(release: ReleaseInfo)`:
- Displays `NSAlert` with `release.tag` and `release.notes`.
- Option "Update & Restart": Download DMG, show progress HUD/modal, then call `installUpdateAndRestart`.

- [ ] **Step 2: Verify app builds and runs via `./install-app.sh`**

Run: `./install-app.sh`
Expected: App compiles, signs, installs to `/Applications/NTranslate.app` and opens.

- [ ] **Step 3: Commit**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "feat: integrate Check for Updates UI into PopoverController"
```

---

### Task 5: End-to-End Test & Verification

- [ ] **Step 1: Test unit tests**

Run: `swift test`
Expected: ALL PASS.

- [ ] **Step 2: Test app installation & update check manually**

Run: `./install-app.sh`
Click "Check for Updates" button in popover top bar.
Verify it checks GitHub release API and alerts status properly.

- [ ] **Step 3: Final Commit**

```bash
git add .
git commit -m "chore: complete auto-update feature implementation and verification"
```
