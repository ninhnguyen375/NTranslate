import Foundation
import Testing
@testable import translate

@Suite(.serialized)
struct AppConfigSecurityTests {
    @Test func encodingNeverContainsAPIKey() throws {
        let text = String(decoding: try AppConfig.encodePrettyJSON(), as: UTF8.self)
        #expect(!text.contains("apiKey"))
    }

    @Test func writeUsesOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = directory.appendingPathComponent("config.json").path
        defer { try? FileManager.default.removeItem(at: directory) }

        try AppConfig.write(.default, at: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func migrationExtractsAndRemovesLegacyAPIKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = directory.appendingPathComponent("config.json").path
        let keyStore = APIKeyStore(service: "local.ninh.ntranslate.tests", account: UUID().uuidString)
        defer {
            try? keyStore.delete()
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var object = try #require(
            JSONSerialization.jsonObject(with: AppConfig.encodePrettyJSON()) as? [String: Any]
        )
        object["apiKey"] = "legacy-secret"
        try JSONSerialization.data(withJSONObject: object).write(to: URL(fileURLWithPath: path))

        #expect(try AppConfig.migrateLegacyAPIKey(at: path, keyStore: keyStore))
        #expect(try keyStore.load() == "legacy-secret")
        let migratedText = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!migratedText.contains("apiKey"))
        let migratedAgain = try AppConfig.migrateLegacyAPIKey(at: path, keyStore: keyStore)
        #expect(!migratedAgain)
    }

    @Test func validationRejectsInvalidSettings() {
        var config = AppConfig.default
        config.apiBaseURL = "file:///tmp/key"
        config.languages = ["English", "English"]
        config.maxTranslateLength = 0
        config.hotkey.option = false

        let issues = config.validationIssues()
        #expect(issues.contains(where: { $0.contains("API base URL") }))
        #expect(issues.contains(where: { $0.contains("duplicates") }))
        #expect(issues.contains(where: { $0.contains("greater than zero") }))
        #expect(issues.contains(where: { $0.contains("modifier") }))
    }
}
