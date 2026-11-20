import AppKit
import UniformTypeIdentifiers

private final class RemoteKeyButton: NSButton {
    var selected = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(selected ? L("已选择") : L("未选择"))
        }
    }
    var dirty = false { didSet { if oldValue != dirty { needsDisplay = true } } }
    var pulse = false { didSet { if oldValue != pulse { needsDisplay = true } } }

    private var hovered = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
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
        let radius = min(20, rect.height / 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.shadowBlurRadius = 2; shadow.set()
        let emphasized = selected || isHighlighted
        let fill = emphasized ? SettingsTheme.color(0x344936) : hovered ? SettingsTheme.color(0xE6EBE0) : SettingsTheme.color(0xFAFBF6)
        fill.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        let strokeColor: NSColor = dirty ? SettingsTheme.color(0xD9822B) :
            (selected ? SettingsTheme.color(0x344936) : SettingsTheme.color(0xC9D0C3))
        strokeColor.setStroke()
        shape.lineWidth = (selected || dirty) ? 1.5 : 0.75
        shape.stroke()

        let symbols = ["↑":"chevron.up", "↓":"chevron.down", "←":"chevron.left", "→":"chevron.right",
                       "↩":"arrow.uturn.backward", L("语音"):"mic.fill", L("主页"):"house", L("静音"):"speaker.slash",
                       L("电源"):"power", L("信源"):"rectangle.on.rectangle", L("菜单"):"line.3.horizontal", "＋":"plus", "−":"minus"]
        if let symbol = symbols[title] {
            let iconRect = NSRect(x: rect.midX - 9, y: rect.midY - 9, width: 18, height: 18)
            if emphasized {
                SettingsTheme.symbol(symbol, in: iconRect, onDark: true)
            } else if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
                let factor = min(iconRect.width / img.size.width, iconRect.height / img.size.height)
                let sz = NSSize(width: img.size.width * factor, height: img.size.height * factor)
                let tinted = NSImage(size: img.size, flipped: false) { b in
                    img.draw(in: b)
                    SettingsTheme.color(0x202923).setFill()
                    b.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: iconRect.midX - sz.width / 2, y: iconRect.midY - sz.height / 2, width: sz.width, height: sz.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: emphasized ? NSColor.white : SettingsTheme.color(0x202923)
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }

        if pulse {
            SettingsTheme.color(0x69D178).setStroke()
            let pulseRing = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: radius + 2, yRadius: radius + 2)
            pulseRing.lineWidth = 2.2
            pulseRing.stroke()
        } else if window?.firstResponder === self {
            SettingsTheme.color(0x527A58).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius + 2, yRadius: radius + 2)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

private final class RemoteDiagram: NSView {
    var profile: RemoteProfile = .chromecast { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let body = NSBezierPath(roundedRect: NSRect(x: 43, y: 10, width: 196, height: 505), xRadius: profile == .chromecast ? 85 : 30, yRadius: profile == .chromecast ? 85 : 30)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 8, height: -10); shadow.shadowBlurRadius = 20; shadow.set()
        SettingsTheme.color(0xE4E8DC).setFill(); body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: SettingsTheme.color(0xFBFCF6), ending: SettingsTheme.color(0xD9DECE))?.draw(in: body, angle: 0)
        NSColor.white.withAlphaComponent(0.7).setStroke(); body.lineWidth = 1.5; body.stroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 61, y: profile == .chromecast ? 34 : 106, width: 160, height: 160))
        NSGradient(starting: SettingsTheme.color(0xD5DBCE), ending: SettingsTheme.color(0xE6EADC))?.draw(in: ring, angle: 90)
        SettingsTheme.color(0xC6CFBC).setStroke(); ring.lineWidth = 0.8; ring.stroke()
    }
}

