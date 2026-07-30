# macOS Platform Release Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate macOS updates and releases under `macos-v<semver>` tags so Windows-only releases never affect macOS update checks.

**Architecture:** macOS updater fetches the GitHub Releases collection, filters strictly to stable `macos-v<semver>` releases, requires one matching DMG asset, and selects the highest version newer than the installed app. `release-dmg.sh` creates `macos-v<semver>` tags/releases while preserving existing DMG naming. Windows `windows-v*` releases remain independent and are ignored.

**Tech Stack:** Swift 6.3, Foundation `URLSession`/`JSONDecoder`, Swift Testing, zsh, GitHub CLI.

## Global Constraints

- Work only on `main` lineage; never merge/cherry-pick Windows `windows-app` history.
- Accept release tags only in exact lowercase form `macos-v<major>.<minor>.<patch>`.
- Ignore `windows-v*`, legacy `v*`, draft, prerelease, malformed, same, and older releases.
- Require exactly one DMG named `NTranslate-<version>-<arch>.dmg`; `<arch>` may be `arm64`, `x86_64`, or `universal`.
- Do not change DMG signing/notarization behavior.
- Run `./install-app.sh` after source/release-script changes and report version/build.
- Do not publish a release until all Swift tests and local install verification pass.

---

### Task 1: Make release selection platform-specific

**Files:**
- Modify: `Sources/translate/UpdateManager.swift`
- Modify: `Tests/translateTests/UpdateManagerTests.swift`

**Interfaces:**
- Produces: `UpdateManager.selectRelease(from:newerThan:) throws -> ReleaseInfo?`
- Preserves: `checkForUpdate() async throws -> ReleaseInfo?`, `downloadDMG(from:)`, `installUpdateAndRestart(dmgURL:)`

- [ ] **Step 1: Add failing selection tests**

Replace current single-release JSON test with array-based tests covering:

```swift
@Test func selectsNewestMacOSReleaseAndIgnoresOtherPlatforms() throws {
    let data = """
    [
      {"tag_name":"windows-v9.0.0","body":"Windows","draft":false,"prerelease":false,"assets":[{"name":"NTranslate-9.0.0-win-x64-setup.exe","browser_download_url":"https://github.com/example/windows.exe"}]},
      {"tag_name":"macos-v1.2.4","body":"Newest macOS","draft":false,"prerelease":false,"assets":[{"name":"NTranslate-1.2.4-arm64.dmg","browser_download_url":"https://github.com/example/NTranslate-1.2.4-arm64.dmg"}]},
      {"tag_name":"macos-v1.2.3","body":"Older macOS","draft":false,"prerelease":false,"assets":[{"name":"NTranslate-1.2.3-arm64.dmg","browser_download_url":"https://github.com/example/NTranslate-1.2.3-arm64.dmg"}]}
    ]
    """.data(using: .utf8)!

    let release = try UpdateManager.selectRelease(from: data, newerThan: "1.2.2")
    #expect(release?.tag == "macos-v1.2.4")
    #expect(release?.dmgURL.lastPathComponent == "NTranslate-1.2.4-arm64.dmg")
}
```

Add separate rejection cases for:

```text
v9.0.0
windows-v9.0.0
Macos-v9.0.0
macos-v9.0
macos-v09.0.0
draft=true
prerelease=true
same/older version
missing DMG
duplicate matching DMGs
DMG whose embedded version differs from tag
```

- [ ] **Step 2: Confirm tests fail before implementation**

```bash
swift test --filter UpdateManagerTests
```

Expected: compile failure because `selectRelease(from:newerThan:)` does not exist.

- [ ] **Step 3: Decode release arrays and select exact macOS candidates**

Extend `GitHubRelease` with:

```swift
let draft: Bool
let prerelease: Bool
```

Implement strict version extraction without accepting legacy prefixes:

```swift
private static func macOSVersion(from tag: String) -> String? {
    let prefix = "macos-v"
    guard tag.hasPrefix(prefix) else { return nil }
    let version = String(tag.dropFirst(prefix.count))
    guard version.range(
        of: #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$"#,
        options: .regularExpression
    ) != nil else { return nil }
    return version
}
```

