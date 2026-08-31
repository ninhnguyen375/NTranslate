// Self-check for the tagged model responses (image translation and text auto-detect):
// streaming extraction and final parse.
// swiftc -parse-as-library Scripts/tagged-response-check.swift -o /tmp/tagged-response-check && /tmp/tagged-response-check

import Foundation

func taggedValue(_ tag: String, in text: String) -> String? {
    guard let open = text.range(of: "<\(tag)>"),
          let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex)
    else { return nil }
    return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
}

func streamedTaggedTranslation(from partial: String) -> String? {
    guard let open = partial.range(of: "<translation>") else { return nil }
    var text = String(partial[open.upperBound...])
    if let close = text.range(of: "</translation>") {
        return String(text[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let last = text.lastIndex(of: "<"), "</translation>".hasPrefix(text[last...]) {
        text = String(text[..<last])
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

@main
struct Check {
    static func main() {
        let full = """
            <source_lang>German</source_lang>
            <source>Guten Morgen
            Guten Abend</source>
            <target_lang>Vietnamese</target_lang>
            <translation>Chào buổi sáng
            Chào buổi tối</translation>
            """

        assert(taggedValue("source_lang", in: full) == "German")
        assert(taggedValue("source", in: full) == "Guten Morgen\nGuten Abend")
        assert(taggedValue("translation", in: full) == "Chào buổi sáng\nChào buổi tối")
        assert(taggedValue("missing", in: full) == nil)

        // Streaming: nothing until the translation tag opens.
        assert(streamedTaggedTranslation(from: "<source_lang>German</source_lang>\n<source>Guten") == nil)
        assert(streamedTaggedTranslation(from: "<source>Guten Morgen</source>\n<translation>Chào") == "Chào")
        assert(streamedTaggedTranslation(from: full) == "Chào buổi sáng\nChào buổi tối")

        // A half-arrived closing tag must not leak into the pane.
        assert(streamedTaggedTranslation(from: "<translation>Chào<") == "Chào")
        assert(streamedTaggedTranslation(from: "<translation>Chào</trans") == "Chào")
        // A real "<" in the text is kept.
        assert(streamedTaggedTranslation(from: "<translation>a < b") == "a < b")

        // Text auto-detect uses the same two trailing tags, without a transcription.
        let autoDetect = "<source_lang>German</source_lang>\n<translation>Chào buổi sáng</translation>"
        assert(taggedValue("source_lang", in: autoDetect) == "German")
        assert(streamedTaggedTranslation(from: autoDetect) == "Chào buổi sáng")
        assert(streamedTaggedTranslation(from: "<source_lang>Ger") == nil)

        // The transcription is only handed over once its closing tag lands.
        assert(taggedValue("source", in: "<source>Guten Mor") == nil)

        print("tagged-response-check: OK")
    }
}
