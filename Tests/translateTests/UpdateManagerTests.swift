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
}
