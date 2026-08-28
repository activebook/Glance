import Foundation
import CoreText
import AppKit

/// Represents an individual text segment with an optional Furigana (Ruby) phonetic reading.
public struct FuriganaSegment: Identifiable, Equatable {
    public var id: String { "\(text)_\(reading ?? "")" }
    public let text: String
    public let reading: String?

    public var isKanji: Bool {
        reading != nil && FuriganaService.containsKanji(text)
    }

    public init(text: String, reading: String? = nil) {
        self.text = text
        self.reading = reading
    }
}

/// Native morphological analyzer and Furigana (Ruby text) generator for Japanese Kanji.
///
/// Utilizes Apple's built-in CoreFoundation linguistic engine (CFStringTokenizer)
/// and CoreText CTRubyAnnotation to generate and render sub-pixel accurate Ruby typography
/// with zero external dependencies and zero bundled dictionary asset overhead.
public final class FuriganaService {
    public static let shared = FuriganaService()

    private init() {}

    /// Checks if a string contains any Japanese CJK Unified Ideographs (Kanji).
    public static func containsKanji(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    /// Tokenizes Japanese text and generates aligned Furigana segments for Kanji components.
    public func annotate(text: String) -> [FuriganaSegment] {
        guard !text.isEmpty else { return [] }
        guard Self.containsKanji(text) else {
            return [FuriganaSegment(text: text, reading: nil)]
        }

        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        guard length > 0 else { return [] }

        let range = CFRangeMake(0, length)
        let locale = Locale(identifier: "ja_JP") as CFLocale

        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            range,
            kCFStringTokenizerUnitWordBoundary,
            locale
        ) else {
            return [FuriganaSegment(text: text, reading: nil)]
        }

        var segments: [FuriganaSegment] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        var lastEndLocation = 0

        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)

            // Capture any leading non-token whitespace/symbols between tokens
            if tokenRange.location > lastEndLocation {
                let gapRange = NSRange(location: lastEndLocation, length: tokenRange.location - lastEndLocation)
                let gapString = (text as NSString).substring(with: gapRange)
                segments.append(FuriganaSegment(text: gapString, reading: nil))
            }

            let tokenString = (text as NSString).substring(
                with: NSRange(location: tokenRange.location, length: tokenRange.length)
            )

            if Self.containsKanji(tokenString),
               let latinRef = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) {
                let mutableReading = NSMutableString(string: latinRef as! String)
                CFStringTransform(mutableReading, nil, kCFStringTransformLatinHiragana, false)
                let hiragana = mutableReading as String

                // Align okurigana (e.g. 食べる -> 食[た] + べる)
                let alignedSegments = alignFurigana(token: tokenString, reading: hiragana)
                segments.append(contentsOf: alignedSegments)
            } else {
                segments.append(FuriganaSegment(text: tokenString, reading: nil))
            }

            lastEndLocation = tokenRange.location + tokenRange.length
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // Capture any trailing string after the last token
        if lastEndLocation < length {
            let trailRange = NSRange(location: lastEndLocation, length: length - lastEndLocation)
            let trailString = (text as NSString).substring(with: trailRange)
            segments.append(FuriganaSegment(text: trailString, reading: nil))
        }

        return segments
    }

    /// Aligns okurigana (leading/trailing kana) so furigana applies strictly to Kanji characters.
    private func alignFurigana(token: String, reading: String) -> [FuriganaSegment] {
        guard Self.containsKanji(token) else {
            return [FuriganaSegment(text: token, reading: nil)]
        }

        let tokenChars = Array(token)
        let readingChars = Array(reading)

        // 1. Identify common Hiragana prefix (e.g. お茶 -> お + 茶[ちゃ])
        var prefixLen = 0
        while prefixLen < tokenChars.count && prefixLen < readingChars.count {
            if tokenChars[prefixLen] == readingChars[prefixLen] && !Self.containsKanji(String(tokenChars[prefixLen])) {
                prefixLen += 1
            } else {
                break
            }
        }

        // 2. Identify common Hiragana suffix (e.g. 食べる -> 食[た] + べる)
        var suffixTokenLen = 0
        var suffixReadingLen = 0
        while suffixTokenLen < (tokenChars.count - prefixLen) && suffixReadingLen < (readingChars.count - prefixLen) {
            let tIdx = tokenChars.count - 1 - suffixTokenLen
            let rIdx = readingChars.count - 1 - suffixReadingLen
            if tokenChars[tIdx] == readingChars[rIdx] && !Self.containsKanji(String(tokenChars[tIdx])) {
                suffixTokenLen += 1
                suffixReadingLen += 1
            } else {
                break
            }
        }

        var result: [FuriganaSegment] = []

        // Prefix segment
        if prefixLen > 0 {
            let prefixStr = String(tokenChars[0..<prefixLen])
            result.append(FuriganaSegment(text: prefixStr, reading: nil))
        }

        // Core Kanji segment
        let coreTokenStart = prefixLen
        let coreTokenEnd = tokenChars.count - suffixTokenLen
        let coreReadingStart = prefixLen
        let coreReadingEnd = readingChars.count - suffixReadingLen

        if coreTokenStart < coreTokenEnd {
            let coreToken = String(tokenChars[coreTokenStart..<coreTokenEnd])
            let coreReading = coreReadingStart <= coreReadingEnd ? String(readingChars[coreReadingStart..<coreReadingEnd]) : ""
            result.append(FuriganaSegment(text: coreToken, reading: coreReading.isEmpty ? nil : coreReading))
        }

        // Suffix segment
        if suffixTokenLen > 0 {
            let suffixStr = String(tokenChars[(tokenChars.count - suffixTokenLen)...])
            result.append(FuriganaSegment(text: suffixStr, reading: nil))
        }

        return result.isEmpty ? [FuriganaSegment(text: token, reading: reading)] : result
    }

    /// Creates an NSAttributedString equipped with native CoreText CTRubyAnnotation attributes.
    public func createRubyAttributedString(
        text: String,
        font: NSFont,
        textColor: NSColor,
        rubySizeFactor: CGFloat = 0.6
    ) -> NSAttributedString {
        let segments = annotate(text: text)
        let attributedString = NSMutableAttributedString()

        for segment in segments {
            if let reading = segment.reading, segment.isKanji {
                let rubyAttributes: [CFString: Any] = [
                    kCTRubyAnnotationSizeFactorAttributeName: rubySizeFactor
                ]

                let annotation = CTRubyAnnotationCreateWithAttributes(
                    .auto,              // Auto horizontal center alignment
                    .auto,              // Auto overhang allowance
                    .before,            // Position above base text
                    reading as CFString,
                    rubyAttributes as CFDictionary
                )

                let tokenAttr = NSMutableAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                )

                tokenAttr.addAttribute(
                    kCTRubyAnnotationAttributeName as NSAttributedString.Key,
                    value: annotation,
                    range: NSRange(location: 0, length: segment.text.utf16.count)
                )

                attributedString.append(tokenAttr)
            } else {
                attributedString.append(NSAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                ))
            }
        }

        return attributedString
    }
}
