import AppKit

enum StudioTheme {
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static let canvas = color(0xF2F3EE)
    static let paper = color(0xFCFCF9)
    static let ink = color(0x202923)
    static let secondary = color(0x667169)
    static let line = color(0xDFE3DA)
    static let accent = color(0xD4EF87)
    static let forest = color(0x344936)
    static let stage = color(0x202B25)
    static let error = color(0xA3422C)

    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = secondary) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        return view
    }

    static func eyebrow(_ text: String, light: Bool = false) -> NSTextField {
        let view = label(text, size: 10, weight: .medium, color: light ? color(0xABBCA9) : secondary)
        view.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        return view
    }

    static func style(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 13)
        field.textColor = ink
        field.backgroundColor = paper
        field.focusRingType = .exterior
    }

    static func symbol(_ name: String, in rect: NSRect, color: NSColor, size: CGFloat = 16) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return }
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let factor = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        tinted.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

class StudioPanel: NSView {
    var fill: NSColor = StudioTheme.paper
    var border: NSColor? = StudioTheme.line
    var radius: CGFloat = 22
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
}

// Reflow columns horizontally while keeping readable type and control heights.
// Capture the authored geometry once so repeated resizing never accumulates drift.
class StudioPage: NSView {
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

final class StudioScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let size = NSSize(width: max(1, contentSize.width), height: max(StudioShell.size.height, contentSize.height))
        if documentView.frame.size != size { documentView.setFrameSize(size) }
    }
}

final class StudioButton: NSButton {
    var primary = false
    var destructive = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let base = primary ? StudioTheme.ink : StudioTheme.paper
        let fill = !isEnabled ? StudioTheme.color(0xE8EBE3) : isHighlighted ? StudioTheme.forest :
            hovered ? (primary ? StudioTheme.forest : StudioTheme.color(0xEBF0E3)) : base
        fill.setFill(); shape.fill()
        if !primary { StudioTheme.line.setStroke(); shape.stroke() }
        let textColor = !isEnabled ? StudioTheme.color(0x7D877D) : primary || isHighlighted ? StudioTheme.accent :
            destructive ? StudioTheme.error : StudioTheme.ink
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: textColor]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class RemoteStage: StudioPanel {
    override init(frame: NSRect) {
        super.init(frame: frame)
        fill = StudioTheme.stage; border = nil; radius = 24
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        StudioTheme.color(0x3C4D3F).withAlphaComponent(0.6).setStroke()
        for radius in stride(from: CGFloat(125), through: 245, by: 40) {
            let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 0.7; ring.stroke()
        }
        StudioTheme.color(0x435543).setFill()
        for x in stride(from: CGFloat(22), through: bounds.width - 20, by: 24) {
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.height - 54, width: 1.5, height: 1.5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ActionPreview: StudioPanel {
    var binding: KeyBinding? { didSet { needsDisplay = true } }
    var voice = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        fill = StudioTheme.canvas; border = nil; radius = 12
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
                let cap = NSBezierPath(roundedRect: NSRect(x: x, y: 16, width: width, height: 49), xRadius: 10, yRadius: 10)
                StudioTheme.paper.setFill(); cap.fill(); StudioTheme.line.setStroke(); cap.stroke()
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: key.count > 3 ? 17 : 25, weight: .medium), .foregroundColor: StudioTheme.ink]
                let size = (key as NSString).size(withAttributes: attrs)
                (key as NSString).draw(at: NSPoint(x: x + (width - size.width) / 2, y: 16 + (49 - size.height) / 2), withAttributes: attrs)
                x += width + 8
            }
            text(binding.isFn ? "按住保持 · 松开释放" : "发送到当前应用", at: NSPoint(x: 18, y: 85), size: 11, color: StudioTheme.secondary)
        } else {
            let symbol: String
            let title: String
            let detail: String
            if voice { symbol = "waveform"; title = "按住说话，松开结束。"; detail = "使用遥控器自带麦克风" }
            else if binding == nil { symbol = "plus"; title = "为这个手势，留一个位置。"; detail = "从上方菜单选择一个动作" }
            else {
                switch binding!.kind {
                case .disabled: symbol = "pause.circle"; title = "不执行动作"; detail = "识别这个手势，但不触发操作"
                case .nextDisplay: symbol = "display.2"; title = "切换到下一块屏幕"; detail = "聚焦可见窗口，鼠标随之移入"
                case .nextWindow: symbol = "macwindow.on.rectangle"; title = "在窗口之间，轻松流转。"; detail = "循环切换当前屏幕的可见窗口"
                case .systemKey: symbol = "slider.horizontal.3"; title = binding!.title; detail = "交给系统、显示器或媒体应用响应"
                case .scrollUp, .scrollDown, .scrollLeft, .scrollRight: symbol = "scroll"; title = binding!.title; detail = "作用于鼠标所在位置"
                default: symbol = "arrow.turn.up.right"; title = "保留原按键功能"; detail = "继续使用系统对这个按键的默认处理"
                }
            }
            let disc = NSBezierPath(roundedRect: NSRect(x: 18, y: 27, width: 53, height: 53), xRadius: 16, yRadius: 16)
            StudioTheme.accent.setFill(); disc.fill()
            StudioTheme.symbol(symbol, in: NSRect(x: 33, y: 42, width: 23, height: 23), color: StudioTheme.ink)
            text(title, at: NSPoint(x: 88, y: 32), size: 17, color: StudioTheme.ink)
            text(detail, at: NSPoint(x: 88, y: 66), size: 11, color: StudioTheme.secondary)
        }
    }
}

