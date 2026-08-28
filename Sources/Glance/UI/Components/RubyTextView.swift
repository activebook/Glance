import SwiftUI
import AppKit
import CoreText

/// A SwiftUI view that renders text with native CoreText Ruby annotations (振仮名)
/// above Japanese Kanji characters when Furigana is enabled.
public struct RubyTextView: View {
    let text: String
    let fontSize: CGFloat
    let fontWeight: NSFont.Weight
    let textColor: Color
    let showFurigana: Bool
    let rubyScaleFactor: CGFloat
    let lineSpacing: CGFloat

    public init(
        text: String,
        fontSize: CGFloat = 13,
        fontWeight: NSFont.Weight = .regular,
        textColor: Color = .primary,
        showFurigana: Bool = true,
        rubyScaleFactor: CGFloat = 0.6,
        lineSpacing: CGFloat = 3
    ) {
        self.text = text
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textColor = textColor
        self.showFurigana = showFurigana
        self.rubyScaleFactor = rubyScaleFactor
        self.lineSpacing = lineSpacing
    }

    private var hasKanji: Bool {
        FuriganaService.containsKanji(text)
    }

    private var swiftUIFontWeight: Font.Weight {
        switch fontWeight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        case .thin: return .thin
        default: return .regular
        }
    }

    public var body: some View {
        if showFurigana && hasKanji {
            CoreTextRubyRepresentable(
                text: text,
                font: NSFont.systemFont(ofSize: fontSize, weight: fontWeight),
                textColor: NSColor(textColor),
                rubyScaleFactor: rubyScaleFactor,
                lineSpacing: lineSpacing
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: fontSize, weight: swiftUIFontWeight))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .lineSpacing(lineSpacing)
        }
    }
}

// MARK: - Native CoreText Ruby View

struct CoreTextRubyRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let rubyScaleFactor: CGFloat
    let lineSpacing: CGFloat

    func makeNSView(context: Context) -> CoreTextRubyNSView {
        let view = CoreTextRubyNSView()
        view.update(text: text, font: font, textColor: textColor, rubyScaleFactor: rubyScaleFactor, lineSpacing: lineSpacing)
        return view
    }

    func updateNSView(_ nsView: CoreTextRubyNSView, context: Context) {
        nsView.update(text: text, font: font, textColor: textColor, rubyScaleFactor: rubyScaleFactor, lineSpacing: lineSpacing)
    }
}

final class CoreTextRubyNSView: NSView {
    private var attributedString: NSAttributedString?
    private var framesetter: CTFramesetter?
    private var currentText: String = ""
    private var currentFont: NSFont = NSFont.systemFont(ofSize: 13)
    private var currentTextColor: NSColor = .labelColor
    private var currentRubyScaleFactor: CGFloat = 0.6
    private var currentLineSpacing: CGFloat = 3
    private var lastBoundsWidth: CGFloat = 0