final class KeyMappingView: SettingsPage, NSTextViewDelegate, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    private let mapping: KeyMapping
    private let voiceSettings: VoiceInputSettings
    var onVoiceSettingsChange: (() -> Void)?

    private var normalDrafts: KeyMapping.Bindings
    private var mouseDrafts: KeyMapping.Bindings
    private var editingMouse: Bool { modePicker.selectedSegment == 1 }
    private var drafts: KeyMapping.Bindings {
        get { editingMouse ? mouseDrafts : normalDrafts }
        set { if editingMouse { mouseDrafts = newValue } else { normalDrafts = newValue } }
    }
    private var selected: UInt8 = 8
    private var displayedProfile: RemoteProfile
    private var draftCache: [RemoteProfile: (normal: KeyMapping.Bindings, mouse: KeyMapping.Bindings)] = [:]
    private var preferredPresetIndices: [String: Int] = [:]
    private var pulseResetWorkItem: DispatchWorkItem?

    private let modePicker = StyledSegmentedControl()
    private let diagram = RemoteDiagram(frame: NSRect(x: 0, y: 0, width: 305, height: 540))
    private let studioEyebrow = SettingsTheme.eyebrow(L("按键设置"))
    private let nameLabel = NSTextField(labelWithString: L("静音"))
    private let currentLabel = NSTextField(wrappingLabelWithString: "")
    private let triggerEyebrow = SettingsTheme.eyebrow(L("触发手势"))
    private let triggerPicker = StyledSegmentedControl()
    private let actionLabel = SettingsTheme.eyebrow(L("执行动作"))
    private let actionPicker = StyledPopUpButton(frame: .zero, pullsDown: false)
    private let searchPill = SettingsPanel()
    private let actionSearchField = NSSearchField(frame: .zero)
    private let shortcutRecorder = ShortcutRecorderControl()
    private let keyPicker = StyledPopUpButton(frame: .zero, pullsDown: false)
    private let textEditor = NSTextView()
    private let textScroll = NSScrollView()
    private let targetLabel = NSTextField(labelWithString: "")
    private let targetField = NSTextField(string: "")
    private let chooseAppButton = SettingsTheme.secondaryButton(L("选择应用…"))
    private let hintPanel = SettingsPanel()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let saveButton = SettingsTheme.button(L("保存并生效"))
    private let resetButton = SettingsTheme.secondaryButton(L("恢复此键默认"))
    private let discardButton = SettingsTheme.secondaryButton(L("撤销修改"))
    private let permissionButton = SettingsTheme.button(L("允许按键控制"))
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private var modifierButtons: [(NSButton, CGEventFlags)] = []
    private var remoteButtons: [UInt8: RemoteKeyButton] = [:]
    private let presets = ActionCatalog.presets
    private let deviceName = SettingsTheme.label("", size: 17, weight: .medium, color: .white)
    private let capacity = SettingsTheme.eyebrow("", light: true)
    private let actionPreview = ActionPreview()
    private let voiceStudio: VoiceStudioView

    var isVoiceSelected: Bool { selected == 0 }
    var hasUnsavedChanges: Bool { normalDrafts != mapping.bindings || mouseDrafts != mapping.mouseBindings }
    var isRecordingShortcut: Bool { shortcutRecorder.isRecording }

    init(mapping: KeyMapping, voiceSettings: VoiceInputSettings? = nil) {
        self.mapping = mapping
        let resolvedVoiceSettings = voiceSettings ?? VoiceInputSettings(
            preferences: UserDefaults(suiteName: "local.ben.RemoteVibe.ephemeral.\(UUID().uuidString)") ?? .standard
        )
        self.voiceSettings = resolvedVoiceSettings
        self.voiceStudio = VoiceStudioView(settings: resolvedVoiceSettings)
        normalDrafts = mapping.bindings
        mouseDrafts = mapping.mouseBindings
        displayedProfile = mapping.profile
        selected = mapping.profile == .chromecast ? 8 : 7
        super.init(frame: NSRect(x: 0, y: 0, width: 1024, height: 574))

        let stage = RemoteStage(frame: NSRect(x: 0, y: 0, width: 396, height: 574))
        addSubview(stage)
        let inspector = SettingsPanel(frame: NSRect(x: 414, y: 0, width: 610, height: 574))
        addSubview(inspector)
        let deviceEyebrow = SettingsTheme.eyebrow(L("遥控器面板"), light: true)
        deviceEyebrow.frame = NSRect(x: 24, y: 22, width: 220, height: 16); stage.addSubview(deviceEyebrow)
        deviceName.frame = NSRect(x: 24, y: 44, width: 300, height: 25); stage.addSubview(deviceName)
        modePicker.surfaceStyle = .darkStage
        modePicker.segmentCount = 2
        modePicker.setLabel(L("普通键位"), forSegment: 0)
        modePicker.setLabel(L("鼠标键位"), forSegment: 1)
        modePicker.selectedSegment = 0
        modePicker.font = .systemFont(ofSize: 12, weight: .medium)
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        modePicker.setAccessibilityLabel(L("要编辑的模式"))
        modePicker.toolTip = L("这里只选择要编辑的键位；用遥控器的切换键进入或退出鼠标模式。")
        modePicker.frame = NSRect(x: 24, y: 78, width: 348, height: 34)
        stage.addSubview(modePicker)

        diagram.frame = NSRect(x: 74, y: 120, width: 248, height: 404)
        diagram.bounds = NSRect(x: 0, y: 0, width: 305, height: 530)
        stage.addSubview(diagram)
        capacity.frame = NSRect(x: 24, y: 538, width: 348, height: 16); stage.addSubview(capacity)
        rebuildDiagram()

        place(studioEyebrow, y: 22, h: 15)
        nameLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        nameLabel.textColor = SettingsTheme.ink
        place(nameLabel, y: 43, h: 36)
        currentLabel.font = .systemFont(ofSize: 12)
        currentLabel.textColor = SettingsTheme.secondary
        place(currentLabel, y: 85, h: 20)

        place(triggerEyebrow, y: 122, h: 15)
        triggerPicker.segmentCount = ButtonTrigger.allCases.count
        triggerPicker.font = .systemFont(ofSize: 12.5, weight: .medium)
        for (index, trigger) in ButtonTrigger.allCases.enumerated() {
            triggerPicker.setLabel(trigger.title, forSegment: index)
        }
        triggerPicker.selectedSegment = 0
        triggerPicker.target = self; triggerPicker.action = #selector(triggerChanged)
        triggerPicker.setAccessibilityLabel(L("按键触发方式"))
        place(triggerPicker, y: 144, h: 36)

        actionLabel.frame = NSRect(x: 440, y: 198, width: 320, height: 16)
        addSubview(actionLabel)

        searchPill.fill = SettingsTheme.subtleFill
        searchPill.border = SettingsTheme.line
        searchPill.radius = 8
        searchPill.frame = NSRect(x: 806, y: 192, width: 192, height: 26)
        addSubview(searchPill)

        actionSearchField.placeholderString = L("搜索动作…")
        actionSearchField.font = .systemFont(ofSize: 11.5)
        actionSearchField.isBordered = false
        actionSearchField.drawsBackground = false
        actionSearchField.focusRingType = .none
        actionSearchField.sendsSearchStringImmediately = true
        actionSearchField.target = self
        actionSearchField.action = #selector(searchFilterChanged)
        actionSearchField.setAccessibilityLabel(L("搜索按键动作"))
        actionSearchField.frame = NSRect(x: 814, y: 195, width: 178, height: 20)
        addSubview(actionSearchField)

        actionPicker.autoenablesItems = false
        var group = ""
        // Keep the existing preset indices while placing the mode entry where it is easy to find.
        let toggleIndex = presets.firstIndex { $0.binding?.kind == .toggleMouseMode }!
        let orderedPresets = [toggleIndex] + presets.indices.filter { $0 != toggleIndex }
        for index in orderedPresets {
            let preset = presets[index]
            if preset.group != group {
                if !group.isEmpty { actionPicker.menu?.addItem(.separator()) }
                actionPicker.menu?.addItem(.sectionHeader(title: preset.group))
                group = preset.group
            }
            let item = NSMenuItem(title: preset.title, action: nil, keyEquivalent: "")
            item.tag = index; actionPicker.menu?.addItem(item)
        }
        actionPicker.setAccessibilityLabel(L("按键动作"))
        actionPicker.toolTip = L("%@ 个可选项，单击、双击和长按分别设置", String(presets.count))
        actionPicker.font = .systemFont(ofSize: 13.5, weight: .medium)
        actionPicker.target = self; actionPicker.action = #selector(actionChanged)
        place(actionPicker, y: 226, h: 38)

        shortcutRecorder.frame = NSRect(x: 440, y: 278, width: 558, height: 36)
        shortcutRecorder.onShortcutRecorded = { [weak self] usage, modifiers in
            guard let self else { return }
            if let keyIdx = MappingKey.all.firstIndex(where: { $0.usage == usage }) {
                self.keyPicker.selectItem(at: keyIdx)
            }
            let flags = CGEventFlags(rawValue: modifiers)
            for (button, flag) in self.modifierButtons {
                button.state = (usage == MappingKey.fnUsage) ? .off : (flags.contains(flag) ? .on : .off)
            }
            self.setSelectedBinding(.init(kind: .key, usage: usage, modifiers: usage == MappingKey.fnUsage ? 0 : modifiers))
            self.updateRemoteButtonStates()
            self.updateTriggerSegmentIndicators()
            self.displayOptions()
            self.refreshStatus()
        }
        addSubview(shortcutRecorder)

        for (index, entry) in [("⌃ Control", CGEventFlags.maskControl), ("⇧ Shift", .maskShift), ("⌥ Option", .maskAlternate), ("⌘ Command", .maskCommand), ("Fn", .maskSecondaryFn)].enumerated() {
            let button = NSButton(checkboxWithTitle: entry.0, target: self, action: #selector(customChanged))
            button.font = .systemFont(ofSize: 12)
            button.frame = NSRect(x: 441 + CGFloat(index % 3) * 175, y: 320 + CGFloat(index / 3) * 22, width: 161, height: 20)
            addSubview(button); modifierButtons.append((button, entry.1))
        }
        keyPicker.addItems(withTitles: MappingKey.all.map { $0.name })
        keyPicker.autoenablesItems = false
        keyPicker.font = .systemFont(ofSize: 12.5, weight: .medium)
        keyPicker.setAccessibilityLabel(L("自定义主键"))
        keyPicker.target = self; keyPicker.action = #selector(customChanged)
        place(keyPicker, y: 366, h: 30)

        textEditor.isRichText = false; textEditor.allowsUndo = true
        textEditor.font = .systemFont(ofSize: 14)
        textEditor.textColor = SettingsTheme.ink
        textEditor.backgroundColor = SettingsTheme.subtleFill
        textEditor.insertionPointColor = SettingsTheme.forest
        textEditor.textContainerInset = NSSize(width: 13, height: 12)
        textEditor.isAutomaticQuoteSubstitutionEnabled = false
        textEditor.isAutomaticDashSubstitutionEnabled = false
        textEditor.isAutomaticTextReplacementEnabled = false
        textEditor.isVerticallyResizable = true; textEditor.autoresizingMask = [.width]
        textEditor.textContainer?.widthTracksTextView = true
        textEditor.delegate = self
        textEditor.setAccessibilityLabel(L("此按键的常用文本"))
        textScroll.hasVerticalScroller = true; textScroll.autohidesScrollers = true
        textScroll.borderType = .noBorder
        textScroll.documentView = textEditor
        textScroll.wantsLayer = true; textScroll.layer?.cornerRadius = 12; textScroll.layer?.masksToBounds = true
        place(textScroll, y: 278, h: 112)
        textEditor.frame = NSRect(origin: .zero, size: textScroll.contentSize)
        textEditor.minSize = NSSize(width: 0, height: textScroll.contentSize.height)
        textEditor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        targetLabel.font = .systemFont(ofSize: 12, weight: .medium); targetLabel.textColor = SettingsTheme.secondary
        place(targetLabel, y: 278, h: 22)
        targetField.delegate = self; targetField.isSelectable = true
        targetField.setAccessibilityLabel(L("应用路径或网页地址"))
        SettingsTheme.style(targetField)
        place(targetField, y: 306, h: 30)
        chooseAppButton.target = self; chooseAppButton.action = #selector(chooseApp)
        chooseAppButton.frame = NSRect(x: 440, y: 348, width: 148, height: 34)
        addSubview(chooseAppButton)

        place(actionPreview, y: 278, h: 112)

        hintPanel.frame = NSRect(x: 440, y: 404, width: 558, height: 68)
        hintPanel.radius = 12; hintPanel.fill = SettingsTheme.subtleFill; hintPanel.border = nil
        addSubview(hintPanel)
        hint.textColor = SettingsTheme.secondary; hint.font = .systemFont(ofSize: 11)
        hint.frame = NSRect(x: 454, y: 414, width: 530, height: 48); addSubview(hint)

        saveButton.target = self; saveButton.action = #selector(saveMappings)
        saveButton.frame = NSRect(x: 440, y: 488, width: 144, height: 36); addSubview(saveButton)
        resetButton.target = self; resetButton.action = #selector(resetKey)
        resetButton.toolTip = L("恢复此键的单击默认值，并清除双击和长按设置")
        resetButton.frame = NSRect(x: 592, y: 488, width: 138, height: 36); addSubview(resetButton)
        discardButton.target = self; discardButton.action = #selector(discardPressed)
        discardButton.toolTip = L("撤销尚未保存的全部草稿修改")
        discardButton.frame = NSRect(x: 738, y: 488, width: 110, height: 36); addSubview(discardButton)
        permissionButton.target = self; permissionButton.action = #selector(allowListener)
        permissionButton.frame = NSRect(x: 856, y: 488, width: 142, height: 36); addSubview(permissionButton)

        liveStatus.font = .systemFont(ofSize: 11, weight: .medium); liveStatus.textColor = SettingsTheme.secondary
        liveStatus.maximumNumberOfLines = 1
        liveStatus.lineBreakMode = .byTruncatingTail
        place(liveStatus, y: 534, h: 17)

        voiceStudio.frame = NSRect(x: 440, y: 122, width: 558, height: 420)
        voiceStudio.onSettingsChange = { [weak self] in
            guard let self else { return }
            if self.selected == 0 {
                self.currentLabel.stringValue = L("按住说话，松手结束 · 当前：%@", self.voiceSettings.trigger.summaryTitle)
            }
            self.onVoiceSettingsChange?()
        }
        addSubview(voiceStudio)

        displaySelection()
        captureHorizontalLayout()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        guard let stage = diagram.superview else { return }
        diagram.setFrameOrigin(NSPoint(x: (stage.bounds.width - diagram.frame.width) / 2, y: 120))
        deviceName.setFrameSize(NSSize(width: stage.bounds.width - 48, height: 25))
        modePicker.setFrameSize(NSSize(width: stage.bounds.width - 48, height: 34))
        capacity.setFrameSize(NSSize(width: stage.bounds.width - 48, height: 16))
    }

    func switchProfile() {
        guard displayedProfile != mapping.profile else { return }
        stopRecordingShortcuts()
        draftCache[displayedProfile] = (normalDrafts, mouseDrafts)
        displayedProfile = mapping.profile
        normalDrafts = draftCache[displayedProfile]?.normal ?? mapping.bindings
        mouseDrafts = draftCache[displayedProfile]?.mouse ?? mapping.mouseBindings
        selected = displayedProfile == .chromecast ? 8 : 7
        triggerPicker.selectedSegment = 0
        rebuildDiagram()
        displaySelection()
    }

    func stopRecordingShortcuts() {
        shortcutRecorder.stopRecording()
        voiceStudio.stopRecordingShortcut()
    }

    func reloadVoiceStudio() {
        voiceStudio.reloadFromSettings()
        if selected == 0 {
            currentLabel.stringValue = L("按住说话，松手结束 · 当前：%@", voiceSettings.trigger.summaryTitle)
        }
    }

    func updateVoiceLevel(_ level: Float, active: Bool, testingOnly: Bool) {
        voiceStudio.updateLevel(level, active: active, testingOnly: testingOnly)
    }

    func selectRemoteButton(code: UInt8, pulse: Bool = false) {
        guard remoteButtons[code] != nil else { return }
        stopRecordingShortcuts()
        selected = code
        displaySelection()
        if pulse {
            pulseResetWorkItem?.cancel()
            for (buttonCode, button) in remoteButtons {
                button.pulse = buttonCode == code
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                for button in self.remoteButtons.values { button.pulse = false }
            }
            pulseResetWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }
    }

    @discardableResult
    func saveAndApply() -> Bool {
        let invalid = [normalDrafts, mouseDrafts].flatMap { values in
            mapping.buttons.compactMap { button -> String? in
                values[String(button.code)]?.validationMessage(for: mapping.profile)
            }
        }.first
        guard invalid == nil else {
            refreshStatus()
            return false
        }
        mapping.save(normalDrafts, mouse: mouseDrafts)
        displaySelection()
        return !hasUnsavedChanges
    }

    func discardDrafts() {
        stopRecordingShortcuts()
        let prefix = "\(displayedProfile.rawValue)."
        preferredPresetIndices = preferredPresetIndices.filter { !$0.key.hasPrefix(prefix) }
        normalDrafts = mapping.bindings
        mouseDrafts = mapping.mouseBindings
        displaySelection()
    }

    private func rebuildDiagram() {
        diagram.subviews.forEach { $0.removeFromSuperview() }
        remoteButtons.removeAll()
        diagram.profile = mapping.profile
        let googlePositions: [(UInt8, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (3,"↑",120,37,42,43), (4,"↓",120,150,42,43),
            (5,"←",64,93,43,43), (6,"→",176,93,43,43), (7,"OK",114,88,54,54),
            (11,"↩",70,215,62,42), (0,L("语音"),151,215,62,42),
            (10,L("主页"),70,278,62,42), (8,L("静音"),151,278,62,42),
            (14,"YouTube",70,341,62,42), (15,"Netflix",151,341,62,42),
            (1,L("电源"),70,404,62,42), (17,L("信源"),151,404,62,42),
            (12,"＋",246,153,36,39), (13,"−",246,194,36,39)
        ]
        let xiaomiPositions: [(UInt8, String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (1,L("电源"),70,43,62,42), (0,L("语音"),151,43,62,42),
            (3,"↑",120,109,42,43), (4,"↓",120,222,42,43),
            (5,"←",64,165,43,43), (6,"→",176,165,43,43), (7,"OK",114,160,54,54),
            (11,"↩",70,286,62,42), (12,"＋",151,286,62,42),
            (10,L("主页"),70,348,62,42), (13,"−",151,348,62,42),
            (18,L("菜单"),70,410,62,42), (19,"TV",151,410,62,42)
        ]
        let positions = mapping.profile == .chromecast ? googlePositions : xiaomiPositions
        for (code, title, x, y, w, h) in positions {
            let button = RemoteKeyButton(frame: NSRect(x: x, y: y, width: w, height: h))
            button.title = title; button.tag = Int(code); button.target = self; button.action = #selector(selectKey(_:))
            button.font = .systemFont(ofSize: title.count > 5 ? 11 : 14, weight: .medium)
            button.setAccessibilityLabel(code == 0 ? L("语音键，按住说话") : mapping.buttons.first { $0.code == code }!.name)
            diagram.addSubview(button); remoteButtons[code] = button
        }
        if mapping.profile == .chromecast {
            let volume = NSTextField(labelWithString: L("音量"))
            volume.font = .systemFont(ofSize: 11); volume.textColor = SettingsTheme.color(0xB7C6AE)
            volume.frame = NSRect(x: 250, y: 132, width: 40, height: 18); diagram.addSubview(volume)
        }
        let brand = NSTextField(labelWithString: mapping.profile == .chromecast ? "Chromecast" : L("小米 RC003"))
        brand.font = .systemFont(ofSize: 12, weight: .medium); brand.textColor = SettingsTheme.color(0x6B756A)
        brand.alignment = .center; brand.frame = NSRect(x: 74, y: 478, width: 133, height: 20); diagram.addSubview(brand)
        deviceName.stringValue = mapping.profile == .chromecast ? "Google Chromecast" : L("小米 RC003")
        capacity.stringValue = L("共 %@ 个按键 · 按下实体键自动定位", String(mapping.buttons.count))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func place(_ view: NSView, y: CGFloat, h: CGFloat) {
        view.frame = NSRect(x: 440, y: y, width: 558, height: h); addSubview(view)
    }

    private var selectedButton: MappedButton? { mapping.buttons.first { $0.code == selected } }
    private var selectedTrigger: ButtonTrigger { ButtonTrigger.allCases[triggerPicker.selectedSegment] }
    private var selectedPresetIndex: Int { actionPicker.selectedItem?.tag ?? 0 }
    private var selectionSlotKey: String {
        "\(displayedProfile.rawValue).\(editingMouse ? "m" : "n").\(selected).\(selectedTrigger.rawValue)"
    }
    private func presetItem(_ index: Int) -> NSMenuItem? {
        actionPicker.itemArray.first { !$0.isSeparatorItem && !$0.isSectionHeader && $0.tag == index }
    }
    private var selectedConfiguration: ButtonBinding {
        guard let selectedButton else { return .init(singleClick: .init(kind: .original)) }
        return KeyMapping.binding(selectedButton, normal: normalDrafts, mouse: mouseDrafts, inMouseMode: editingMouse)
    }
    private var selectedBinding: ButtonAction { selectedConfiguration[selectedTrigger] ?? .init(kind: .disabled) }
    private var reservedToggle: Bool { editingMouse && selectedConfiguration.togglesMouseMode }
    private func setSelectedBinding(_ value: ButtonAction?) {
        guard !reservedToggle else { return }
        var configuration = selectedConfiguration
        configuration[selectedTrigger] = value
        drafts[String(selected)] = configuration
    }

    @objc private func selectKey(_ sender: NSButton) {
        stopRecordingShortcuts()
        selected = UInt8(sender.tag)
        displaySelection()
    }
    @objc private func triggerChanged() {
        stopRecordingShortcuts()
        displaySelection()
    }
    @objc private func modeChanged() {
        stopRecordingShortcuts()
        triggerPicker.selectedSegment = 0
        displaySelection()
    }
    @objc private func searchFilterChanged() {
        applyActionSearchFilter()
    }
    @objc private func discardPressed() {
        discardDrafts()
    }

    private func updateRemoteButtonStates() {
        for (code, button) in remoteButtons {
            button.selected = code == selected
            if let physical = mapping.buttons.first(where: { $0.code == code }) {
                let draftConfig = KeyMapping.binding(physical, normal: normalDrafts, mouse: mouseDrafts, inMouseMode: editingMouse)
                let savedConfig = mapping.binding(physical, mouse: editingMouse)
                button.dirty = draftConfig != savedConfig
                button.toolTip = "\(physical.name) → \(draftConfig.summary)"
            } else {
                button.dirty = false
                button.toolTip = L("按住说话，松开结束 · 点击配置语音工作台")
            }
        }
    }

    private func updateTriggerSegmentIndicators() {
        guard let physical = selectedButton else {
            triggerPicker.configuredSegments = []
            return
        }
        let defaultSingle = editingMouse ? KeyMapping.mouseDefault(physical.code) : physical.initial
        let config = selectedConfiguration
        var configured = Set<Int>()
        for (index, trigger) in ButtonTrigger.allCases.enumerated() {
            switch trigger {
            case .singleClick:
                if config.singleClick != defaultSingle { configured.insert(index) }
            case .doubleClick:
                if config.doubleClick != nil { configured.insert(index) }
            case .longPress:
                if config.longPress != nil { configured.insert(index) }
            }
        }
        triggerPicker.configuredSegments = configured
    }

    private func applyActionSearchFilter() {
        guard let menu = actionPicker.menu else { return }
        let query = actionSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let voiceIndex = presets.firstIndex { $0.binding?.kind == .remoteVoice }
        for item in menu.items {
            if item.isSectionHeader || item.isSeparatorItem {
                item.isHidden = false
                continue
            }
            let idx = item.tag
            var baseHidden = false
            if idx == voiceIndex && mapping.profile != .chromecast { baseHidden = true }
            if presets.indices.contains(idx), presets[idx].binding?.kind == .toggleMouseMode, editingMouse && !reservedToggle {
                baseHidden = true
            }
            if baseHidden {
                item.isHidden = true
            } else if query.isEmpty || item === actionPicker.selectedItem {
                item.isHidden = false
            } else if presets.indices.contains(idx) {
                let preset = presets[idx]
                item.isHidden = !preset.title.lowercased().contains(query) && !preset.group.lowercased().contains(query)
            }
        }
        if !query.isEmpty {
            var sectionHeader: NSMenuItem?
            var sectionHasVisible = false
            for item in menu.items {
                if item.isSeparatorItem {
                    item.isHidden = true
                } else if item.isSectionHeader {
                    if let prevHeader = sectionHeader { prevHeader.isHidden = !sectionHasVisible }
                    sectionHeader = item
                    sectionHasVisible = false
                } else if !item.isHidden {
                    sectionHasVisible = true
                }
            }
            if let lastHeader = sectionHeader { lastHeader.isHidden = !sectionHasVisible }
        }
    }

    private func displaySelection() {
        updateRemoteButtonStates()
        let voice = selected == 0
        studioEyebrow.stringValue = voice ? L("语音设置") : L("按键设置")
        nameLabel.stringValue = selectedButton?.name ?? L("语音键")
        triggerPicker.isEnabled = !voice
        actionPicker.isEnabled = !voice && !reservedToggle
        resetButton.isEnabled = !voice && !reservedToggle

        voiceStudio.isHidden = !voice
        triggerEyebrow.isHidden = voice
        triggerPicker.isHidden = voice
        actionLabel.isHidden = voice
        actionPicker.isHidden = voice
        searchPill.isHidden = voice || reservedToggle
        actionSearchField.isHidden = voice || reservedToggle
        hintPanel.isHidden = voice
        hint.isHidden = voice
        saveButton.isHidden = voice
        resetButton.isHidden = voice
        discardButton.isHidden = voice || !hasUnsavedChanges
        liveStatus.isHidden = voice

        if voice { voiceStudio.reloadFromSettings() }

        updateTriggerSegmentIndicators()
        presetItem(0)?.title = selectedTrigger == .singleClick ? L("原按键功能") : L("未设置")
        presetItem(2)?.title = selectedTrigger == .longPress ? L("Fn 按键（长按后保持）") : presets[2].title
        presetItem(2)?.isEnabled = selectedTrigger != .doubleClick
        if let voiceIndex = presets.firstIndex(where: { $0.binding?.kind == .remoteVoice }), let item = presetItem(voiceIndex) {
            item.isHidden = mapping.profile != .chromecast
            item.isEnabled = selectedTrigger != .doubleClick
            item.title = selectedTrigger == .longPress ? L("遥控器麦克风（长按后开麦）") : presets[voiceIndex].title
        }
        for (index, preset) in presets.enumerated() {
            if preset.binding?.kind == .toggleMouseMode {
                presetItem(index)?.isHidden = editingMouse && !reservedToggle
                presetItem(index)?.isEnabled = !editingMouse
            }
            if preset.binding?.isMouseMovement == true { presetItem(index)?.isEnabled = selectedTrigger != .doubleClick }
        }
        keyPicker.item(at: 0)?.isEnabled = selectedTrigger != .doubleClick
        let value = selectedBinding
        let unset = selectedTrigger != .singleClick && selectedConfiguration[selectedTrigger] == nil
        let targetIndex = ActionCatalog.index(for: value, preferredIndex: preferredPresetIndices[selectionSlotKey])
        actionPicker.select(presetItem(unset ? 0 : targetIndex))
        applyActionSearchFilter()
        textEditor.string = value.text ?? ""
        targetField.stringValue = value.kind == .openApp ? value.appPath ?? "" : value.url ?? ""
        keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == value.usage } ?? 0)
        for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: value.modifiers).contains(flag) ? .on : .off }
        shortcutRecorder.allowFnOnly = selectedTrigger != .doubleClick
        shortcutRecorder.usage = value.usage
        shortcutRecorder.modifiers = value.modifiers
        capacity.stringValue = editingMouse ? L("当前编辑：鼠标键位 · 切换键在普通键位设置") :
            L("共 %@ 个按键 · 按下实体键自动定位", String(mapping.buttons.count))
        capacity.toolTip = capacity.stringValue
        displayOptions()
        refreshStatus()
    }

    private func displayOptions() {
        currentLabel.stringValue = selected == 0 ?
            L("按住说话，松手结束 · 当前：%@", voiceSettings.trigger.summaryTitle) :
            L("已保存 · %@：%@", selectedTrigger.title, mapping.binding(selectedButton!, mouse: editingMouse)[selectedTrigger].map(ActionCatalog.displayName) ?? L("未设置"))
        currentLabel.toolTip = currentLabel.stringValue

        if let selectedButton { remoteButtons[selected]?.toolTip = "\(selectedButton.name) → \(selectedConfiguration.summary)" }
        let voice = selected == 0
        let custom = !voice && selectedPresetIndex == presets.count - 1
        if !custom { shortcutRecorder.stopRecording() }
        shortcutRecorder.isHidden = !custom
        keyPicker.isHidden = !custom
        modifierButtons.forEach { $0.0.isHidden = !custom; $0.0.isEnabled = !selectedBinding.isFn }
        textScroll.isHidden = voice || selectedBinding.kind != .text
        let hasEditor = custom || selectedBinding.kind == .text || selectedBinding.kind == .openApp || selectedBinding.kind == .openURL
        actionPreview.isHidden = voice || hasEditor
        actionPreview.binding = selectedConfiguration[selectedTrigger]
        actionPreview.voice = voice || selectedBinding.kind == .remoteVoice
        let app = !voice && selectedBinding.kind == .openApp
        let webpage = !voice && selectedBinding.kind == .openURL
        targetLabel.isHidden = !app && !webpage
        targetField.isHidden = !app && !webpage
        targetLabel.stringValue = app ? L("要打开的 Mac 应用") : L("要打开的网页地址")
        targetField.isEditable = webpage
        targetField.placeholderString = app ? L("点击下方按钮选择 .app") : "https://example.com"
        chooseAppButton.isHidden = !app
        if reservedToggle {
            hint.stringValue = L("此键的模式切换手势在两种模式中都保留。\n可切换上方手势查看；请在“普通键位”中修改。")
        } else if selectedBinding.kind == .toggleMouseMode {
            hint.stringValue = L("用此键的%@切换模式；松开所有键后生效。\n再次使用相同手势退出。鼠标键位会保留此键的所有手势。", selectedTrigger.title)
        } else if selectedBinding.isMouseMovement {
            hint.stringValue = L("按住持续移动，松开立即停止；长按移动逐渐加速。\n可同时按两个方向斜向移动。")
        } else if selectedBinding.isMouseAction {
            hint.stringValue = L("在指针当前位置点击一次，按住不会重复点击。\n连续按两次左键可双击。")
        } else if voice {
            hint.stringValue = ""
        } else if selectedBinding.kind == .remoteVoice {
            hint.stringValue = selectedTrigger == .longPress ?
                L("按住约 0.55 秒后开启 Google 遥控器麦克风，松开结束。\n需要 ATVV 1.0；旧协议请使用原语音键。") :
                L("按下开启 Google 遥控器麦克风，松开结束。\n需要 ATVV 1.0；旧协议请使用原语音键。")
        } else if selectedBinding.isFn {
            hint.stringValue = selectedTrigger == .longPress ?
                L("仅模拟 Fn：长按约 0.55 秒后保持，松开释放。\n使用目标软件选择的麦克风，不开启遥控器麦克风。") :
                L("仅模拟 Fn：按住保持，松开释放。\n使用目标软件选择的麦克风，不开启遥控器麦克风。")
        } else if selectedBinding.kind == .text {
            hint.stringValue = L("先将光标放入目标输入框，再按遥控器。\n按一次粘贴一次，不发送回车；文本保存在本机。")
        } else if app {
            hint.stringValue = L("按一次打开并激活所选应用，已运行时切换到它。\n每个按键、每种触发方式可选择不同应用。")
        } else if webpage {
            hint.stringValue = L("按一次交给默认浏览器打开，可能新建标签页。\n支持 http:// 和 https:// 地址。")
        } else if selectedBinding.kind == .systemKey {
            hint.stringValue = L("发送一次系统音量、亮度或媒体按键。\n亮度取决于显示器支持，播放控制取决于当前媒体应用。")
        } else if selectedBinding.kind == .nextDisplay {
            hint.stringValue = L("切到下一块屏幕的可见窗口，鼠标随之移入。\n不移动窗口，不切换桌面空间；按一次切换一次。")
        } else if selectedBinding.kind == .nextWindow {
            hint.stringValue = L("在当前屏幕的可见普通窗口间循环。\n跳过最小化窗口；按一次切换一次。")
        } else if custom {
            hint.stringValue = L("点击上方录制框直接按下键盘组合键，或在下方手动选择修饰键与主键。")
        } else if selectedBinding.kind == .key {
            hint.stringValue = L("按下遥控器时，向当前活动窗口发送 %@。", selectedBinding.title)
        } else {
            hint.stringValue = L("切换按键后未保存的修改也会暂存，点击「保存并生效」后统一应用。")
        }
        if !voice {
            if let error = selectedConfiguration.validationMessage(for: mapping.profile) {
                hint.stringValue = error
            } else if selectedConfiguration.hasGestures {
                let gestureNote: String
                if selectedConfiguration.doubleClick != nil && selectedConfiguration.longPress != nil {
                    gestureNote = L("已开启多手势：连按两次触发双击，按住约半秒触发长按。")
                } else if selectedConfiguration.doubleClick != nil {
                    gestureNote = L("已开启双击：连按两次触发双击，单按松手约 0.3 秒后触发单击。")
                } else {
                    gestureNote = L("已开启长按：短按松手触发单击，按住约半秒触发长按。")
                }
                hint.stringValue += "\n" + gestureNote
            } else if selectedTrigger != .singleClick {
                hint.stringValue += "\n" + L("当前手势未设置动作，不影响单击响应速度。")
            }
        }
    }

    @objc private func actionChanged() {
        guard selectedButton != nil else { return }
        stopRecordingShortcuts()
        if selectedTrigger != .singleClick && selectedPresetIndex == 0 {
            preferredPresetIndices.removeValue(forKey: selectionSlotKey)
            setSelectedBinding(nil)
        } else if let value = presets[selectedPresetIndex].binding {
            if presets[selectedPresetIndex].isAlias {
                preferredPresetIndices[selectionSlotKey] = selectedPresetIndex
            } else {
                preferredPresetIndices.removeValue(forKey: selectionSlotKey)
            }
            var next = value
            if next.kind == .text { next.text = selectedBinding.text ?? "" }
            if next.kind == .openApp { next.appPath = selectedBinding.appPath }
            if next.kind == .openURL { next.url = selectedBinding.url }
            setSelectedBinding(next)
            textEditor.string = next.text ?? ""
            targetField.stringValue = next.kind == .openApp ? next.appPath ?? "" : next.url ?? ""
        } else {
            preferredPresetIndices.removeValue(forKey: selectionSlotKey)
            let current = selectedBinding
            if current.kind == .key {
                keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == current.usage } ?? 0)
                for (button, flag) in modifierButtons { button.state = CGEventFlags(rawValue: current.modifiers).contains(flag) ? .on : .off }
            } else {
                keyPicker.selectItem(at: MappingKey.all.firstIndex { $0.usage == 0x28 } ?? 0)
                modifierButtons.forEach { $0.0.state = .off }
            }
            customChanged()
            return
        }
        updateRemoteButtonStates()
        updateTriggerSegmentIndicators()
        displayOptions()
        refreshStatus()
    }

    @objc private func customChanged() {
        let usage = MappingKey.all[keyPicker.indexOfSelectedItem].usage
        if usage == MappingKey.fnUsage {
            modifierButtons.forEach { $0.0.state = .off }
        }
        let flags = modifierButtons.filter { $0.0.state == .on }.reduce(UInt64(0)) { $0 | $1.1.rawValue }
        shortcutRecorder.usage = usage
        shortcutRecorder.modifiers = flags
        setSelectedBinding(.init(kind: .key, usage: usage, modifiers: flags))
        updateRemoteButtonStates()
        updateTriggerSegmentIndicators()
        displayOptions()
        refreshStatus()
    }

    func textDidChange(_ notification: Notification) {
        guard selected != 0, selectedBinding.kind == .text else { return }
        var value = selectedBinding
        value.text = textEditor.string
        setSelectedBinding(value)
        updateRemoteButtonStates()
        refreshStatus()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === targetField, selected != 0, selectedBinding.kind == .openURL else { return }
        var value = selectedBinding
        value.url = targetField.stringValue
        setSelectedBinding(value)
        updateRemoteButtonStates()
        displayOptions()
        refreshStatus()
    }

    @objc private func chooseApp() {
        guard let window, selectedBinding.kind == .openApp else { return }
        let profile = displayedProfile, code = selected, trigger = selectedTrigger, mouse = editingMouse
        let panel = NSOpenPanel()
        panel.title = L("选择要打开的应用")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let path = panel.url?.path,
                  self.displayedProfile == profile, self.selected == code, self.selectedTrigger == trigger, self.editingMouse == mouse,
                  self.selectedBinding.kind == .openApp else { return }
            guard KeyMapping.applicationURL(path) != nil else { self.liveStatus.stringValue = L("请选择可运行的 Mac 应用"); return }
            var value = self.selectedBinding
            value.appPath = path
            self.setSelectedBinding(value)
            self.displaySelection()
        }
    }

    @objc private func saveMappings() {
        _ = saveAndApply()
    }

    // Import/restore changes only the drafts; Save and Apply remains explicit.
    func importConfiguration(_ data: Data) throws {
        let archive = try MappingArchive.read(data, for: displayedProfile)
        let prefix = "\(displayedProfile.rawValue)."
        preferredPresetIndices = preferredPresetIndices.filter { !$0.key.hasPrefix(prefix) }
        normalDrafts = archive.normal; mouseDrafts = archive.mouse
        displaySelection()
    }

    func importConfiguration() {
        guard let window, window.attachedSheet == nil else { return }
        let profile = displayedProfile
        let panel = NSOpenPanel()
        panel.title = L("导入键位到草稿…")
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url, self.displayedProfile == profile else { return }
            do {
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= MappingArchive.maximumBytes else { throw MappingArchive.Failure.tooLarge }
                try self.importConfiguration(Data(contentsOf: url))
                self.liveStatus.stringValue = L("配置已载入草稿，请检查后点击“保存并生效”")
            } catch { self.liveStatus.stringValue = error.localizedDescription }
            self.liveStatus.toolTip = self.liveStatus.stringValue
        }
    }

    func exportConfiguration() {
        guard let window, window.attachedSheet == nil else { return }
        do {
            let data = try MappingArchive(profile: displayedProfile, normal: mapping.bindings, mouse: mapping.mouseBindings).data()
            let panel = NSSavePanel()
            panel.title = L("导出已保存键位…"); panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Remote-Vibe-\(displayedProfile.rawValue).json"
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    self.liveStatus.stringValue = L("已导出此型号的普通键位和鼠标键位")
                } catch { self.liveStatus.stringValue = error.localizedDescription }
                self.liveStatus.toolTip = self.liveStatus.stringValue
            }
        } catch { liveStatus.stringValue = error.localizedDescription }
    }

    func restoreConfiguration() {
        guard let backup = mapping.configurationBackup() else { liveStatus.stringValue = L("暂无可用的配置备份"); return }
        let prefix = "\(displayedProfile.rawValue)."
        preferredPresetIndices = preferredPresetIndices.filter { !$0.key.hasPrefix(prefix) }
        normalDrafts = backup.normal; mouseDrafts = backup.mouse
        displaySelection()
        liveStatus.stringValue = L("配置已载入草稿，请检查后点击“保存并生效”")
        self.liveStatus.toolTip = liveStatus.stringValue
    }

    @objc private func resetKey() {
        guard selectedButton != nil, !reservedToggle else { return }
        stopRecordingShortcuts()
        let prefix = "\(displayedProfile.rawValue).\(editingMouse ? "m" : "n").\(selected)."
        preferredPresetIndices = preferredPresetIndices.filter { !$0.key.hasPrefix(prefix) }
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
        let dirty = hasUnsavedChanges
        let invalid = [normalDrafts, mouseDrafts].flatMap { values in
            mapping.buttons.compactMap { button -> String? in
                values[String(button.code)]?.validationMessage(for: mapping.profile).map { "\(button.name)：\($0)" }
            }
        }.first
        let voice = selected == 0
        saveButton.isHidden = voice
        discardButton.isHidden = voice || !dirty
        liveStatus.isHidden = voice
        if let invalid {
            liveStatus.stringValue = invalid
            liveStatus.textColor = SettingsTheme.error
        } else if let notice = mapping.configurationNotice {
            liveStatus.stringValue = notice
            liveStatus.textColor = SettingsTheme.warning
        } else if dirty {
            liveStatus.stringValue = L("有未保存的键位修改，点击「保存并生效」后启用")
            liveStatus.textColor = SettingsTheme.warning
        } else {
            liveStatus.stringValue = mapping.status
            liveStatus.textColor = SettingsTheme.secondary
        }
        liveStatus.toolTip = liveStatus.stringValue
        hint.textColor = selectedConfiguration.validationMessage == nil ? SettingsTheme.secondary : SettingsTheme.error
        permissionButton.isHidden = voice || (mapping.listeningAllowed && AXIsProcessTrusted()) ||
            !mapping.buttons.contains { KeyMapping.binding($0, normal: normalDrafts, mouse: mouseDrafts, inMouseMode: editingMouse).usesListener }
        permissionButton.title = !mapping.listeningAllowed ? L("允许输入监控") : L("允许辅助功能")
        saveButton.isEnabled = invalid == nil && (dirty || mapping.needsApply || mapping.configurationNotice != nil)
    }
}
