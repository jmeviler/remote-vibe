import AppKit

enum ButtonRole {
    case primary
    case secondary
    case destructive
}

final class StyledButton: NSButton {
    var role: ButtonRole = .primary {
        didSet {
            if oldValue != role { needsDisplay = true }
        }
    }
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var title: String { didSet { needsDisplay = true } }

    init(title: String, target: AnyObject? = nil, action: Selector? = nil, role: ButtonRole = .primary) {
        self.role = role
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 12.5, weight: role == .secondary ? .medium : .semibold)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyRole() { needsDisplay = true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder(); needsDisplay = true; return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder(); needsDisplay = true; return ok
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 10
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let fill: NSColor
        let stroke: NSColor?
        let textColor: NSColor

        if !isEnabled {
            fill = SettingsTheme.adaptive(light: 0xECEFE8, dark: 0x212924)
            stroke = SettingsTheme.adaptive(light: 0xDDE2D8, dark: 0x2C3730)
            textColor = SettingsTheme.adaptive(light: 0x97A198, dark: 0x5E6C62)
        } else {
            switch role {
            case .primary:
                fill = isHighlighted ? SettingsTheme.adaptive(light: 0x263728, dark: 0x38573C) :
                    hovered ? SettingsTheme.adaptive(light: 0x3E5741, dark: 0x4E7653) : SettingsTheme.forest
                stroke = nil
                textColor = .white
            case .secondary:
                fill = isHighlighted ? SettingsTheme.adaptive(light: 0xE0E5DA, dark: 0x2E3A33) :
                    hovered ? SettingsTheme.adaptive(light: 0xEEF1EA, dark: 0x28332C) :
                    SettingsTheme.adaptive(light: 0xF7F8F4, dark: 0x222B25)
                stroke = SettingsTheme.adaptive(light: 0xD2D8CC, dark: 0x35433A)
                textColor = SettingsTheme.ink
            case .destructive:
                fill = isHighlighted ? SettingsTheme.color(0x6D2B1F) :
                    hovered ? SettingsTheme.color(0x963E2D) : SettingsTheme.destructiveFill
                stroke = nil
                textColor = .white
            }
        }

        fill.setFill()
        shape.fill()
        if let stroke {
            stroke.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }

        let weight: NSFont.Weight = (role == .secondary || !isEnabled) ? .medium : .semibold
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: weight),
            .foregroundColor: textColor
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )

        if window?.firstResponder === self {
            SettingsTheme.forest.withAlphaComponent(0.75).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

final class StyledPopUpButton: NSPopUpButton {
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func select(_ item: NSMenuItem?) {
        super.select(item)
        needsDisplay = true
    }

    override func selectItem(at index: Int) {
        super.selectItem(at: index)
        needsDisplay = true
    }

    override func selectItem(withTitle title: String) {
        super.selectItem(withTitle: title)
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder(); needsDisplay = true; return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder(); needsDisplay = true; return ok
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 10
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let fill = !isEnabled ? SettingsTheme.adaptive(light: 0xEFF1EC, dark: 0x1E2621) :
            hovered ? SettingsTheme.adaptive(light: 0xF5F6F1, dark: 0x26302A) : SettingsTheme.paper
        let border = !isEnabled ? SettingsTheme.line.withAlphaComponent(0.65) :
            hovered ? SettingsTheme.adaptive(light: 0xB9C3B4, dark: 0x435448) :
            SettingsTheme.adaptive(light: 0xD4DACF, dark: 0x334038)

        fill.setFill()
        shape.fill()
        border.setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let currentTitle = titleOfSelectedItem ?? ""
        let textFont = font ?? NSFont.systemFont(ofSize: 13, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: isEnabled ? SettingsTheme.ink : SettingsTheme.secondary.withAlphaComponent(0.65),
            .paragraphStyle: paragraph
        ]
        let textHeight = (currentTitle as NSString).size(withAttributes: attrs).height
        let textRect = NSRect(x: 13, y: (bounds.height - textHeight) / 2, width: max(20, bounds.width - 42), height: textHeight + 2)
        (currentTitle as NSString).draw(in: textRect, withAttributes: attrs)

        let chevronRect = NSRect(x: bounds.width - 25, y: (bounds.height - 13) / 2, width: 13, height: 13)
        SettingsTheme.symbol("chevron.up.chevron.down", in: chevronRect, muted: true)

        if window?.firstResponder === self {
            SettingsTheme.forest.withAlphaComponent(0.75).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

final class StyledSegmentedControl: NSSegmentedControl {
    enum SurfaceStyle {
        case surface
        case darkStage
    }

    var surfaceStyle: SurfaceStyle = .surface { didSet { needsDisplay = true } }
    var configuredSegments: Set<Int> = [] { didSet { if oldValue != configuredSegments { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var selectedSegment: Int {
        get { super.selectedSegment }
        set { super.selectedSegment = newValue; needsDisplay = true }
    }

    override func setLabel(_ label: String, forSegment segment: Int) {
        super.setLabel(label, forSegment: segment)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, segmentCount > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let width = bounds.width / CGFloat(segmentCount)
        let index = max(0, min(segmentCount - 1, Int(point.x / max(1, width))))
        guard isEnabled(forSegment: index) else { return }
        selectedSegment = index
        if let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard segmentCount > 0 else { return }
        let trackRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let trackRadius: CGFloat = 10
        let track = NSBezierPath(roundedRect: trackRect, xRadius: trackRadius, yRadius: trackRadius)

        switch surfaceStyle {
        case .surface:
            SettingsTheme.adaptive(light: 0xE6EAE1, dark: 0x161D19).setFill()
            track.fill()
            SettingsTheme.adaptive(light: 0xD8DFD2, dark: 0x2A362E).setStroke()
            track.lineWidth = 1
            track.stroke()
        case .darkStage:
            SettingsTheme.color(0x161E19).setFill()
            track.fill()
            SettingsTheme.color(0x2F3E34).setStroke()
            track.lineWidth = 1
            track.stroke()
        }

        let inset: CGFloat = 3
        let innerWidth = (bounds.width - inset * 2) / CGFloat(segmentCount)
        let innerHeight = bounds.height - inset * 2
        let baseFont = font ?? NSFont.systemFont(ofSize: 12.5, weight: .medium)

        for idx in 0..<segmentCount {
            let segRect = NSRect(x: inset + CGFloat(idx) * innerWidth, y: inset, width: innerWidth, height: innerHeight)
            let isSelected = isEnabled && idx == selectedSegment
            if isSelected {
                let pill = NSBezierPath(roundedRect: segRect, xRadius: 7.5, yRadius: 7.5)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(surfaceStyle == .darkStage ? 0.25 : 0.08)
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 2.5
                shadow.set()
                switch surfaceStyle {
                case .surface:
                    SettingsTheme.adaptive(light: 0xFFFFFF, dark: 0x355039).setFill()
                case .darkStage:
                    SettingsTheme.color(0x3B593F).setFill()
                }
                pill.fill()
                NSGraphicsContext.restoreGraphicsState()

                switch surfaceStyle {
                case .surface:
                    SettingsTheme.adaptive(light: 0xD2D9CC, dark: 0x4A6D4F).setStroke()
                case .darkStage:
                    SettingsTheme.color(0x527657).setStroke()
                }
                pill.lineWidth = 0.8
                pill.stroke()
            }

            let rawTitle = label(forSegment: idx) ?? ""
            let textColor: NSColor
            if !isEnabled || !isEnabled(forSegment: idx) {
                textColor = surfaceStyle == .darkStage ? SettingsTheme.color(0x5A695E) : SettingsTheme.secondary.withAlphaComponent(0.5)
            } else if isSelected {
                textColor = surfaceStyle == .darkStage ? .white : SettingsTheme.adaptive(light: 0x1B241E, dark: 0xFFFFFF)
            } else {
                textColor = surfaceStyle == .darkStage ? SettingsTheme.color(0x95A698) : SettingsTheme.secondary
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: isSelected ? .semibold : .medium),
                .foregroundColor: textColor
            ]
            let size = (rawTitle as NSString).size(withAttributes: attrs)
            let hasDot = configuredSegments.contains(idx) && isEnabled
            let totalWidth = size.width + (hasDot ? 11 : 0)
            let textX = segRect.midX - totalWidth / 2
            let textY = segRect.midY - size.height / 2
            (rawTitle as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            if hasDot {
                let dotColor = (isSelected && surfaceStyle == .darkStage) ? NSColor.white : SettingsTheme.accentDot
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: textX + size.width + 5.5, y: segRect.midY - 2.5, width: 5, height: 5)).fill()
            }
        }
    }
}

private final class PlainSearchFieldCell: NSSearchFieldCell {
    private var adjustingEditor = false

    override init(textCell string: String) {
        super.init(textCell: string)
        configureCell()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configureCell()
    }

    private func configureCell() {
        searchButtonCell = nil
        cancelButtonCell = nil
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        wraps = false
        isScrollable = true
        lineBreakMode = .byTruncatingTail
    }

    private func textRect(for bounds: NSRect) -> NSRect {
        let resolvedFont = font ?? NSFont.systemFont(ofSize: 12)
        let lineHeight = ceil(("Ag搜" as NSString).size(withAttributes: [.font: resolvedFont]).height)
        let y = bounds.minY + max(0, floor((bounds.height - lineHeight) * 2) / 2)
        return NSRect(x: bounds.minX, y: y, width: max(12, bounds.width - 2), height: min(bounds.height, lineHeight))
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect { .zero }

    override func drawingRect(forBounds theRect: NSRect) -> NSRect {
        adjustingEditor ? theRect : textRect(for: theRect)
    }

    override func titleRect(forBounds theRect: NSRect) -> NSRect {
        adjustingEditor ? theRect : textRect(for: theRect)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        adjustingEditor ? rect : textRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let target = textRect(for: rect)
        (textObj as? NSTextView)?.insertionPointColor = SettingsTheme.forest
        adjustingEditor = true
        super.edit(withFrame: target, in: controlView, editor: textObj, delegate: delegate, event: event)
        adjustingEditor = false
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let target = textRect(for: rect)
        (textObj as? NSTextView)?.insertionPointColor = SettingsTheme.forest
        adjustingEditor = true
        super.select(withFrame: target, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        adjustingEditor = false
    }
}

final class PlainSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { PlainSearchFieldCell.self }
        set {}
    }

    var onStateChange: (() -> Void)?

    override var stringValue: String {
        didSet { onStateChange?() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if !(cell is PlainSearchFieldCell) {
            cell = PlainSearchFieldCell(textCell: "")
        }
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        sendsSearchStringImmediately = true
        font = .systemFont(ofSize: 12)
        textColor = SettingsTheme.ink
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStyledPlaceholder(_ text: String) {
        let resolvedFont = font ?? .systemFont(ofSize: 12)
        placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: resolvedFont,
                .foregroundColor: SettingsTheme.placeholder
            ]
        )
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        onStateChange?()
    }

    override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        DispatchQueue.main.async { [weak self] in self?.onStateChange?() }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onStateChange?()
    }

    override func cancelOperation(_ sender: Any?) {
        if !stringValue.isEmpty {
            stringValue = ""
            if let action { NSApp.sendAction(action, to: target, from: self) }
            onStateChange?()
        } else {
            window?.makeFirstResponder(nil)
        }
    }
}

final class ActionSearchBar: NSView {
    let searchField = PlainSearchField(frame: .zero)
    override var isFlipped: Bool { true }

    var isEditingSearch: Bool {
        guard let window else { return false }
        if window.firstResponder === searchField { return true }
        if let editor = searchField.currentEditor(), window.firstResponder === editor { return true }
        return false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(searchField)
        searchField.onStateChange = { [weak self] in
            self?.needsLayout = true
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let leftInset: CGFloat = 27
        let rightInset: CGFloat = searchField.stringValue.isEmpty ? 8 : 25
        searchField.frame = NSRect(
            x: leftInset,
            y: 0,
            width: max(24, bounds.width - leftInset - rightInset),
            height: bounds.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !searchField.stringValue.isEmpty && point.x >= bounds.width - 25 {
            searchField.stringValue = ""
            if let action = searchField.action {
                NSApp.sendAction(action, to: searchField.target, from: searchField)
            }
            window?.makeFirstResponder(searchField)
            needsLayout = true
            needsDisplay = true
            return
        }
        window?.makeFirstResponder(searchField)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let focused = isEditingSearch
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 9
        let pill = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (focused ? SettingsTheme.paper : SettingsTheme.subtleFill).setFill()
        pill.fill()
        (focused ? SettingsTheme.forest : SettingsTheme.line).setStroke()
        pill.lineWidth = focused ? 1.5 : 1
        pill.stroke()

        let iconSize: CGFloat = 13
        let iconRect = NSRect(x: 10, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        SettingsTheme.symbol("magnifyingglass", in: iconRect, muted: !focused)

        if !searchField.stringValue.isEmpty {
            let clearRect = NSRect(x: bounds.width - iconSize - 8, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            SettingsTheme.symbol("xmark.circle.fill", in: clearRect, muted: true)
        }
    }
}

enum SettingsTheme {
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(isDark ? dark : light)
        }
    }

    static let canvas = adaptive(light: 0xF2F3EE, dark: 0x131815)
    static let paper = adaptive(light: 0xFCFCF9, dark: 0x1C231F)
    static let subtleFill = adaptive(light: 0xEAECE5, dark: 0x242E28)
    static let ink = adaptive(light: 0x202923, dark: 0xECF1EC)
    static let secondary = adaptive(light: 0x626E65, dark: 0x99A89C)
    static let placeholder = adaptive(light: 0x7D887F, dark: 0x829186)
    static let line = adaptive(light: 0xDFE3DA, dark: 0x2E3A32)
    static let forest = adaptive(light: 0x344936, dark: 0x456949)
    static let stage = adaptive(light: 0x202B25, dark: 0x17201B)
    static let accentDot = adaptive(light: 0x3B7A44, dark: 0x69D178)
    static let warning = adaptive(light: 0xB8621B, dark: 0xF0A04B)
    static let error = adaptive(light: 0xA3422C, dark: 0xEB6F56)
    static let destructiveFill = adaptive(light: 0x843727, dark: 0x9F4330)

    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = secondary) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        return view
    }

    static func eyebrow(_ text: String, light: Bool = false) -> NSTextField {
        label(text, size: 11, weight: .semibold, color: light ? color(0xABBCA9) : secondary)
    }

    static func style(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 13)
        field.textColor = ink
        field.backgroundColor = paper
        field.focusRingType = .exterior
    }

    static func button(_ title: String, target: AnyObject? = nil, action: Selector? = nil,
                       destructive: Bool = false, role: ButtonRole? = nil) -> StyledButton {
        let resolvedRole = role ?? (destructive ? .destructive : .primary)
        return StyledButton(title: title, target: target, action: action, role: resolvedRole)
    }

    static func secondaryButton(_ title: String, target: AnyObject? = nil, action: Selector? = nil) -> StyledButton {
        StyledButton(title: title, target: target, action: action, role: .secondary)
    }

    // Cache fixed app symbols in explicit tint variants so Light and Dark modes stay crisp.
    private static var symbols: [String: NSImage] = [:]
    static func symbol(_ name: String, in rect: NSRect, onDark: Bool = false, muted: Bool = false) {
        let isDarkAppearance = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let variant = onDark ? "white" : muted ? (isDarkAppearance ? "darkMuted" : "lightMuted") : (isDarkAppearance ? "darkInk" : "lightInk")
        let key = "\(name)/\(variant)"
        if symbols[key] == nil {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) else { return }
            let tint: NSColor
            if onDark {
                tint = .white
            } else if muted {
                tint = isDarkAppearance ? color(0x99A89C) : color(0x626E65)
            } else {
                tint = isDarkAppearance ? color(0xECF1EC) : color(0x202923)
            }
            let tinted = NSImage(size: base.size, flipped: false) { bounds in
                base.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                tint.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            symbols[key] = tinted
        }
        guard let image = symbols[key] else { return }
        let factor = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

class SettingsPanel: NSView {
    var fill: NSColor = SettingsTheme.paper { didSet { needsDisplay = true } }
    var border: NSColor? = SettingsTheme.line { didSet { needsDisplay = true } }
    var radius: CGFloat = 22 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
}

final class StatusDotView: NSView {
    var isReady = true { didSet { if oldValue != isReady { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = 7.5
        let dotRect = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        (isReady ? SettingsTheme.accentDot : SettingsTheme.error).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

// Reflow columns horizontally while keeping readable type and control heights.
// Capture the authored geometry once so repeated resizing never accumulates drift.
class SettingsPage: NSView {
    private var authoredWidth: CGFloat = 0
    private var authoredFrames: [(NSView, NSRect)] = []
    override var isFlipped: Bool { true }

    func captureHorizontalLayout() {
        authoredWidth = bounds.width
        authoredFrames = subviews.map { ($0, $0.frame) }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard authoredWidth > 0 else { super.resizeSubviews(withOldSize: oldSize); return }
        let scale = bounds.width / authoredWidth
        for (view, original) in authoredFrames {
            view.frame = NSRect(x: original.minX * scale, y: original.minY,
                                width: original.width * scale, height: original.height)
        }
    }
}

final class SettingsScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let size = NSSize(width: max(1, contentSize.width), height: max(SettingsView.size.height, contentSize.height))
        if documentView.frame.size != size { documentView.setFrameSize(size) }
    }
}

final class RemoteStage: SettingsPanel {
    override init(frame: NSRect) {
        super.init(frame: frame)
        fill = SettingsTheme.stage; border = SettingsTheme.color(0x2F3E34); radius = 24
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        SettingsTheme.color(0x3C4D3F).withAlphaComponent(0.55).setStroke()
        for radius in stride(from: CGFloat(125), through: 245, by: 40) {
            let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 0.7; ring.stroke()
        }
        SettingsTheme.color(0x435543).setFill()
        for x in stride(from: CGFloat(22), through: bounds.width - 20, by: 24) {
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.height - 50, width: 1.5, height: 1.5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ActionPreview: SettingsPanel {
    var binding: ButtonAction? { didSet { needsDisplay = true } }
    var voice = false { didSet { needsDisplay = true } }
    var hasGestures = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        fill = SettingsTheme.subtleFill; border = nil; radius = 12
        super.draw(dirtyRect)
        func text(_ value: String, at point: NSPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .medium) {
            (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        if let binding, binding.kind == .key, !voice {
            let flags = CGEventFlags(rawValue: binding.modifiers)
            var keys = [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "Fn")]
                .filter { flags.contains($0.0) }.map { $0.1 }
            let symbols: [UInt64: String] = [0: "Fn", 0x28: "⏎", 0x2A: "⌫", 0x29: "esc", 0x2B: "⇥", 0x2C: "space",
                                             0x52: "↑", 0x51: "↓", 0x50: "←", 0x4F: "→"]
            keys.append(symbols[binding.usage] ?? binding.key?.name ?? "key")
            var x: CGFloat = 17
            for key in keys {
                let width = max(48, min(125, CGFloat(key.count) * 14 + 22))
                let cap = NSBezierPath(roundedRect: NSRect(x: x, y: 16, width: width, height: 48), xRadius: 10, yRadius: 10)
                SettingsTheme.paper.setFill(); cap.fill(); SettingsTheme.line.setStroke(); cap.stroke()
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: key.count > 3 ? 17 : 24, weight: .medium), .foregroundColor: SettingsTheme.ink]
                let size = (key as NSString).size(withAttributes: attrs)
                (key as NSString).draw(at: NSPoint(x: x + (width - size.width) / 2, y: 16 + (48 - size.height) / 2), withAttributes: attrs)
                x += width + 8
            }
            let caption: String
            if binding.isFn {
                caption = L("仅按住键盘 Fn 键 · 不开启遥控器麦克风")
            } else if !hasGestures && !binding.usesListener {
                caption = L("系统级改键 · 直接发给当前软件（免额外权限）")
            } else {
                caption = L("向当前软件发送按键 · 按一次触发一次")
            }
            text(caption, at: NSPoint(x: 18, y: 80), size: 11, color: SettingsTheme.secondary)
        } else {
            let symbol: String
            let title: String
            let detail: String
            if voice { symbol = "waveform"; title = L("按住开启遥控器麦克风"); detail = L("松手结束收音，输入方式跟随「语音键」设置") }
            else if binding == nil { symbol = "plus"; title = L("未绑定动作"); detail = L("从上方「执行动作」菜单选择，或保持为空") }
            else {
                switch binding!.kind {
                case .toggleMouseMode: symbol = "cursorarrow"; title = binding!.title; detail = L("按一次进入鼠标控制，再按一次恢复普通键位")
                case .mouseUp, .mouseDown, .mouseLeft, .mouseRight: symbol = "cursorarrow.motionlines"; title = binding!.title; detail = L("按住连续移动指针并加速，松手即停")
                case .mouseLeftClick, .mouseRightClick: symbol = "computermouse"; title = binding!.title; detail = L("在当前鼠标位置点击一次")
                case .disabled: symbol = "pause.circle"; title = L("屏蔽此按键"); detail = L("按下不产生任何操作，适合防误触或只用双击/长按")
                case .nextDisplay: symbol = "display.2"; title = L("切换到下一块屏幕"); detail = L("激活另一块屏幕上的窗口，并将鼠标移过去")
                case .nextWindow: symbol = "macwindow.on.rectangle"; title = L("切换当前屏幕窗口"); detail = L("在当前屏幕已打开的窗口间依次切换，跳过最小化窗口")
                case .systemKey: symbol = "slider.horizontal.3"; title = binding!.title; detail = L("触发 macOS 系统音量、亮度或媒体播放键")
                case .scrollUp, .scrollDown, .scrollLeft, .scrollRight: symbol = "scroll"; title = binding!.title; detail = L("滚动鼠标指针所在位置的内容，按住可连续滚动")
                default: symbol = "arrow.turn.up.right"; title = L("保留原按键功能"); detail = L("不改绑，保持 macOS 对该按键的默认响应")
                }
            }
            let disc = NSBezierPath(roundedRect: NSRect(x: 18, y: 26, width: 52, height: 52), xRadius: 15, yRadius: 15)
            SettingsTheme.forest.setFill(); disc.fill()
            SettingsTheme.symbol(symbol, in: NSRect(x: 33, y: 41, width: 22, height: 22), onDark: true)
            text(title, at: NSPoint(x: 86, y: 31), size: 16.5, color: SettingsTheme.ink)
            text(detail, at: NSPoint(x: 86, y: 62), size: 11, color: SettingsTheme.secondary)
        }
    }
}

// Shared shell for the real application and side-effect-free visual previews.
final class SettingsView: SettingsPage {
    static let size = NSSize(width: 1080, height: 812)
    let readinessDot = StatusDotView()
    override var isFlipped: Bool { true }
    init(mapping: NSView, unlock: NSView, remote: NSPopUpButton, discovery: NSButton, pages: NSSegmentedControl,
         connection: NSTextField, audio: NSTextField, permission: NSTextField, permissionsButton: NSButton, message: NSTextField,
         readiness: NSTextField, wechatButton: NSButton) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: width, height: height); addSubview(view)
        }
        place(SettingsTheme.eyebrow("Remote Vibe"), 30, 23, 380, 16)
        place(SettingsTheme.label(L("遥控器设置"), size: 28, weight: .semibold, color: SettingsTheme.ink), 28, 46, 460, 40)
        place(readinessDot, 30, 96, 10, 10)
        readiness.font = .systemFont(ofSize: 12, weight: .medium)
        readiness.maximumNumberOfLines = 1
        readiness.lineBreakMode = .byTruncatingTail
        readiness.setAccessibilityLabel(L("使用就绪状态"))
        place(readiness, 46, 92, 620, 19)

        remote.font = .systemFont(ofSize: 12.5, weight: .medium)
        remote.setAccessibilityLabel(L("当前遥控器"))
        place(remote, 734, 24, 170, 34)
        place(discovery, 914, 24, 138, 34)

        pages.font = .systemFont(ofSize: 12.5, weight: .medium)
        place(pages, 816, 74, 236, 34)

        place(mapping, 28, 128, 1024, 574)
        place(unlock, 28, 128, 1024, 574)

        let footer = SettingsPanel(frame: NSRect(x: 28, y: 718, width: 1024, height: 70))
        footer.radius = 16; addSubview(footer)
        for field in [connection, audio, permission, message] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = SettingsTheme.secondary
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingTail
        }
        connection.textColor = SettingsTheme.ink
        connection.font = .systemFont(ofSize: 11.5, weight: .semibold)
        (wechatButton as? StyledButton)?.role = .secondary
        place(connection, 48, 732, 224, 18)
        place(audio, 282, 732, 210, 18)
        place(permission, 502, 732, 242, 18)
        place(message, 48, 756, 694, 18)
        place(permissionsButton, 756, 736, 130, 34)
        place(wechatButton, 896, 736, 136, 34)
        captureHorizontalLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { SettingsTheme.canvas.setFill(); bounds.fill() }
}
