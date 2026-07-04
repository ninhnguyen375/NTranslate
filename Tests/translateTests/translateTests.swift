import AppKit
import XCTest
@testable import translate

final class TranslateTests: XCTestCase {
    func testMarkdownDisplayPreservesReadableText() {
        let rendered = NSAttributedString.markdownDisplay("**Bold** and *italic*", font: .systemFont(ofSize: 13))
        XCTAssertEqual(rendered.string, "Bold and italic")
    }
}