// Shared shell for the real application and side-effect-free visual previews.
final class StudioShell: StudioPage {
    static let size = NSSize(width: 1080, height: 812)
    override var isFlipped: Bool { true }
    init(mapping: NSView, unlock: NSView, remote: NSPopUpButton, discovery: NSButton, pages: NSSegmentedControl,
         connection: NSTextField, audio: NSTextField, permission: NSTextField, permissionsButton: NSButton, message: NSTextField) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .aqua)
        func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: width, height: height); addSubview(view)
        }
        place(StudioTheme.eyebrow("REMOTE VIBE  /  DESKTOP CONTROL"), 30, 22, 380, 16)
        place(StudioTheme.label("把习惯，放进按键。", size: 29, weight: .semibold, color: StudioTheme.ink), 28, 49, 460, 42)
        place(StudioTheme.label("一个按键，三种可能。", size: 12), 30, 96, 440, 19)
        remote.font = .systemFont(ofSize: 12, weight: .medium)
        remote.setAccessibilityLabel("当前遥控器")
        place(remote, 737, 24, 168, 32)
        place(discovery, 918, 23, 134, 34)
        pages.segmentStyle = .separated
        pages.selectedSegmentBezelColor = StudioTheme.forest
        pages.segmentDistribution = .fillEqually
        pages.font = .systemFont(ofSize: 12, weight: .medium)
        place(pages, 817, 77, 234, 30)
        place(mapping, 28, 131, 1024, 574)
        place(unlock, 28, 131, 1024, 574)
        let footer = StudioPanel(frame: NSRect(x: 28, y: 721, width: 1024, height: 73))
        footer.radius = 15; addSubview(footer)
        for field in [connection, audio, permission, message] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = StudioTheme.secondary
            field.maximumNumberOfLines = 2
        }
        connection.textColor = StudioTheme.ink
        connection.font = .systemFont(ofSize: 11, weight: .medium)
        place(connection, 46, 733, 306, 31)
        place(audio, 363, 733, 269, 31)
        place(permission, 655, 733, 253, 31)
        place(permissionsButton, 920, 731, 115, 30)
        place(message, 46, 766, 976, 19)
        captureHorizontalLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { StudioTheme.canvas.setFill(); bounds.fill() }
}
