import AppKit

final class VoiceStudioView: SettingsPage {
    private let settings: VoiceInputSettings
    var onSettingsChange: (() -> Void)?

    private let meterCard = SettingsPanel()
    private let meterStatusLabel = NSTextField(labelWithString: "")
    private let meterView = VoiceLevelMeterView()
    private let presetPopup = StyledPopUpButton(frame: .zero, pullsDown: false)
    private let presetHintPanel = SettingsPanel()
    private let presetHintLabel = NSTextField(wrappingLabelWithString: "")
    private let customModeControl = StyledSegmentedControl()
    private let customRecorder = ShortcutRecorderControl()
    private let switchMicCheckbox = NSButton(checkboxWithTitle: L("说话时自动切换系统默认麦克风（推荐）"), target: nil, action: nil)
    private let switchMicDetail = NSTextField(wrappingLabelWithString: L("关闭后不再改动系统默认麦克风（适合戴蓝牙耳机开会防切麦，需在语音软件内手动选定 Chromecast Mic）。"))
    private let fastCheckbox = NSButton(checkboxWithTitle: L("快速连说模式"), target: nil, action: nil)
    private let fastDetail = NSTextField(wrappingLabelWithString: L("缩短松手后的等待时间，一句接一句说更快；若每句开头偶尔吞字，请关闭此项。"))

    private var customMode: VoiceTriggerMode = .hold
    private var customUsage: UInt64 = 0x2C
    private var customModifiers: UInt64 = CGEventFlags.maskAlternate.rawValue
    private var editingCustom = false

    init(settings: VoiceInputSettings) {
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 558, height: 428))

        meterCard.fill = SettingsTheme.subtleFill
        meterCard.border = SettingsTheme.line
        meterCard.radius = 14
        meterCard.frame = NSRect(x: 0, y: 0, width: 558, height: 86)
        addSubview(meterCard)

        meterStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        meterStatusLabel.textColor = SettingsTheme.ink
        meterStatusLabel.frame = NSRect(x: 16, y: 15, width: 526, height: 18)
        addSubview(meterStatusLabel)

        meterView.frame = NSRect(x: 16, y: 44, width: 526, height: 24)
        addSubview(meterView)

        let triggerHeader = SettingsTheme.eyebrow(L("语音输入方式"))
        triggerHeader.frame = NSRect(x: 0, y: 106, width: 558, height: 16)
        addSubview(triggerHeader)

        presetPopup.addItems(withTitles: [
            L("微信全局语音输入（按住 Fn）"),
            L("豆包 / Superwhisper 等（按住右 Option）"),
            L("系统听写等开关模式（点按 Option + Space）"),
            L("仅作麦克风收音（不发快捷键）"),
            L("自定义语音触发快捷键…")
        ])
        presetPopup.font = .systemFont(ofSize: 13.5, weight: .medium)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.setAccessibilityLabel(L("语音输入触发方式"))
        presetPopup.frame = NSRect(x: 0, y: 129, width: 558, height: 38)
        addSubview(presetPopup)

        presetHintPanel.fill = SettingsTheme.subtleFill
        presetHintPanel.border = nil
        presetHintPanel.radius = 11
        presetHintPanel.frame = NSRect(x: 0, y: 178, width: 558, height: 62)
        addSubview(presetHintPanel)

        presetHintLabel.font = .systemFont(ofSize: 11.5)
        presetHintLabel.textColor = SettingsTheme.secondary
        presetHintLabel.frame = NSRect(x: 15, y: 190, width: 528, height: 40)
        addSubview(presetHintLabel)

        customModeControl.segmentCount = VoiceTriggerMode.allCases.count
        customModeControl.font = .systemFont(ofSize: 12, weight: .medium)
        for (index, mode) in VoiceTriggerMode.allCases.enumerated() {
            customModeControl.setLabel(mode.title, forSegment: index)
        }
        customModeControl.target = self
        customModeControl.action = #selector(customModeChanged)
        customModeControl.frame = NSRect(x: 0, y: 176, width: 558, height: 34)
        addSubview(customModeControl)

        customRecorder.allowFnOnly = false
        customRecorder.frame = NSRect(x: 0, y: 218, width: 558, height: 36)
        customRecorder.onShortcutRecorded = { [weak self] usage, modifiers in
            guard let self else { return }
            self.customUsage = usage
            self.customModifiers = modifiers
            self.applyCustomTrigger()
        }
        addSubview(customRecorder)

        let optionsHeader = SettingsTheme.eyebrow(L("麦克风与连说设置"))
        optionsHeader.frame = NSRect(x: 0, y: 266, width: 558, height: 16)
        addSubview(optionsHeader)

        switchMicCheckbox.font = .systemFont(ofSize: 13, weight: .medium)
        switchMicCheckbox.target = self
        switchMicCheckbox.action = #selector(switchMicChanged)
        switchMicCheckbox.frame = NSRect(x: 0, y: 290, width: 558, height: 22)
        addSubview(switchMicCheckbox)

        switchMicDetail.font = .systemFont(ofSize: 11.5)
        switchMicDetail.textColor = SettingsTheme.secondary
        switchMicDetail.frame = NSRect(x: 22, y: 314, width: 536, height: 38)
        addSubview(switchMicDetail)

        fastCheckbox.font = .systemFont(ofSize: 13, weight: .medium)
        fastCheckbox.target = self
        fastCheckbox.action = #selector(fastChanged)
        fastCheckbox.frame = NSRect(x: 0, y: 360, width: 558, height: 22)
        addSubview(fastCheckbox)

        fastDetail.font = .systemFont(ofSize: 11.5)
        fastDetail.textColor = SettingsTheme.secondary
        fastDetail.frame = NSRect(x: 22, y: 384, width: 536, height: 38)
        addSubview(fastDetail)

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
                L("收音正常 · 切到其他软件的输入框再按住即可语音打字") :
                L("正在收音 · 松开语音键结束")
            meterStatusLabel.textColor = SettingsTheme.accentDot
        } else {
            meterStatusLabel.stringValue = L("按住遥控器语音键说话，可在此测试麦克风收音")
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
                presetHintLabel.stringValue = L("需保持 Mac 微信在后台运行并开启「长按 Fn 全局语音输入」。若按住说话不出字，可点右下角「微信语音指南」排查。")
            case .holdRightOption:
                presetHintLabel.stringValue = L("说话期间自动按住键盘右 Option，松手自动松开；请将豆包桌面端、Superwhisper 等软件的语音键也设为右 Option。")
            case .tapOptionSpace:
                presetHintLabel.stringValue = L("按下语音键时点按一次 ⌥Space 开始听写，松手录完尾音后再点按一次 ⌥Space 结束。")
            case .audioOnly:
                presetHintLabel.stringValue = L("只把遥控器声音送入 Chromecast Mic 虚拟麦克风，不发送任何按键（适合会议通话或录音，无需辅助功能权限）。")
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
}
