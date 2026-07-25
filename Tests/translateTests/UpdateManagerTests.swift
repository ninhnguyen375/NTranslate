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
