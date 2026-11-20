import AppKit

final class ShortcutRecorderControl: NSButton {
    // macOS automatically sets .function on navigation and F-keys; exclude those when detecting explicit Fn.
    private static let implicitFunctionKeyCodes: Set<CGKeyCode> = [
        123, 124, 125, 126, 115, 116, 117, 119, 121,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90
    ]

    var allowFnOnly = true
    var usage: UInt64 = 0x28 { didSet { needsDisplay = true; syncAccessibility() } }
    var modifiers: UInt64 = 0 { didSet { needsDisplay = true; syncAccessibility() } }
    var onShortcutRecorded: ((UInt64, UInt64) -> Void)?

    private(set) var isRecording = false { didSet { needsDisplay = true; syncAccessibility() } }
    private var monitor: Any?
    private var fnPressedAlone = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(toggleRecording)
        setAccessibilityRole(.button)
        syncAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { stopRecording() }
        return accepted
    }

    @objc private func toggleRecording() {
        guard isEnabled else { return }
        if isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        guard isEnabled, !isRecording else { return }
        isRecording = true
        fnPressedAlone = false
        _ = window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handleRecordingEvent(event) ? nil : event
        }
    }

    func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        fnPressedAlone = false
        if isRecording { isRecording = false }
    }

    static func normalizedModifiers(for keyCode: CGKeyCode, flags: NSEvent.ModifierFlags) -> UInt64 {
        var result = CGEventFlags()
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.function) && !implicitFunctionKeyCodes.contains(keyCode) {
            result.insert(.maskSecondaryFn)
        }
        return result.rawValue
    }

    @discardableResult
    func applyRecordedShortcut(keyCode: CGKeyCode, modifiers flags: NSEvent.ModifierFlags) -> Bool {
        let cleanMods = flags.intersection([.control, .option, .shift, .command, .function])
        if keyCode == 53 && cleanMods.isEmpty {
            stopRecording()
            return true
        }
        if keyCode == 63 && allowFnOnly {
            usage = MappingKey.fnUsage
            modifiers = 0
            stopRecording()
            onShortcutRecorded?(usage, modifiers)
            return true
        }
        guard let matched = MappingKey.all.first(where: { $0.usage != MappingKey.fnUsage && $0.code == keyCode }) else {
            return false
        }
        usage = matched.usage
        modifiers = Self.normalizedModifiers(for: keyCode, flags: cleanMods)
        stopRecording()
        onShortcutRecorded?(usage, modifiers)
        return true
    }

    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            if event.keyCode == 63 {
                if event.modifierFlags.contains(.function) {
                    let otherMods = event.modifierFlags.intersection([.control, .option, .shift, .command])
                    fnPressedAlone = otherMods.isEmpty
                } else if fnPressedAlone && allowFnOnly {
                    return applyRecordedShortcut(keyCode: 63, modifiers: [])
                }
            } else {
                fnPressedAlone = false
            }
            return false
        }
        fnPressedAlone = false
        return applyRecordedShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    var shortcutDisplayString: String {
        if usage == MappingKey.fnUsage { return "Fn" }
        let flags = CGEventFlags(rawValue: modifiers)
        let prefix = [
            (CGEventFlags.maskControl, "⌃"),
            (.maskAlternate, "⌥"),
            (.maskShift, "⇧"),
            (.maskCommand, "⌘"),
            (.maskSecondaryFn, "Fn + ")
        ].filter { flags.contains($0.0) }.map(\.1).joined()
        let keyName = MappingKey.all.first { $0.usage == usage }?.name ?? "Enter"
        return prefix + keyName
    }

    private func syncAccessibility() {
        setAccessibilityLabel(L("键盘快捷键录制"))
        setAccessibilityValue(isRecording ? L("正在监听键盘按键，按 Esc 取消") : shortcutDisplayString)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (isRecording ? SettingsTheme.paper : SettingsTheme.subtleFill).setFill()
        shape.fill()
        (isRecording ? SettingsTheme.forest : SettingsTheme.line).setStroke()
        shape.lineWidth = isRecording ? 1.6 : 1
        shape.stroke()

        SettingsTheme.symbol("keyboard", in: NSRect(x: 13, y: (bounds.height - 16) / 2, width: 18, height: 16))

        let mainText = isRecording ? L("请直接按下键盘快捷键…") : shortcutDisplayString
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: isRecording ? SettingsTheme.forest : SettingsTheme.ink
        ]
        let mainSize = (mainText as NSString).size(withAttributes: mainAttrs)
        (mainText as NSString).draw(at: NSPoint(x: 39, y: (bounds.height - mainSize.height) / 2), withAttributes: mainAttrs)

        let rightHint = isRecording ? L("Esc 取消") : L("点击按键录制")
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: SettingsTheme.secondary
        ]
        let hintSize = (rightHint as NSString).size(withAttributes: hintAttrs)
        if bounds.width - hintSize.width - 14 > 44 + mainSize.width {
            (rightHint as NSString).draw(
                at: NSPoint(x: bounds.width - hintSize.width - 14, y: (bounds.height - hintSize.height) / 2),
                withAttributes: hintAttrs
            )
        }

        if window?.firstResponder === self && !isRecording {
            SettingsTheme.forest.withAlphaComponent(0.75).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

final class VoiceLevelMeterView: NSView {
    var level: Float = 0 {
        didSet {
            let clamped = max(0, min(1, level))
            if level != clamped { level = clamped }
            if abs(level - oldValue) > 0.005 || (level == 0 && oldValue != 0) {
                needsDisplay = true
            }
        }
    }
    var active = false { didSet { if oldValue != active { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let count = 40
        let gap: CGFloat = 5
        let totalGap = CGFloat(count - 1) * gap
        let barWidth = max(3, (bounds.width - totalGap) / CGFloat(count))
        let litCount = active ? max(1, Int((level * Float(count)).rounded(.up))) : 0
        for index in 0..<count {
            let x = CGFloat(index) * (barWidth + gap)
            let barRect = NSRect(x: x, y: 3, width: barWidth, height: bounds.height - 6)
            let pill = NSBezierPath(roundedRect: barRect, xRadius: min(3.5, barWidth / 2), yRadius: min(3.5, barWidth / 2))
            if index < litCount {
                let ratio = CGFloat(index) / CGFloat(max(1, count - 1))
                let fill = ratio > 0.82 ? SettingsTheme.warning : SettingsTheme.accentDot
                fill.setFill()
            } else {
                SettingsTheme.adaptive(light: 0xD7DDD1, dark: 0x2F3B33).setFill()
            }
            pill.fill()
        }
    }
}
