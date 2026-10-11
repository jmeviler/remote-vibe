import AppKit
import UniformTypeIdentifiers

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
    var profile: RemoteProfile = .chromecast { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 43, y: 10, width: 196, height: 505), xRadius: profile == .chromecast ? 85 : 30, yRadius: profile == .chromecast ? 85 : 30).fill()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 61, y: profile == .chromecast ? 34 : 106, width: 160, height: 160)).fill()
    }
}

final class KeyMappingView: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    private let mapping: KeyMapping
    private var drafts: KeyMapping.Bindings
    private var selected: UInt8 = 8
    private var displayedProfile: RemoteProfile
    private var draftCache: [RemoteProfile: KeyMapping.Bindings] = [:]
    private let diagram = RemoteDiagram(frame: NSRect(x: 0, y: 0, width: 305, height: 540))
    private let nameLabel = NSTextField(labelWithString: "静音")
    private let currentLabel = NSTextField(wrappingLabelWithString: "")
    private let triggerPicker = NSSegmentedControl()
    private let actionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textEditor = NSTextView()
    private let textScroll = NSScrollView()
    private let targetLabel = NSTextField(labelWithString: "")
    private let targetField = NSTextField(string: "")
    private let chooseAppButton = NSButton(title: "选择应用…", target: nil, action: nil)
    private let modifierLabel = NSTextField(labelWithString: "组合键（可多选）")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "保存并生效", target: nil, action: nil)
    private let resetButton = NSButton(title: "恢复此键默认", target: nil, action: nil)
    private let permissionButton = NSButton(title: "允许按键控制", target: nil, action: nil)
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private var modifierButtons: [(NSButton, CGEventFlags)] = []
    private var remoteButtons: [UInt8: RemoteKeyButton] = [:]
    private let presets = ActionCatalog.presets

    init(mapping: KeyMapping) {
        self.mapping = mapping
        drafts = mapping.bindings
        displayedProfile = mapping.profile
        selected = mapping.profile == .chromecast ? 8 : 7
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 540))
        addSubview(diagram)
        rebuildDiagram()

        nameLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        place(nameLabel, y: 20, h: 36)
        currentLabel.textColor = .secondaryLabelColor
        place(currentLabel, y: 65, h: 45)
        triggerPicker.segmentCount = ButtonTrigger.allCases.count
        for (index, trigger) in ButtonTrigger.allCases.enumerated() {
            triggerPicker.setLabel(trigger.title, forSegment: index)
            triggerPicker.setWidth(130, forSegment: index)
        }
        triggerPicker.selectedSegment = 0
        triggerPicker.target = self; triggerPicker.action = #selector(triggerChanged)
        triggerPicker.setAccessibilityLabel("按键触发方式")
        place(triggerPicker, y: 118, h: 28)
        actionPicker.autoenablesItems = false
        var group = ""
        for (index, preset) in presets.enumerated() {
            if preset.group != group {
                if !group.isEmpty { actionPicker.menu?.addItem(.separator()) }
                actionPicker.menu?.addItem(.sectionHeader(title: preset.group))
                group = preset.group
            }
            let item = NSMenuItem(title: preset.title, action: nil, keyEquivalent: "")
            item.tag = index
            actionPicker.menu?.addItem(item)
        }
        actionPicker.setAccessibilityLabel("按键动作")
        actionPicker.toolTip = "\(presets.count) 个可选项，按类别排列；单击、双击和长按分别设置"
        actionPicker.target = self; actionPicker.action = #selector(actionChanged)
        place(actionPicker, y: 154, h: 32)
        place(modifierLabel, y: 207, h: 22)
        for (index, entry) in [("⌃ Control", CGEventFlags.maskControl), ("⇧ Shift", .maskShift), ("⌥ Option", .maskAlternate), ("⌘ Command", .maskCommand), ("Fn", .maskSecondaryFn)].enumerated() {
            let button = NSButton(checkboxWithTitle: entry.0, target: self, action: #selector(customChanged))
            button.frame = NSRect(x: 330 + CGFloat(index % 3) * 138, y: 236 + CGFloat(index / 3) * 30, width: 132, height: 24)
            addSubview(button); modifierButtons.append((button, entry.1))
        }
        keyPicker.addItems(withTitles: MappingKey.all.map { $0.name })
        keyPicker.autoenablesItems = false
        keyPicker.setAccessibilityLabel("自定义主键")
        keyPicker.target = self; keyPicker.action = #selector(customChanged)
        place(keyPicker, y: 306, h: 32)
        textEditor.isRichText = false
        textEditor.allowsUndo = true
        textEditor.font = .systemFont(ofSize: 14)
        textEditor.textContainerInset = NSSize(width: 8, height: 8)
        textEditor.isAutomaticQuoteSubstitutionEnabled = false
        textEditor.isAutomaticDashSubstitutionEnabled = false
        textEditor.isAutomaticTextReplacementEnabled = false
        textEditor.isVerticallyResizable = true
        textEditor.autoresizingMask = [.width]
        textEditor.textContainer?.widthTracksTextView = true
        textEditor.delegate = self
        textEditor.setAccessibilityLabel("此按键的常用文本")
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textScroll.documentView = textEditor
        place(textScroll, y: 207, h: 131)
        textEditor.frame = NSRect(origin: .zero, size: textScroll.contentSize)
        textEditor.minSize = NSSize(width: 0, height: textScroll.contentSize.height)
        textEditor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        place(targetLabel, y: 209, h: 24)
        targetField.delegate = self
        targetField.isSelectable = true
        targetField.setAccessibilityLabel("应用路径或网页地址")
        place(targetField, y: 244, h: 28)
        chooseAppButton.bezelStyle = .rounded
        chooseAppButton.target = self; chooseAppButton.action = #selector(chooseApp)
        place(chooseAppButton, y: 286, h: 30)
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 12)
        place(hint, y: 345, h: 73)
        saveButton.target = self; saveButton.action = #selector(saveMappings)
        saveButton.bezelStyle = .rounded; saveButton.bezelColor = .controlAccentColor
        saveButton.frame = NSRect(x: 330, y: 423, width: 155, height: 34); addSubview(saveButton)
        resetButton.target = self; resetButton.action = #selector(resetKey)
        resetButton.toolTip = "恢复此键的单击默认值，并清除双击和长按设置"
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 498, y: 423, width: 155, height: 34); addSubview(resetButton)
        liveStatus.font = .systemFont(ofSize: 12); liveStatus.textColor = .secondaryLabelColor
        place(liveStatus, y: 469, h: 32)
        permissionButton.target = self; permissionButton.action = #selector(allowListener)
        permissionButton.bezelStyle = .rounded
        place(permissionButton, y: 507, h: 28)
        displaySelection()
    }

    func switchProfile() {
        guard displayedProfile != mapping.profile else { return }
        draftCache[displayedProfile] = drafts
        displayedProfile = mapping.profile
        drafts = draftCache[displayedProfile] ?? mapping.bindings
        selected = displayedProfile == .chromecast ? 8 : 7
        triggerPicker.selectedSegment = 0
        rebuildDiagram()
        displaySelection()
    }

    private func rebuildDiagram() {
        diagram.subviews.forEach { $0.removeFromSuperview() }
        remoteButtons.removeAll()
        diagram.profile = mapping.profile
        let googlePositions: [(UInt8, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (3,"↑",120,37,42,43), (4,"↓",120,150,42,43),
            (5,"←",64,93,43,43), (6,"→",176,93,43,43), (7,"OK",114,88,54,54),
            (11,"↩",70,215,62,42), (0,"语音",151,215,62,42),
            (10,"主页",70,278,62,42), (8,"静音",151,278,62,42),
            (14,"YouTube",70,341,62,42), (15,"Netflix",151,341,62,42),
            (1,"电源",70,404,62,42), (17,"信源",151,404,62,42),
            (12,"＋",246,153,36,39), (13,"−",246,194,36,39)
        ]
        let xiaomiPositions: [(UInt8, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (1,"电源",70,43,62,42), (0,"语音",151,43,62,42),
            (3,"↑",120,109,42,43), (4,"↓",120,222,42,43),
            (5,"←",64,165,43,43), (6,"→",176,165,43,43), (7,"OK",114,160,54,54),
            (11,"↩",70,286,62,42), (12,"＋",151,286,62,42),
            (10,"主页",70,348,62,42), (13,"−",151,348,62,42),
            (18,"菜单",70,410,62,42), (19,"TV",151,410,62,42)
        ]
        let positions = mapping.profile == .chromecast ? googlePositions : xiaomiPositions
        for (code, title, x, y, w, h) in positions {
            let button = RemoteKeyButton(frame: NSRect(x: x, y: y, width: w, height: h))
            button.title = title; button.tag = Int(code); button.target = self; button.action = #selector(selectKey(_:))
            button.font = .systemFont(ofSize: title.count > 5 ? 11 : 14, weight: .medium)
            button.setAccessibilityLabel(code == 0 ? "语音键，按住说话" : mapping.buttons.first { $0.code == code }!.name)
            diagram.addSubview(button); remoteButtons[code] = button
        }
        if mapping.profile == .chromecast {
        let volume = NSTextField(labelWithString: "音量")
        volume.font = .systemFont(ofSize: 11); volume.textColor = .secondaryLabelColor
        volume.frame = NSRect(x: 250, y: 132, width: 40, height: 18); diagram.addSubview(volume)
        }
        let brand = NSTextField(labelWithString: mapping.profile == .chromecast ? "Chromecast" : "小米 RC003")
        brand.font = .systemFont(ofSize: 12, weight: .medium); brand.textColor = .secondaryLabelColor
        brand.alignment = .center; brand.frame = NSRect(x: 74, y: 478, width: 133, height: 20); diagram.addSubview(brand)
        let capacity = NSTextField(labelWithString: "\(mapping.buttons.count) 个普通键 · 最多 \(mapping.buttons.count * 3) 个动作位")
        capacity.font = .systemFont(ofSize: 11); capacity.textColor = .secondaryLabelColor
        capacity.alignment = .center
        capacity.frame = NSRect(x: 5, y: 519, width: 295, height: 18)
        diagram.addSubview(capacity)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func place(_ view: NSView, y: CGFloat, h: CGFloat) {
        view.frame = NSRect(x: 330, y: y, width: 415, height: h); addSubview(view)
    }

    private var selectedButton: MappedButton? { mapping.buttons.first { $0.code == selected } }
    private var selectedTrigger: ButtonTrigger { ButtonTrigger.allCases[triggerPicker.selectedSegment] }
    private var selectedPresetIndex: Int { actionPicker.selectedItem?.tag ?? 0 }
    private func presetItem(_ index: Int) -> NSMenuItem? {
        actionPicker.itemArray.first { !$0.isSeparatorItem && !$0.isSectionHeader && $0.tag == index }
    }
    private var selectedConfiguration: ButtonBinding {
        drafts[String(selected)] ?? .init(singleClick: selectedButton?.initial ?? .init(kind: .original))
    }
    private var selectedBinding: KeyBinding { selectedConfiguration[selectedTrigger] ?? .init(kind: .disabled) }
    private func setSelectedBinding(_ value: KeyBinding?) {
        var configuration = selectedConfiguration
        configuration[selectedTrigger] = value
        drafts[String(selected)] = configuration
    }

    @objc private func selectKey(_ sender: NSButton) { selected = UInt8(sender.tag); displaySelection() }
    @objc private func triggerChanged() { displaySelection() }

    private func displaySelection() {
        for (code, button) in remoteButtons {
            button.selected = code == selected
            if let physical = mapping.buttons.first(where: { $0.code == code }) {
                button.toolTip = "\(physical.name) → \((drafts[String(code)] ?? .init(singleClick: physical.initial)).summary)"
            } else { button.toolTip = "按住说话，松开结束" }
        }
        let voice = selected == 0
        nameLabel.stringValue = selectedButton?.name ?? "语音键"
        triggerPicker.isEnabled = !voice
        presetItem(0)?.title = selectedTrigger == .singleClick ? "原按键功能" : "未设置"
        presetItem(2)?.title = selectedTrigger == .longPress ? "Fn（长按后保持，松开释放）" : presets[2].title
        presetItem(2)?.isEnabled = selectedTrigger != .doubleClick
        keyPicker.item(at: 0)?.isEnabled = selectedTrigger != .doubleClick
        let value = selectedBinding
        let unset = selectedTrigger != .singleClick && selectedConfiguration[selectedTrigger] == nil
        actionPicker.select(presetItem(unset ? 0 : ActionCatalog.index(for: value)))
        textEditor.string = value.text ?? ""
        targetField.stringValue = value.kind == .openApp ? value.appPath ?? "" : value.url ?? ""
        actionPicker.isEnabled = !voice; resetButton.isEnabled = !voice
        keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == value.usage } ?? 0)
        for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: value.modifiers).contains(flag) ? .on : .off }
        displayOptions()
        refreshStatus()
    }

    private func displayOptions() {
        currentLabel.stringValue = selected == 0 ? "按住说话，松开后由微信转成文字。" :
            "\(selectedTrigger.title)：\(selectedConfiguration[selectedTrigger].map(ActionCatalog.displayName) ?? "未设置")\n已保存：\(mapping.binding(selectedButton!)[selectedTrigger].map(ActionCatalog.displayName) ?? "未设置")"
        if let selectedButton { remoteButtons[selected]?.toolTip = "\(selectedButton.name) → \(selectedConfiguration.summary)" }
        let custom = selected != 0 && selectedPresetIndex == presets.count - 1
        modifierLabel.isHidden = !custom; keyPicker.isHidden = !custom
        modifierButtons.forEach { $0.0.isHidden = !custom; $0.0.isEnabled = !selectedBinding.isFn }
        textScroll.isHidden = selected == 0 || selectedBinding.kind != .text
        let app = selected != 0 && selectedBinding.kind == .openApp
        let webpage = selected != 0 && selectedBinding.kind == .openURL
        targetLabel.isHidden = !app && !webpage
        targetField.isHidden = !app && !webpage
        targetLabel.stringValue = app ? "要打开的 Mac 应用" : "要打开的网页地址"
        targetField.isEditable = webpage
        targetField.placeholderString = app ? "点击下方按钮选择 .app" : "https://example.com"
        chooseAppButton.isHidden = !app
        if selected == 0 { hint.stringValue = "语音功能已固定保留，当前无需设置。" }
        else if selectedBinding.isFn {
            hint.stringValue = selectedTrigger == .longPress ?
                "按住约 0.55 秒后保持 Fn，松开即释放。\n不会开启遥控器麦克风，也不会切换系统输入设备。" :
                "按住此键保持 Fn，松开即释放；用途由系统或软件决定。\n不会开启遥控器麦克风，也不会切换系统输入设备。"
        }
        else if selectedBinding.kind == .text {
            hint.stringValue = "先将光标放入目标输入框，再按遥控器。\n按一次粘贴一次，不发送回车；文本保存在本机。"
        }
        else if app {
            hint.stringValue = "按一次打开并激活所选应用，已运行时切换到它。\n每个按键、每种触发方式可选择不同应用。"
        } else if webpage {
            hint.stringValue = "按一次交给默认浏览器打开，可能新建标签页。\n支持 http:// 和 https:// 地址。"
        } else if selectedBinding.kind == .systemKey {
            hint.stringValue = "发送一次系统音量、亮度或媒体按键。\n亮度取决于显示器支持，播放控制取决于当前媒体应用。"
        }
        else if selectedBinding.kind == .nextDisplay {
            hint.stringValue = "切到下一块屏幕的可见窗口，鼠标随之移入。\n不移动窗口，不切换桌面空间；按一次切换一次。"
        } else if selectedBinding.kind == .nextWindow {
            hint.stringValue = "在当前屏幕的可见普通窗口间循环。\n跳过最小化窗口；按一次切换一次。"
        } else if custom {
            hint.stringValue = "可多选修饰键，例如 Control + Shift + ↑。\n按一次发送一次；实际用途由当前软件决定。"
        } else if selectedBinding.modifiers != 0 {
            hint.stringValue = "发送 \(selectedBinding.title)；按一次执行一次。\n用途取决于当前软件和系统快捷键设置。"
        } else if selectedBinding.kind == .key && selectedBinding.usage == 0x29 {
            hint.stringValue = "发送一次 Esc；长按不连发。\n可用于当前软件支持的取消或停止操作。"
        } else {
            hint.stringValue = "切换按键后，未保存的修改也会保留。\n点击「保存并生效」后一起应用并记住。"
        }
        if selected != 0 {
            if let error = selectedConfiguration.validationMessage {
                hint.stringValue = error
            } else if selectedConfiguration.hasGestures || selectedTrigger != .singleClick {
                var timing = selectedConfiguration.doubleClick != nil ?
                    "双击间隔 0.3 秒；单击松开后等待。" : "短按松开即触发单击。"
                if selectedConfiguration.longPress != nil { timing += "长按 0.55 秒。" }
                hint.stringValue += "\n" + (selectedConfiguration.hasGestures ? timing + "不连发。" : "未设置时不识别此手势，单击保持原有响应。")
            }
        }
    }

    @objc private func actionChanged() {
        guard selectedButton != nil else { return }
        if selectedTrigger != .singleClick && selectedPresetIndex == 0 {
            setSelectedBinding(nil)
        } else if let value = presets[selectedPresetIndex].binding {
            var next = value
            if next.kind == .text { next.text = selectedBinding.text ?? "" }
            if next.kind == .openApp { next.appPath = selectedBinding.appPath }
            if next.kind == .openURL { next.url = selectedBinding.url }
            setSelectedBinding(next)
            textEditor.string = next.text ?? ""
            targetField.stringValue = next.kind == .openApp ? next.appPath ?? "" : next.url ?? ""
        } else {
            let current = selectedBinding
            if current.kind == .key {
                keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == current.usage } ?? 0)
                for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: current.modifiers).contains(flag) ? .on : .off }
            } else {
                keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == 0x28 } ?? 0)
                modifierButtons.forEach { $0.0.state = .off }
            }
            customChanged()
        }
        displayOptions(); refreshStatus()
    }

    @objc private func customChanged() {
        if MappingKey.all[keyPicker.indexOfSelectedItem].usage == MappingKey.fnUsage {
            modifierButtons.forEach { $0.0.state = .off }
        }
        let flags = modifierButtons.filter { $0.0.state == .on }.reduce(UInt64(0)) { $0 | $1.1.rawValue }
        setSelectedBinding(.init(kind: .key, usage: MappingKey.all[keyPicker.indexOfSelectedItem].usage, modifiers: flags))
        displayOptions(); refreshStatus()
    }

    func textDidChange(_ notification: Notification) {
        guard selected != 0, selectedBinding.kind == .text else { return }
        var value = selectedBinding
        value.text = textEditor.string
        setSelectedBinding(value)
        refreshStatus()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === targetField, selected != 0, selectedBinding.kind == .openURL else { return }
        var value = selectedBinding
        value.url = targetField.stringValue
        setSelectedBinding(value)
        displayOptions(); refreshStatus()
    }

    @objc private func chooseApp() {
        guard let window, selectedBinding.kind == .openApp else { return }
        let profile = displayedProfile, code = selected, trigger = selectedTrigger
        let panel = NSOpenPanel()
        panel.title = "选择要打开的应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let path = panel.url?.path,
                  self.displayedProfile == profile, self.selected == code, self.selectedTrigger == trigger,
                  self.selectedBinding.kind == .openApp else { return }
            guard KeyMapping.applicationURL(path) != nil else { self.liveStatus.stringValue = "请选择可运行的 Mac 应用"; return }
            var value = self.selectedBinding
            value.appPath = path
            self.setSelectedBinding(value)
            self.displaySelection()
        }
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

    @objc func allowListener() {
        let pane: String
        if !mapping.listeningAllowed {
            mapping.requestListeningAccess()
            pane = "Privacy_ListenEvent"
        } else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            pane = "Privacy_Accessibility"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func refreshStatus() {
        let dirty = drafts != mapping.bindings
        let invalid = mapping.buttons.compactMap { button -> String? in
            drafts[String(button.code)]?.validationMessage.map { "\(button.name)：\($0)" }
        }.first
        liveStatus.stringValue = invalid ?? (dirty ? "有未保存的修改" : mapping.status)
        permissionButton.isHidden = (mapping.listeningAllowed && AXIsProcessTrusted()) ||
            !mapping.buttons.contains { (drafts[String($0.code)] ?? .init(singleClick: $0.initial)).usesListener }
        permissionButton.title = !mapping.listeningAllowed ? "允许输入监控" : "允许辅助功能"
        saveButton.isEnabled = invalid == nil && (dirty || mapping.needsApply)
    }
}
