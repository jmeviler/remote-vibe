import AppKit

final class VoiceStudioView: SettingsPage {
    private let settings: VoiceInputSettings
    var onSettingsChange: (() -> Void)?
    var onShowGuide: (() -> Void)?

    private let meterCard = SettingsPanel()
    private let meterStatusLabel = NSTextField(labelWithString: "")
    private let meterView = VoiceLevelMeterView()
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presetHintPanel = SettingsPanel()
    private let presetHintLabel = NSTextField(wrappingLabelWithString: "")
    private let customModeControl = NSSegmentedControl()
    private let customRecorder = ShortcutRecorderControl()
    private let switchMicCheckbox = NSButton(checkboxWithTitle: L("说话时自动切到遥控器麦克风（推荐）"), target: nil, action: nil)
    private let switchMicDetail = NSTextField(wrappingLabelWithString: L("戴蓝牙耳机开会不想声音闪断时，可在微信里固定选 Chromecast Mic 后关闭此项。"))
    private let fastCheckbox = NSButton(checkboxWithTitle: L("快速连续说话（缩短松手后的等待时间）"), target: nil, action: nil)
    private let fastDetail = NSTextField(wrappingLabelWithString: L("适合一句接一句连续说话；如果开头偶发漏掉第一个字可关闭。"))
    private let guideButton = SettingsTheme.secondaryButton(L("查看微信语音设置步骤"))

    private var customMode: VoiceTriggerMode = .hold
    private var customUsage: UInt64 = 0x2C
    private var customModifiers: UInt64 = CGEventFlags.maskAlternate.rawValue
    private var editingCustom = false

