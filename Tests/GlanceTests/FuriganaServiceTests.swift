import XCTest
import CoreText
import AppKit
@testable import Glance

final class FuriganaServiceTests: XCTestCase {
    private let service = FuriganaService.shared

    func test_containsKanji_detection() {
        XCTAssertTrue(FuriganaService.containsKanji("漢字"))
        XCTAssertTrue(FuriganaService.containsKanji("これは日本語です"))
        XCTAssertTrue(FuriganaService.containsKanji("食べる"))
        XCTAssertTrue(FuriganaService.containsKanji("Tokyo (東京)"))

        XCTAssertFalse(FuriganaService.containsKanji("あいうえお"))
        XCTAssertFalse(FuriganaService.containsKanji("アイウエオ"))
        XCTAssertFalse(FuriganaService.containsKanji("Hello World 123!"))
        XCTAssertFalse(FuriganaService.containsKanji(""))
    }

    func test_annotate_nonKanjiText_returnsSinglePlainSegment() {
        let text = "Hello world! これはテストです。"
        let segments = service.annotate(text: text)

        XCTAssertFalse(segments.isEmpty)
        // All non-kanji tokens should have nil readings
        for segment in segments {
            XCTAssertNil(segment.reading)
            XCTAssertFalse(segment.isKanji)
        }
        let reconstructed = segments.map(\.text).joined()
        XCTAssertEqual(reconstructed, text)
    }

    func test_annotate_kanjiText_extractsHiraganaReadings() {
        let text = "東京"
        let segments = service.annotate(text: text)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "東京")
        XCTAssertEqual(segments.first?.reading, "とうきょう")
        XCTAssertTrue(segments.first?.isKanji == true)
    }

    func test_annotate_okuriganaSeparation() {
        let text = "食べる"
        let segments = service.annotate(text: text)

        XCTAssertEqual(segments.count, 2)
        // First segment: Kanji "食" with reading "た"
        XCTAssertEqual(segments[0].text, "食")
        XCTAssertEqual(segments[0].reading, "た")
        XCTAssertTrue(segments[0].isKanji)

        // Second segment: Okurigana "べる" with no reading
        XCTAssertEqual(segments[1].text, "べる")
        XCTAssertNil(segments[1].reading)
        XCTAssertFalse(segments[1].isKanji)
    }

    func test_annotate_fullSentence_reconstructionIntegrity() {
        let sentence = "私は東京の大学で日本語を勉強します。"
        let segments = service.annotate(text: sentence)

        let reconstructed = segments.map(\.text).joined()
        XCTAssertEqual(reconstructed, sentence)

        // Ensure key kanji tokens received readings
        let kanjiSegments = segments.filter { $0.isKanji }
        XCTAssertFalse(kanjiSegments.isEmpty)

        let kanjiTexts = kanjiSegments.map(\.text)
        XCTAssertTrue(kanjiTexts.contains("私"))
        XCTAssertTrue(kanjiTexts.contains("東京"))
        XCTAssertTrue(kanjiTexts.contains("大学"))
        XCTAssertTrue(kanjiTexts.contains("日本語") || kanjiTexts.contains("日本"))
        XCTAssertTrue(kanjiTexts.contains("勉強"))
    }

    func test_createRubyAttributedString_attachesCTRubyAttributes() {
        let text = "漢字"
        let font = NSFont.systemFont(ofSize: 14)
        let color = NSColor.labelColor

        let attrStr = service.createRubyAttributedString(text: text, font: font, textColor: color)

        XCTAssertEqual(attrStr.string, text)

        // Verify ruby attribute exists on range
        var effectiveRange = NSRange()
        let rubyAttr = attrStr.attribute(
            kCTRubyAnnotationAttributeName as NSAttributedString.Key,
            at: 0,
            effectiveRange: &effectiveRange
        )

        XCTAssertNotNil(rubyAttr)
        XCTAssertEqual(effectiveRange.location, 0)
        XCTAssertEqual(effectiveRange.length, text.utf16.count)
    }
}
