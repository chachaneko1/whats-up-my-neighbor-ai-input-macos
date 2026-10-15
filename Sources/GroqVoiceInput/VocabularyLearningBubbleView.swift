import AppKit

private enum VocabularyComicPalette {
    static let cream = NSColor(srgbRed: 1, green: 241 / 255, blue: 201 / 255, alpha: 1)
    static let highlight = NSColor(srgbRed: 1, green: 214 / 255, blue: 111 / 255, alpha: 1)
}

private final class VocabularyBubbleRejectButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        (isHighlighted ? VocabularyComicPalette.cream : VocabularyComicPalette.highlight).setFill()
        shape.fill()
        NekoAppearance.ink.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NekoAppearance.ink
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

private final class VocabularyCountdownView: NSView {
    var fraction: Double = 1 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NekoAppearance.ink.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
        NekoAppearance.ink.setFill()
        let remaining = NSRect(x: 0, y: 0, width: bounds.width * min(1, max(0, fraction)), height: bounds.height)
        NSBezierPath(roundedRect: remaining, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// Can also render in a preview with a synthetic term and image; no dictionary,
/// accessibility target, application activation, or persistence is involved.
final class VocabularyLearningBubbleView: NSView {
    static let preferredSize = NSSize(width: 480, height: 136)
    private let cat = NSImageView(frame: NSRect(x: 6, y: 41, width: 72, height: 54))
    private let question = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let reject = VocabularyBubbleRejectButton(title: "", target: nil, action: nil)
    private let countdown = VocabularyCountdownView(frame: NSRect(x: 104, y: 34, width: 140, height: 3))
    private var tracking: NSTrackingArea?
    private var isPreview = false
    private(set) var isPointerInside = false
    var onReject: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    init(term: String = "", catImage: NSImage? = NekoAppearance.catImage) {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        cat.image = catImage
        cat.imageScaling = .scaleProportionallyUpOrDown
        addSubview(cat)

        question.font = .systemFont(ofSize: 17, weight: .medium)
        question.textColor = NekoAppearance.ink
        question.maximumNumberOfLines = 3
        question.lineBreakMode = .byWordWrapping
        question.frame = NSRect(x: 104, y: 84, width: 348, height: 24)
        addSubview(question)
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = NekoAppearance.ink
        hint.frame = NSRect(x: 104, y: 51, width: 242, height: 18)
        addSubview(hint)
        addSubview(countdown)
        reject.target = self
        reject.action = #selector(rejectPending)
        reject.bezelStyle = .rounded
        reject.refusesFirstResponder = true
        reject.frame = NSRect(x: 362, y: 28, width: 90, height: 44)
        addSubview(reject)
        setTerm(term)
    }

    required init?(coder: NSCoder) { nil }

    func setTerm(_ term: String, isPreview: Bool = false) {
        self.isPreview = isPreview
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        let text = NSMutableAttributedString(string: "要將「\(term)」加入常用詞典嗎？", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NekoAppearance.ink, .paragraphStyle: paragraph
        ])
        text.addAttributes([.font: NSFont.systemFont(ofSize: 17, weight: .bold),
                            .foregroundColor: NekoAppearance.ink,
                            .backgroundColor: VocabularyComicPalette.highlight],
                           range: NSRange(location: 3, length: (term as NSString).length))
        question.attributedStringValue = text
        sizeForQuestion(text)
        hint.stringValue = isPreview ? "介面預覽，不會加入字典" : "6 秒後自動加入"
        reject.title = isPreview ? "關閉預覽" : "不加入"
        reject.setAccessibilityLabel(isPreview ? "關閉字典提示預覽" : "不將這個修正詞加入常用詞典")
        reject.needsDisplay = true
        countdown.fraction = 1
        setPointerInside(false)
    }

    private func sizeForQuestion(_ text: NSAttributedString) {
        // Match the label's text area and measure real glyph wrapping once per
        // term. A running countdown never changes the panel's dimensions.
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: question.frame.width - 4,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in
            lines += 1
        }
        let questionHeight = CGFloat(min(3, max(1, lines))) * 24
        question.setFrameSize(NSSize(width: question.frame.width, height: questionHeight))
        setFrameSize(NSSize(width: Self.preferredSize.width, height: 112 + questionHeight))
        cat.setFrameOrigin(NSPoint(x: 6, y: (bounds.height - cat.frame.height) / 2))
        needsDisplay = true
    }

    /// The presentation lifecycle owns the clock; the view only renders it.
    func setCountdown(remaining: TimeInterval, total: TimeInterval, paused: Bool) {
        let safeRemaining = remaining.isFinite ? max(0, remaining) : 0
        let safeTotal = total.isFinite && total > 0 ? total : 1
        countdown.fraction = min(1, safeRemaining / safeTotal)
        if isPreview {
            hint.stringValue = paused ? "預覽不會加入字典・倒數暫停" : "介面預覽，不會加入字典"
        } else {
            hint.stringValue = paused ? "倒數暫停中" : "\(Int(ceil(min(safeRemaining, safeTotal)))) 秒後自動加入"
        }
        // Also catches a pointer already inside when the panel first appears,
        // plus movement of the panel underneath a stationary pointer.
        refreshPointerLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self)
        addTrackingArea(area)
        tracking = area
        refreshPointerLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshPointerLocation()
    }

    override func mouseEntered(with event: NSEvent) { refreshPointerLocation() }
    override func mouseMoved(with event: NSEvent) { refreshPointerLocation() }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    func refreshPointerLocation() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else {
            setPointerInside(false)
            return
        }
        setPointerInside(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        onHoverChanged?(inside)
    }

    @objc private func rejectPending() { onReject?() }

    override func draw(_ dirtyRect: NSRect) {
        let catBase = NSRect(x: 4, y: (bounds.height - 56) / 2, width: 76, height: 56)
        let base = NSBezierPath(roundedRect: catBase, xRadius: 14, yRadius: 14)
        VocabularyComicPalette.cream.setFill()
        NekoAppearance.ink.setStroke()
        base.fill()
        base.lineWidth = 2
        base.stroke()

        let rect = NSRect(x: 88, y: 12, width: 380, height: bounds.height - 24)
        let radius: CGFloat = 16
        let mouthY = catBase.midY - 12
        // One continuous contour keeps the short speech tail free of an inner seam.
        let bubble = NSBezierPath()
        bubble.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
        bubble.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        bubble.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                         startAngle: 270, endAngle: 360, clockwise: false)
        bubble.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        bubble.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                         startAngle: 0, endAngle: 90, clockwise: false)
        bubble.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        bubble.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
                         startAngle: 90, endAngle: 180, clockwise: false)
        bubble.line(to: NSPoint(x: rect.minX, y: mouthY + 8))
        bubble.line(to: NSPoint(x: 78, y: mouthY))
        bubble.line(to: NSPoint(x: rect.minX, y: mouthY - 8))
        bubble.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        bubble.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                         startAngle: 180, endAngle: 270, clockwise: false)
        bubble.close()
        VocabularyComicPalette.cream.setFill()
        bubble.fill()
        bubble.lineWidth = 2
        NekoAppearance.ink.setStroke()
        bubble.stroke()
    }
}
