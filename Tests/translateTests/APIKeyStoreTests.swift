import Foundation
import Testing
@testable import translate

@Suite(.serialized)
struct APIKeyStoreTests {
    @Test func savesUpdatesLoadsAndDeletesAPIKey() throws {
        let account = "test-\(UUID().uuidString)"
        let store = APIKeyStore(service: "local.ninh.ntranslate.tests", account: account)
        defer { try? store.delete() }

        try store.delete()
        #expect(try store.load() == nil)

        try store.save("first-key")
        #expect(try store.load() == "first-key")

        try store.save("second-key")
        #expect(try store.load() == "second-key")

        try store.save("   ")
        #expect(try store.load() == nil)
    }
}
