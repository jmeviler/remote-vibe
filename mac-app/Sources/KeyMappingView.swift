import AppKit

private final class RemoteKeyButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: min(19, rect.height / 2), yRadius: min(19, rect.height / 2))
        (selected || isHighlighted ? NSColor.controlAccentColor : NSColor.white).setFill()
        shape.fill()
        NSColor.black.withAlphaComponent(0.1).setStroke(); shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: selected || isHighlighted ? NSColor.white : NSColor.black.withAlphaComponent(0.8)
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

private final class RemoteDiagram: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 43, y: 10, width: 196, height: 505), xRadius: 85, yRadius: 85).fill()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 61, y: 34, width: 160, height: 160)).fill()
    }
}

final class KeyMappingView: NSView {
    override var isFlipped: Bool { true }
    private let mapping: KeyMapping
    private var drafts: KeyMapping.Bindings
    private var selected: UInt8 = 8
    private let nameLabel = NSTextField(labelWithString: "静音")
    private let currentLabel = NSTextField(wrappingLabelWithString: "")
    private let actionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modifierLabel = NSTextField(labelWithString: "组合键（可多选）")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "保存并生效", target: nil, action: nil)
    private let resetButton = NSButton(title: "恢复此键默认", target: nil, action: nil)
    private let permissionButton = NSButton(title: "允许组合快捷键", target: nil, action: nil)
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private var modifierButtons: [(NSButton, CGEventFlags)] = []
    private var remoteButtons: [UInt8: RemoteKeyButton] = [:]
    private let presets: [(String, KeyBinding?)] = [
        ("原按键功能", .init(kind: .original)), ("不执行", .init(kind: .disabled)),
        ("Enter 回车 / 确认", .init(kind: .key, usage: 0x28)),
        ("Backspace 退格删除", .init(kind: .key, usage: 0x2A)),
        ("Escape 取消", .init(kind: .key, usage: 0x29)),
        ("↑ 方向上", .init(kind: .key, usage: 0x52)), ("↓ 方向下", .init(kind: .key, usage: 0x51)),
        ("← 方向左", .init(kind: .key, usage: 0x50)), ("→ 方向右", .init(kind: .key, usage: 0x4F)),
        ("Tab 下一项", .init(kind: .key, usage: 0x2B)),
        ("Shift + Tab 上一项", .init(kind: .key, usage: 0x2B, modifiers: CGEventFlags.maskShift.rawValue)),
        ("Space 空格", .init(kind: .key, usage: 0x2C)),
        ("向上滚动", .init(kind: .scrollUp)), ("向下滚动", .init(kind: .scrollDown)),
        ("自定义按键 / 组合快捷键…", nil)
    ]

    init(mapping: KeyMapping) {
        self.mapping = mapping
        drafts = mapping.bindings
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 540))
        let diagram = RemoteDiagram(frame: NSRect(x: 0, y: 0, width: 305, height: 540))
        addSubview(diagram)
        // The physical layout includes the volume rocker on the right edge.
        let positions: [(UInt8, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (3,"↑",120,37,42,43), (4,"↓",120,150,42,43),
            (5,"←",64,93,43,43), (6,"→",176,93,43,43), (7,"OK",114,88,54,54),
            (11,"↩",70,215,62,42), (0,"语音",151,215,62,42),
            (10,"主页",70,278,62,42), (8,"静音",151,278,62,42),
            (14,"YouTube",70,341,62,42), (15,"Netflix",151,341,62,42),
            (1,"电源",70,404,62,42), (17,"信源",151,404,62,42),
            (12,"＋",246,153,36,39), (13,"−",246,194,36,39)
        ]
        for (code, title, x, y, w, h) in positions {
            let button = RemoteKeyButton(frame: NSRect(x: x, y: y, width: w, height: h))
            button.title = title; button.tag = Int(code); button.target = self; button.action = #selector(selectKey(_:))
            button.font = .systemFont(ofSize: title.count > 5 ? 11 : 14, weight: .medium)
            button.setAccessibilityLabel(code == 0 ? "语音键，按住说话" : MappedButton.all.first { $0.code == code }!.name)
            diagram.addSubview(button); remoteButtons[code] = button
        }
        let volume = NSTextField(labelWithString: "音量")
        volume.font = .systemFont(ofSize: 11); volume.textColor = .secondaryLabelColor
        volume.frame = NSRect(x: 250, y: 132, width: 40, height: 18); diagram.addSubview(volume)
        let brand = NSTextField(labelWithString: "Chromecast")
        brand.font = .systemFont(ofSize: 12, weight: .medium); brand.textColor = .secondaryLabelColor
        brand.alignment = .center; brand.frame = NSRect(x: 74, y: 470, width: 133, height: 20); diagram.addSubview(brand)

        nameLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        place(nameLabel, y: 20, h: 36)
        currentLabel.textColor = .secondaryLabelColor
        place(currentLabel, y: 65, h: 45)
        let choose = NSTextField(labelWithString: "这个按键要做什么")
        choose.font = .systemFont(ofSize: 13, weight: .medium)
        place(choose, y: 125, h: 22)
        actionPicker.addItems(withTitles: presets.map { $0.0 })
        actionPicker.target = self; actionPicker.action = #selector(actionChanged)
        place(actionPicker, y: 154, h: 32)
        place(modifierLabel, y: 207, h: 22)
        for (index, entry) in [("Control", CGEventFlags.maskControl), ("Shift", .maskShift), ("Option", .maskAlternate), ("Command", .maskCommand)].enumerated() {
            let button = NSButton(checkboxWithTitle: entry.0, target: self, action: #selector(customChanged))
            button.frame = NSRect(x: 330 + CGFloat(index % 2) * 180, y: 236 + CGFloat(index / 2) * 30, width: 165, height: 24)
            addSubview(button); modifierButtons.append((button, entry.1))
        }
        keyPicker.addItems(withTitles: MappingKey.all.map { $0.name })
        keyPicker.target = self; keyPicker.action = #selector(customChanged)
        place(keyPicker, y: 306, h: 32)
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 12)
        place(hint, y: 354, h: 55)
        saveButton.target = self; saveButton.action = #selector(saveMappings)
        saveButton.bezelStyle = .rounded; saveButton.bezelColor = .controlAccentColor
        saveButton.frame = NSRect(x: 330, y: 423, width: 155, height: 34); addSubview(saveButton)
        resetButton.target = self; resetButton.action = #selector(resetKey)
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 498, y: 423, width: 155, height: 34); addSubview(resetButton)
        liveStatus.font = .systemFont(ofSize: 12); liveStatus.textColor = .secondaryLabelColor
        place(liveStatus, y: 469, h: 32)
        permissionButton.target = self; permissionButton.action = #selector(allowListener)
        permissionButton.bezelStyle = .rounded
        place(permissionButton, y: 507, h: 28)
        displaySelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func place(_ view: NSView, y: CGFloat, h: CGFloat) {
        view.frame = NSRect(x: 330, y: y, width: 415, height: h); addSubview(view)
    }

    private var selectedButton: MappedButton? { MappedButton.all.first { $0.code == selected } }
    private var selectedBinding: KeyBinding { drafts[String(selected)] ?? selectedButton?.initial ?? .init(kind: .original) }

    @objc private func selectKey(_ sender: NSButton) { selected = UInt8(sender.tag); displaySelection() }

    private func displaySelection() {
        for (code, button) in remoteButtons {
            button.selected = code == selected
            if let physical = MappedButton.all.first(where: { $0.code == code }) {
                button.toolTip = "\(physical.name) → \((drafts[String(code)] ?? physical.initial).title)"
            } else { button.toolTip = "按住说话，松开结束" }
        }
        let voice = selected == 0
        nameLabel.stringValue = selectedButton?.name ?? "语音键"
        currentLabel.stringValue = voice ? "按住说话，松开后由微信转成文字。" : "已保存：\(mapping.binding(selectedButton!).title)"
        let value = selectedBinding
        actionPicker.selectItem(at: presets.firstIndex(where: { $0.1 == value }) ?? presets.count - 1)
        actionPicker.isEnabled = !voice; resetButton.isEnabled = !voice
        keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == value.usage } ?? 0)
        for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: value.modifiers).contains(flag) ? .on : .off }
        displayOptions()
        refreshStatus()
    }

    private func displayOptions() {
        let custom = selected != 0 && actionPicker.indexOfSelectedItem == presets.count - 1
        modifierLabel.isHidden = !custom; keyPicker.isHidden = !custom
        modifierButtons.forEach { $0.0.isHidden = !custom }
        hint.stringValue = selected == 0 ? "语音功能已固定保留，当前无需设置。" : custom ?
            "例如：勾选 Control、Shift，再选择 ↑。\n快捷键会发送给你正在使用的软件。" :
            "配置会自动记住。切换按键后，未保存的修改也会保留；点保存后一起生效。"
    }

    @objc private func actionChanged() {
        guard selectedButton != nil else { return }
        if let value = presets[actionPicker.indexOfSelectedItem].1 {
            drafts[String(selected)] = value
        } else {
            let current = selectedBinding
            if current.kind == .key {
                keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == current.usage } ?? 0)
                for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: current.modifiers).contains(flag) ? .on : .off }
            } else {
                keyPicker.selectItem(at: 0)
                modifierButtons.forEach { $0.0.state = .off }
            }
            customChanged()
        }
        displayOptions(); refreshStatus()
    }

    @objc private func customChanged() {
        let flags = modifierButtons.filter { $0.0.state == .on }.reduce(UInt64(0)) { $0 | $1.1.rawValue }
        drafts[String(selected)] = .init(kind: .key, usage: MappingKey.all[keyPicker.indexOfSelectedItem].usage, modifiers: flags)
        displayOptions(); refreshStatus()
    }

    @objc private func saveMappings() {
        mapping.save(drafts)
        displaySelection()
    }

    @objc private func resetKey() {
        guard selectedButton != nil else { return }
        drafts.removeValue(forKey: String(selected))
        displaySelection()
    }

    @objc private func allowListener() {
        mapping.requestListeningAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func refreshStatus() {
        let dirty = drafts != mapping.bindings
        liveStatus.stringValue = dirty ? "有未保存的修改" : mapping.status
        permissionButton.isHidden = mapping.listeningAllowed || !MappedButton.all.contains { (drafts[String($0.code)] ?? $0.initial).usesListener }
        saveButton.isEnabled = dirty || mapping.needsApply
    }
}