Implement `selectRelease(from:newerThan:)` by decoding `[GitHubRelease]`, rejecting draft/prerelease/non-macOS releases, requiring exactly one matching DMG, and selecting highest newer version.

Match DMG using exact semantic version plus allowed architecture:

```swift
let pattern = #"^NTranslate-"# + NSRegularExpression.escapedPattern(for: version)
    + #"-(arm64|x86_64|universal)\.dmg$"#
```

- [ ] **Step 4: Change network endpoint from latest release to release collection**

In `checkForUpdate()`, use:

```swift
https://api.github.com/repos/ninhnguyen375/NTranslate/releases?per_page=100
```

Then call:

```swift
return try UpdateManager.selectRelease(from: data, newerThan: currentVersion)
```

Do not use `/releases/latest`; latest may be a Windows release.

- [ ] **Step 5: Run focused and full Swift tests**

```bash
swift test --filter UpdateManagerTests
swift test
```

Expected: all tests pass.

---

### Task 2: Create macOS-prefixed releases

**Files:**
- Modify: `release-dmg.sh`
- Modify: `README.md`

- [ ] **Step 1: Add a static script check**

Create `Tests/release-dmg-tags.sh`:

```bash
#!/bin/bash
set -euo pipefail
text=$(cat release-dmg.sh)
grep -F 'TAG="macos-v${VERSION}"' <<<"$text" >/dev/null
! grep -F 'TAG="v${VERSION}"' <<<"$text" >/dev/null
```

Make executable and run it:

```bash
chmod +x Tests/release-dmg-tags.sh
./Tests/release-dmg-tags.sh
```

Expected before implementation: failure.

- [ ] **Step 2: Prefix macOS tags**

Change:

```bash
TAG="v${VERSION}"
```

to:

```bash
TAG="macos-v${VERSION}"
```

Keep DMG filename unchanged:

```bash
DMG_NAME="NTranslate-${VERSION}-${ARCH}.dmg"
```

- [ ] **Step 3: Update README Latest-line replacement**

Allow `release-dmg.sh` to replace either legacy `v<version>` or new `macos-v<version>` links, but always write `macos-v<version>` for future releases.

Do not rewrite current live link until a matching `macos-v*` release exists; avoid dead links.

- [ ] **Step 4: Validate shell script**

```bash
zsh -n release-dmg.sh
./Tests/release-dmg-tags.sh
```

Expected: both pass.

---

### Task 3: Verify installed macOS app

**Files:**
- No new source files

- [ ] **Step 1: Run full install gate**

```bash
./install-app.sh
```

Record exact output:

```text
Version: <semantic version>
Build: <build number>
```

- [ ] **Step 2: Confirm installed app metadata**

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/NTranslate.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/NTranslate.app/Contents/Info.plist
codesign -vv /Applications/NTranslate.app
```

Expected: plist values match installer output; code signature verifies.

- [ ] **Step 3: Manually verify update isolation**

Run app from `/Applications/NTranslate.app`, choose **Check for Updates**, and confirm:

```text
windows-v* release newer than installed macOS version -> ignored
legacy v* release -> ignored
macos-v* release with missing/wrong DMG -> ignored
valid newer macos-v* release -> offered
```

Use a draft fixture/repository for this check; do not publish production release merely to test selection.

---

### Task 4: Commit, push, and publish next macOS release

- [ ] **Step 1: Review diff and commit**

```bash
git diff --check
git status --short
git add Sources/translate/UpdateManager.swift Tests/translateTests/UpdateManagerTests.swift release-dmg.sh Tests/release-dmg-tags.sh
git commit -m "feat(macos): isolate updates under macOS release tags"
```

- [ ] **Step 2: Push `main` after verification**

```bash
git push origin main
```

- [ ] **Step 3: Publish next macOS release**

```bash
./release-dmg.sh
```

Expected release tag and artifact:

```text
macos-v<version>
NTranslate-<version>-<arch>.dmg
```

- [ ] **Step 4: Verify release contents**

```bash
gh release view "macos-v<version>" --repo ninhnguyen375/NTranslate --json tagName,url,assets
```

Require exactly one macOS DMG matching release version. Windows assets are neither required nor modified.

- [ ] **Step 5: Report completion**

Report release URL, version, build, DMG filename, Swift test result, install result, and remaining dirty paths.
