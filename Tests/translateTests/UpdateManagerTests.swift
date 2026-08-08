import Foundation
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

    @Test func selectsNewestMacOSReleaseAndIgnoresOtherPlatforms() throws {
        let data = try releasesData([
            release(tag: "windows-v9.0.0", assetNames: ["NTranslate-9.0.0-arm64.dmg"]),
            release(tag: "macos-v1.2.3", assetNames: ["NTranslate-1.2.3-x86_64.dmg"]),
            release(tag: "macos-v1.2.4", body: "Latest macOS", assetNames: ["NTranslate-1.2.4-arm64.dmg"])
        ])

        let selected = try UpdateManager.selectRelease(from: data, newerThan: "1.2.2")

        #expect(selected?.tag == "macos-v1.2.4")
        #expect(selected?.notes == "Latest macOS")
        #expect(selected?.dmgURL.lastPathComponent == "NTranslate-1.2.4-arm64.dmg")
    }

    @Test(arguments: [
        "v9.0.0",
        "windows-v9.0.0",
        "Macos-v9.0.0",
        "macos-v9.0",
        "macos-v09.0.0",
        "macos-v1.0.0.0",
        "macos-v1.0.0-beta",
        "macos-v1.0.0+build"
    ])
    func rejectsInvalidMacOSTags(_ tag: String) throws {
        let data = try releasesData([release(tag: tag, assetNames: ["NTranslate-9.0.0-arm64.dmg"])])
        #expect(try UpdateManager.selectRelease(from: data, newerThan: "0.0.0") == nil)
    }

    @Test(arguments: [(true, false), (false, true)])
    func rejectsDraftAndPrerelease(draft: Bool, prerelease: Bool) throws {
        let data = try releasesData([
            release(
                tag: "macos-v2.0.0",
                draft: draft,
                prerelease: prerelease,
                assetNames: ["NTranslate-2.0.0-arm64.dmg"]
            )
        ])
        #expect(try UpdateManager.selectRelease(from: data, newerThan: "1.0.0") == nil)
    }

    @Test(arguments: ["1.2.2", "1.2.3"])
    func rejectsCurrentAndOlderVersions(_ version: String) throws {
        let data = try releasesData([
            release(tag: "macos-v1.2.2", assetNames: ["NTranslate-1.2.2-arm64.dmg"])
        ])
        #expect(try UpdateManager.selectRelease(from: data, newerThan: version) == nil)
    }

    @Test func rejectsInvalidDMGAssets() throws {
        let releases = [
            release(tag: "macos-v2.0.0"),
            release(
                tag: "macos-v2.0.1",
                assetNames: ["NTranslate-2.0.1-arm64.dmg", "NTranslate-2.0.1-x86_64.dmg"]
            ),
            release(tag: "macos-v2.0.2", assetNames: ["NTranslate-2.0.2-i386.dmg"]),
            release(tag: "macos-v2.0.3", assetNames: ["NTranslate-2.0.2-arm64.dmg"])
        ]

        #expect(try UpdateManager.selectRelease(from: releasesData(releases), newerThan: "1.0.0") == nil)
    }

    @Test func ignoresInvalidAssetURLWithoutLosingValidCandidate() throws {
        let data = try releasesData([
            release(
                tag: "macos-v2.0.0",
                assetNames: ["NTranslate-2.0.0-arm64.dmg"],
                downloadURL: "http://[::1"
            ),
            release(tag: "macos-v1.5.0", assetNames: ["NTranslate-1.5.0-universal.dmg"])
        ])

        #expect(try UpdateManager.selectRelease(from: data, newerThan: "1.0.0")?.tag == "macos-v1.5.0")
    }

    private func release(
        tag: String,
        body: String? = nil,
        draft: Bool = false,
        prerelease: Bool = false,
        assetNames: [String] = [],
        downloadURL: String? = nil
    ) -> [String: Any] {
        [
            "tag_name": tag,
            "body": body as Any,
            "draft": draft,
            "prerelease": prerelease,
            "assets": assetNames.map { name in
                [
                    "name": name,
                    "browser_download_url": downloadURL
                        ?? "https://github.com/ninhnguyen375/NTranslate/releases/download/\(tag)/\(name)"
                ]
            }
        ]
    }

    private func releasesData(_ releases: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: releases)
    }
}
