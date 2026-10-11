import AppKit

enum SettingsTheme {
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

    static func button(_ title: String, target: AnyObject? = nil, action: Selector? = nil,
                       primary: Bool = false, destructive: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.bezelColor = primary ? forest : paper
        button.contentTintColor = destructive ? error : primary ? accent : ink
        return button
    }

    // Only the fixed app symbols use this cache, all with the same size and tint.
    private static var symbols: [String: NSImage] = [:]
    static func symbol(_ name: String, in rect: NSRect) {
        if symbols[name] == nil {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) else { return }
            let tinted = NSImage(size: image.size)
            tinted.lockFocus()
            image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            ink.setFill(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            symbols[name] = tinted
        }
        guard let image = symbols[name] else { return }
        let factor = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

class SettingsPanel: NSView {
    var fill: NSColor = SettingsTheme.paper
    var border: NSColor? = SettingsTheme.line
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
        fill = SettingsTheme.stage; border = nil; radius = 24
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        SettingsTheme.color(0x3C4D3F).withAlphaComponent(0.6).setStroke()
        for radius in stride(from: CGFloat(125), through: 245, by: 40) {
            let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 0.7; ring.stroke()
        }
        SettingsTheme.color(0x435543).setFill()
        for x in stride(from: CGFloat(22), through: bounds.width - 20, by: 24) {
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.height - 54, width: 1.5, height: 1.5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ActionPreview: SettingsPanel {
    var binding: ButtonAction? { didSet { needsDisplay = true } }
    var voice = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        fill = SettingsTheme.canvas; border = nil; radius = 12
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
                SettingsTheme.paper.setFill(); cap.fill(); SettingsTheme.line.setStroke(); cap.stroke()
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: key.count > 3 ? 17 : 25, weight: .medium), .foregroundColor: SettingsTheme.ink]
                let size = (key as NSString).size(withAttributes: attrs)
                (key as NSString).draw(at: NSPoint(x: x + (width - size.width) / 2, y: 16 + (49 - size.height) / 2), withAttributes: attrs)
                x += width + 8
            }
            text(binding.isFn ? L("仅模拟 Fn · 使用目标软件选择的麦克风") : L("发送到当前应用"), at: NSPoint(x: 18, y: 85), size: 11, color: SettingsTheme.secondary)
        } else {
            let symbol: String
            let title: String
            let detail: String
            if voice { symbol = "waveform"; title = L("按住说话，松开结束。"); detail = L("使用遥控器自带麦克风") }
            else if binding == nil { symbol = "plus"; title = L("为这个手势，留一个位置。"); detail = L("从上方菜单选择一个动作") }
            else {
                switch binding!.kind {
                case .disabled: symbol = "pause.circle"; title = L("不执行动作"); detail = L("识别这个手势，但不触发操作")
                case .nextDisplay: symbol = "display.2"; title = L("切换到下一块屏幕"); detail = L("聚焦可见窗口，鼠标随之移入")
                case .nextWindow: symbol = "macwindow.on.rectangle"; title = L("在窗口之间，轻松流转。"); detail = L("循环切换当前屏幕的可见窗口")
                case .systemKey: symbol = "slider.horizontal.3"; title = binding!.title; detail = L("交给系统、显示器或媒体应用响应")
                case .scrollUp, .scrollDown, .scrollLeft, .scrollRight: symbol = "scroll"; title = binding!.title; detail = L("作用于鼠标所在位置")
                default: symbol = "arrow.turn.up.right"; title = L("保留原按键功能"); detail = L("继续使用系统对这个按键的默认处理")
                }
            }
            let disc = NSBezierPath(roundedRect: NSRect(x: 18, y: 27, width: 53, height: 53), xRadius: 16, yRadius: 16)
            SettingsTheme.accent.setFill(); disc.fill()
            SettingsTheme.symbol(symbol, in: NSRect(x: 33, y: 42, width: 23, height: 23))
            text(title, at: NSPoint(x: 88, y: 32), size: 17, color: SettingsTheme.ink)
            text(detail, at: NSPoint(x: 88, y: 66), size: 11, color: SettingsTheme.secondary)
        }
    }
}

// Shared shell for the real application and side-effect-free visual previews.
final class SettingsView: SettingsPage {
    static let size = NSSize(width: 1080, height: 812)
    override var isFlipped: Bool { true }
    init(mapping: NSView, unlock: NSView, remote: NSPopUpButton, discovery: NSButton, pages: NSSegmentedControl,
         connection: NSTextField, audio: NSTextField, permission: NSTextField, permissionsButton: NSButton, message: NSTextField,
         readiness: NSTextField, wechatButton: NSButton) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .aqua)
        func place(_ view: NSView, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            view.frame = NSRect(x: x, y: y, width: width, height: height); addSubview(view)
        }
        place(SettingsTheme.eyebrow("REMOTE VIBE  /  DESKTOP CONTROL"), 30, 22, 380, 16)
        place(SettingsTheme.label(L("把习惯，放进按键。"), size: 29, weight: .semibold, color: SettingsTheme.ink), 28, 49, 460, 42)
        readiness.font = .systemFont(ofSize: 12, weight: .medium)
        readiness.maximumNumberOfLines = 1
        readiness.lineBreakMode = .byTruncatingTail
        readiness.setAccessibilityLabel(L("使用就绪状态"))
        place(readiness, 30, 96, 750, 19)
        remote.font = .systemFont(ofSize: 12, weight: .medium)
        remote.setAccessibilityLabel(L("当前遥控器"))
        place(remote, 737, 24, 168, 32)
        place(discovery, 918, 23, 134, 34)
        pages.segmentStyle = .separated
        pages.selectedSegmentBezelColor = SettingsTheme.forest
        pages.segmentDistribution = .fillEqually
        pages.font = .systemFont(ofSize: 12, weight: .medium)
        place(pages, 817, 77, 234, 30)
        place(mapping, 28, 131, 1024, 574)
        place(unlock, 28, 131, 1024, 574)
        let footer = SettingsPanel(frame: NSRect(x: 28, y: 721, width: 1024, height: 73))
        footer.radius = 15; addSubview(footer)
        for field in [connection, audio, permission, message] {
            field.font = .systemFont(ofSize: 11)
            field.textColor = SettingsTheme.secondary
            field.maximumNumberOfLines = 2
        }
        connection.textColor = SettingsTheme.ink
        connection.font = .systemFont(ofSize: 11, weight: .medium)
        place(connection, 46, 733, 306, 31)
        place(audio, 363, 733, 269, 31)
        place(permission, 655, 733, 253, 31)
        place(permissionsButton, 920, 731, 115, 30)
        place(message, 46, 766, 806, 19)
        place(wechatButton, 876, 761, 159, 29)
        captureHorizontalLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) { SettingsTheme.canvas.setFill(); bounds.fill() }
}