    init(settings: VoiceInputSettings) {
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 558, height: 414))

        meterCard.fill = SettingsTheme.subtleFill
        meterCard.border = SettingsTheme.line
        meterCard.radius = 14
        meterCard.frame = NSRect(x: 0, y: 0, width: 558, height: 82)
        addSubview(meterCard)

        meterStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        meterStatusLabel.textColor = SettingsTheme.ink
        meterStatusLabel.frame = NSRect(x: 16, y: 12, width: 526, height: 18)
        addSubview(meterStatusLabel)

        meterView.frame = NSRect(x: 16, y: 40, width: 526, height: 26)
        addSubview(meterView)

        let triggerHeader = SettingsTheme.eyebrow(L("01 / 语音输入方式"))
        triggerHeader.frame = NSRect(x: 0, y: 96, width: 558, height: 16)
        addSubview(triggerHeader)

        presetPopup.addItems(withTitles: [
            L("微信语音输入（默认 · 按住 Fn）"),
            L("按住右 Option 说话（豆包 / Whisper 等）"),
            L("点按 Option + Space 开始/结束（系统听写等）"),
            L("仅把遥控器当麦克风（不发快捷键）"),
            L("自定义语音触发快捷键…")
        ])
        presetPopup.font = .systemFont(ofSize: 13, weight: .medium)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.setAccessibilityLabel(L("语音输入触发方式"))
        presetPopup.frame = NSRect(x: 0, y: 118, width: 558, height: 34)
        addSubview(presetPopup)

        presetHintPanel.fill = SettingsTheme.subtleFill
        presetHintPanel.border = nil
        presetHintPanel.radius = 11
        presetHintPanel.frame = NSRect(x: 0, y: 160, width: 558, height: 64)
        addSubview(presetHintPanel)

        presetHintLabel.font = .systemFont(ofSize: 11)
        presetHintLabel.textColor = SettingsTheme.secondary
        presetHintLabel.frame = NSRect(x: 14, y: 171, width: 530, height: 42)
        addSubview(presetHintLabel)

        customModeControl.segmentCount = VoiceTriggerMode.allCases.count
        customModeControl.segmentStyle = .separated
        customModeControl.selectedSegmentBezelColor = SettingsTheme.forest
        customModeControl.segmentDistribution = .fillEqually
        customModeControl.font = .systemFont(ofSize: 12, weight: .medium)
        for (index, mode) in VoiceTriggerMode.allCases.enumerated() {
            customModeControl.setLabel(mode.title, forSegment: index)
        }
        customModeControl.target = self
        customModeControl.action = #selector(customModeChanged)
        customModeControl.frame = NSRect(x: 0, y: 160, width: 558, height: 30)
        addSubview(customModeControl)

        customRecorder.allowFnOnly = false
        customRecorder.frame = NSRect(x: 0, y: 198, width: 558, height: 38)
        customRecorder.onShortcutRecorded = { [weak self] usage, modifiers in
            guard let self else { return }
            self.customUsage = usage
            self.customModifiers = modifiers
            self.applyCustomTrigger()
        }
        addSubview(customRecorder)

        let optionsHeader = SettingsTheme.eyebrow(L("02 / 通话与连说体验"))
        optionsHeader.frame = NSRect(x: 0, y: 250, width: 558, height: 16)
        addSubview(optionsHeader)

        switchMicCheckbox.font = .systemFont(ofSize: 13, weight: .medium)
        switchMicCheckbox.target = self
        switchMicCheckbox.action = #selector(switchMicChanged)
        switchMicCheckbox.frame = NSRect(x: 0, y: 272, width: 558, height: 22)
        addSubview(switchMicCheckbox)

        switchMicDetail.font = .systemFont(ofSize: 11)
        switchMicDetail.textColor = SettingsTheme.secondary
        switchMicDetail.frame = NSRect(x: 22, y: 295, width: 536, height: 28)
        addSubview(switchMicDetail)

        fastCheckbox.font = .systemFont(ofSize: 13, weight: .medium)
        fastCheckbox.target = self
        fastCheckbox.action = #selector(fastChanged)
        fastCheckbox.frame = NSRect(x: 0, y: 325, width: 558, height: 22)
        addSubview(fastCheckbox)

        fastDetail.font = .systemFont(ofSize: 11)
        fastDetail.textColor = SettingsTheme.secondary
        fastDetail.frame = NSRect(x: 22, y: 348, width: 536, height: 26)
        addSubview(fastDetail)

        guideButton.target = self
        guideButton.action = #selector(showGuidePressed)
        guideButton.frame = NSRect(x: 0, y: 378, width: 196, height: 34)
        addSubview(guideButton)

        captureHorizontalLayout()
        reloadFromSettings()
        updateLevel(0, active: false, testingOnly: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func stopRecordingShortcut() {
        customRecorder.stopRecording()
    }

    func updateLevel(_ level: Float, active: Bool, testingOnly: Bool) {
        meterView.active = active
        meterView.level = active ? level : 0
        if active {
            meterStatusLabel.stringValue = testingOnly ?
                L("正在试麦 · 遥控器麦克风收音正常（切到输入框即可直接说话打字）") :
                L("正在说话 · 遥控器麦克风信号正常")
            meterStatusLabel.textColor = SettingsTheme.accentDot
        } else {
            meterStatusLabel.stringValue = L("按住手里的遥控器语音键，可直接在这里看麦克风音量条跳动")
            meterStatusLabel.textColor = SettingsTheme.ink
        }
    }

    func reloadFromSettings() {
        let current = settings.trigger.normalized
        switch current {
        case .holdFn:
            editingCustom = false
            presetPopup.selectItem(at: 0)
        case .holdRightOption:
            editingCustom = false
            presetPopup.selectItem(at: 1)
        case .tapOptionSpace:
            editingCustom = false
            presetPopup.selectItem(at: 2)
        case .audioOnly:
            editingCustom = false
            presetPopup.selectItem(at: 3)
        case let .custom(mode, usage, modifiers):
            editingCustom = true
            customMode = mode
            customUsage = usage
            customModifiers = modifiers
            presetPopup.selectItem(at: 4)
        }
        customModeControl.selectedSegment = VoiceTriggerMode.allCases.firstIndex(of: customMode) ?? 0
        customRecorder.usage = customUsage
        customRecorder.modifiers = customModifiers
        switchMicCheckbox.state = settings.switchDefaultInput ? .on : .off
        fastCheckbox.state = settings.fastTurnaround ? .on : .off
        refreshVisibility()
    }

    private func refreshVisibility() {
        customModeControl.isHidden = !editingCustom
        customRecorder.isHidden = !editingCustom
        presetHintPanel.isHidden = editingCustom
        presetHintLabel.isHidden = editingCustom
        if !editingCustom {
            customRecorder.stopRecording()
            switch settings.trigger.normalized {
            case .holdFn:
                presetHintLabel.stringValue = L("保持微信在后台运行并开启“长按 Fn 全局语音输入”，点击任意输入框后按住遥控器说话即可出字。")
            case .holdRightOption:
                presetHintLabel.stringValue = L("按住遥控器语音键时自动按住右 Option，松开自动释放，适合豆包桌面端、Superwhisper 等。")
            case .tapOptionSpace:
                presetHintLabel.stringValue = L("按下遥控器语音键时点按一次 ⌥Space 开始，松手排空尾音后再点按一次 ⌥Space 结束。")
            case .audioOnly:
                presetHintLabel.stringValue = L("只把遥控器声音送入 Chromecast Mic 虚拟麦克风，不模拟任何键盘按键（无需辅助功能权限）。")
            case .custom:
                break
            }
        }
    }

    @objc private func presetChanged() {
        switch presetPopup.indexOfSelectedItem {
        case 0:
            editingCustom = false
            settings.trigger = .holdFn
        case 1:
            editingCustom = false
            settings.trigger = .holdRightOption
        case 2:
            editingCustom = false
            settings.trigger = .tapOptionSpace
        case 3:
            editingCustom = false
            settings.trigger = .audioOnly
        default:
            editingCustom = true
            applyCustomTrigger()
            return
        }
        refreshVisibility()
        onSettingsChange?()
    }

    @objc private func customModeChanged() {
        customMode = VoiceTriggerMode.allCases[max(0, customModeControl.selectedSegment)]
        applyCustomTrigger()
    }

    private func applyCustomTrigger() {
        settings.trigger = .custom(mode: customMode, usage: customUsage, modifiers: customModifiers)
        customRecorder.usage = customUsage
        customRecorder.modifiers = customModifiers
        refreshVisibility()
        onSettingsChange?()
    }

    @objc private func switchMicChanged() {
        settings.switchDefaultInput = switchMicCheckbox.state == .on
        onSettingsChange?()
    }

    @objc private func fastChanged() {
        settings.fastTurnaround = fastCheckbox.state == .on
        onSettingsChange?()
    }

    @objc private func showGuidePressed() {
        onShowGuide?()
    }
}