    // Selection state
    private var selectedRange: NSRange? = nil
    private var selectionAnchor: Int? = nil

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func update(text: String, font: NSFont, textColor: NSColor, rubyScaleFactor: CGFloat, lineSpacing: CGFloat) {
        guard text != currentText || font != currentFont || textColor != currentTextColor || rubyScaleFactor != currentRubyScaleFactor || lineSpacing != currentLineSpacing else {
            return
        }

        self.currentText = text
        self.currentFont = font
        self.currentTextColor = textColor
        self.currentRubyScaleFactor = rubyScaleFactor
        self.currentLineSpacing = lineSpacing
        self.selectedRange = nil
        self.selectionAnchor = nil

        let attr = FuriganaService.shared.createRubyAttributedString(
            text: text,
            font: font,
            textColor: textColor,
            rubySizeFactor: rubyScaleFactor
        )

        let mutable = NSMutableAttributedString(attributedString: attr)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(lineSpacing, 4)
        paragraph.paragraphSpacing = 4
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))

        self.attributedString = mutable
        self.framesetter = CTFramesetterCreateWithAttributedString(mutable as CFAttributedString)
        self.lastBoundsWidth = 0
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 && abs(bounds.width - lastBoundsWidth) > 1.0 {
            lastBoundsWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let framesetter = framesetter, let attr = attributedString, attr.length > 0 else {
            return .zero
        }
        let width = bounds.width > 0 ? bounds.width : 400
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRangeMake(0, attr.length),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(suggested.height) + 6)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext,
              let framesetter = framesetter,
              let attr = attributedString,
              attr.length > 0 else {
            return
        }

        let path = CGPath(rect: CGRect(x: 0, y: 2, width: bounds.width, height: bounds.height - 2), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attr.length), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)

        // 1. Draw selection highlight in CoreText coordinates
        if let sel = selectedRange, sel.length > 0 {
            context.saveGState()
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4).setFill()

            for i in 0..<lines.count {
                let line = lines[i]
                let cfRange = CTLineGetStringRange(line)
                let lineRange = NSRange(location: cfRange.location, length: cfRange.length)

                let intersection = NSIntersectionRange(lineRange, sel)
                if intersection.length > 0 {
                    var ascent: CGFloat = 0
                    var descent: CGFloat = 0
                    var leading: CGFloat = 0
                    CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

                    let startX = origins[i].x + CTLineGetOffsetForStringIndex(line, intersection.location, nil)
                    let endX = origins[i].x + CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, nil)
                    let highlightRect = CGRect(
                        x: min(startX, endX),
                        y: origins[i].y - descent - 2,
                        width: abs(endX - startX),
                        height: ascent + descent + 6
                    )

                    let clipPath = CGPath(roundedRect: highlightRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    context.addPath(clipPath)
                    context.fillPath()
                }
            }
            context.restoreGState()
        }

        // 2. Draw CoreText Ruby Frame
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    // MARK: - String Index & Boundary Lookup

    private func stringIndex(at point: NSPoint) -> Int {
        guard let framesetter = framesetter, let attr = attributedString, attr.length > 0 else { return 0 }
        let path = CGPath(rect: CGRect(x: 0, y: 2, width: bounds.width, height: bounds.height - 2), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attr.length), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return 0 }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)

        for i in 0..<lines.count {
            let line = lines[i]
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let flippedBaselineY = bounds.height - origins[i].y
            let lineTop = flippedBaselineY - ascent
            let lineBottom = flippedBaselineY + descent + leading

            if point.y >= lineTop - 4 && point.y <= lineBottom + 4 || (i == lines.count - 1 && point.y > lineBottom) {
                let relativeX = point.x - origins[i].x
                let idx = CTLineGetStringIndexForPosition(line, CGPoint(x: relativeX, y: 0))
                return max(0, min(idx, attr.length))
            }
        }
        return attr.length
    }

    private func wordRange(at index: Int) -> NSRange {
        let ns = currentText as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = max(0, min(index, ns.length - 1))

        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            currentText as CFString,
            CFRangeMake(0, ns.length),
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja_JP") as CFLocale
        )

        let tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, clamped)
        if tokenType != [] {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if cfRange.location != kCFNotFound && cfRange.length > 0 {
                return NSRange(location: cfRange.location, length: cfRange.length)
            }
        }
        return ns.rangeOfComposedCharacterSequence(at: clamped)
    }

    // MARK: - Mouse & Selection Interaction

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let idx = stringIndex(at: point)

        if event.clickCount == 1 {
            selectionAnchor = idx
            selectedRange = nil
        } else if event.clickCount == 2 {
            selectedRange = wordRange(at: idx)
            selectionAnchor = selectedRange?.location
        } else if event.clickCount >= 3 {
            selectedRange = NSRange(location: 0, length: (currentText as NSString).length)
            selectionAnchor = 0
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectionAnchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        let curr = stringIndex(at: point)

        let start = min(anchor, curr)
        let end = max(anchor, curr)
        selectedRange = NSRange(location: start, length: end - start)
        needsDisplay = true
    }

    // MARK: - Context Menu & Clipboard Actions

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let idx = stringIndex(at: point)

        if let sel = selectedRange, sel.length > 0 {
            if !NSLocationInRange(idx, sel) {
                selectedRange = wordRange(at: idx)
                needsDisplay = true
            }
        } else {
            selectedRange = wordRange(at: idx)
            needsDisplay = true
        }

        let menu = NSMenu(title: "Text Actions")

        let hasSelection = (selectedRange?.length ?? 0) > 0
        let copyItem = NSMenuItem(
            title: hasSelection ? "Copy" : "Copy All",
            action: #selector(copySelectedText(_:)),
            keyEquivalent: "c"
        )
        copyItem.target = self
        menu.addItem(copyItem)

        if hasSelection {
            let copyAllItem = NSMenuItem(
                title: "Copy Entire Text",
                action: #selector(copyFullText(_:)),
                keyEquivalent: ""
            )
            copyAllItem.target = self
            menu.addItem(copyAllItem)
        }

        menu.addItem(NSMenuItem.separator())

        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(selectAllText(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        return menu
    }

    @objc func copySelectedText(_ sender: Any?) {
        let ns = currentText as NSString
        let toCopy: String
        if let sel = selectedRange, sel.length > 0 && sel.location + sel.length <= ns.length {
            toCopy = ns.substring(with: sel)
        } else {
            toCopy = currentText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(toCopy, forType: .string)
    }

    @objc func copyFullText(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentText, forType: .string)
    }

    @objc func selectAllText(_ sender: Any?) {
        selectedRange = NSRange(location: 0, length: (currentText as NSString).length)
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "c" {
                copySelectedText(self)
                return true
            } else if event.charactersIgnoringModifiers == "a" {
                selectAllText(self)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
