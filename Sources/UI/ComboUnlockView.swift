import AppKit

final class ComboUnlockView: SettingsPage {
    override var isFlipped: Bool { true }
    private let controller: ComboUnlock
    private let allowPermissions: () -> Void
    private let summary = NSTextField(labelWithString: "")
    private let progress = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let password = NSSecureTextField()
    private let enabled = NSButton(checkboxWithTitle: L("开启连招解锁"), target: nil, action: nil)
    private let record = SettingsTheme.button(L("录制连招"))
    private let finish = SettingsTheme.button(L("确认录制"))
    private let practice = SettingsTheme.secondaryButton(L("练习"))
    private let cancel = SettingsTheme.secondaryButton(L("取消"))
    private let save = SettingsTheme.button(L("保存密码"))
    private let clear = SettingsTheme.button(L("清除设置…"), destructive: true)
    private let verify = SettingsTheme.button(L("开始手动锁屏验证"))
    private let success = SettingsTheme.button(L("看到了测试字符"))
    private let failure = SettingsTheme.secondaryButton(L("没有出现"))
    private let permissions = SettingsTheme.button(L("允许按键控制"))

    init(controller: ComboUnlock, allowPermissions: @escaping () -> Void) {
        self.controller = controller
        self.allowPermissions = allowPermissions
        super.init(frame: NSRect(x: 0, y: 0, width: 1024, height: 574))
        let intro = RemoteStage(frame: NSRect(x: 0, y: 0, width: 286, height: 574))
        addSubview(intro)
        let surface = SettingsPanel(frame: NSRect(x: 304, y: 0, width: 720, height: 574))
        addSubview(surface)
        let eyebrow = SettingsTheme.eyebrow(L("锁屏快捷解锁"), light: true)
        place(eyebrow, x: 24, y: 24, w: 238, h: 17)
        let heading = SettingsTheme.label(L("按预设连招，\n解锁这台 Mac"), size: 26, weight: .semibold, color: SettingsTheme.color(0xF1F5E9))
        heading.maximumNumberOfLines = 2
        place(heading, x: 23, y: 58, w: 240, h: 80)
        let subtitle = NSTextField(wrappingLabelWithString: L("锁屏时在遥控器上按对顺序，自动代填密码并解锁。"))
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = SettingsTheme.color(0xAFBFAB)
        place(subtitle, x: 24, y: 148, w: 238, h: 38)
        for (index, pair) in [
            (L("录入连招"), L("除语音和电源键外，按 8–16 下并重复一遍。")),
            (L("保存密码"), L("加密存入本机钥匙串，不写入普通配置文件。")),
            (L("锁屏验证"), L("锁屏试填 1 个测试字符，确认可用后再开启。"))
        ].enumerated() {
            let y = CGFloat(224 + index * 92)
            place(SettingsTheme.eyebrow("0\(index + 1)", light: true), x: 25, y: y, w: 30, h: 18)
            place(SettingsTheme.label(pair.0, size: 15, weight: .medium, color: SettingsTheme.paper), x: 63, y: y - 2, w: 180, h: 23)
            let description = NSTextField(wrappingLabelWithString: pair.1)
            description.font = .systemFont(ofSize: 11); description.textColor = SettingsTheme.color(0xBBC8B7)
            place(description, x: 63, y: y + 27, w: 198, h: 38)
        }
        place(SettingsTheme.eyebrow(L("仅支持登录后的锁屏 · 开机仍需手输"), light: true), x: 24, y: 534, w: 238, h: 18)
        let title = SettingsTheme.label(L("连招解锁"), size: 26, weight: .semibold, color: SettingsTheme.ink)
        place(title, x: 332, y: 25, w: 660, h: 37)
        summary.font = .systemFont(ofSize: 12, weight: .medium); summary.textColor = SettingsTheme.secondary
        place(summary, x: 332, y: 74, w: 660, h: 23)
        let explanation = NSTextField(wrappingLabelWithString: L("除语音键和电源键外均可参与；相邻两下间隔不超过 3 秒，长按只算一下。"))
        explanation.font = .systemFont(ofSize: 12); explanation.textColor = SettingsTheme.secondary
        place(explanation, x: 332, y: 110, w: 660, h: 34)
        setup(record, action: #selector(recordPressed), x: 330, y: 156, w: 128)
        setup(finish, action: #selector(finishPressed), x: 464, y: 156, w: 119)
        setup(practice, action: #selector(practicePressed), x: 589, y: 156, w: 83)
        setup(cancel, action: #selector(cancelPressed), x: 678, y: 156, w: 130)
        setup(permissions, action: #selector(permissionsPressed), x: 814, y: 156, w: 184)
        progress.textColor = SettingsTheme.secondary; progress.font = .systemFont(ofSize: 12)
        place(progress, x: 332, y: 205, w: 660, h: 44)
        place(SettingsTheme.eyebrow(L("本机登录密码")), x: 332, y: 264, w: 200, h: 18)
        password.placeholderString = L("输入这台 Mac 的登录密码")
        password.setAccessibilityLabel(L("本机登录密码"))
        SettingsTheme.style(password)
        place(password, x: 332, y: 292, w: 440, h: 30)
        setup(save, action: #selector(savePressed), x: 790, y: 287, w: 209)
        let storage = NSTextField(wrappingLabelWithString: L("连招与密码仅加密保存在本机钥匙串中；关闭下方开关不会清空已存设置。"))
        storage.textColor = SettingsTheme.secondary; storage.font = .systemFont(ofSize: 11)
        place(storage, x: 332, y: 335, w: 660, h: 30)
        setup(verify, action: #selector(verifyPressed), x: 330, y: 386, w: 206)
        enabled.target = self; enabled.action = #selector(enabledPressed)
        enabled.font = .systemFont(ofSize: 12)
        place(enabled, x: 553, y: 391, w: 232, h: 28)
        setup(clear, action: #selector(clearPressed), x: 794, y: 386, w: 204)
        let limitations = NSTextField(wrappingLabelWithString: L("点「开始手动锁屏验证」后在 90 秒内锁屏并按连招，系统只会试填 1 个字符（不按回车）；确认看到字符后才可开启。重启或开机首次登录不支持代填。"))
        limitations.textColor = SettingsTheme.secondary; limitations.font = .systemFont(ofSize: 11)
        place(limitations, x: 332, y: 438, w: 660, h: 44)
        status.font = .systemFont(ofSize: 12, weight: .medium); status.textColor = SettingsTheme.ink
        place(status, x: 332, y: 490, w: 660, h: 37)
        setup(success, action: #selector(successPressed), x: 330, y: 531, w: 195)
        setup(failure, action: #selector(failurePressed), x: 535, y: 531, w: 145)

        controller.onChange = { [weak self] in self?.refresh() }
        updateContents()
        captureHorizontalLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func place(_ view: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        view.frame = NSRect(x: x, y: y, width: w, height: h); addSubview(view)
    }
    private func setup(_ button: NSButton, action: Selector, x: CGFloat, y: CGFloat, w: CGFloat) {
        button.target = self; button.action = action
        place(button, x: x, y: y, w: w, h: 38)
    }
    func refresh() {
        guard window?.isVisible == true, window?.isMiniaturized == false, !NSApplication.shared.isHidden, !isHidden else { return }
        updateContents()
    }

    private func updateContents() {
        let idle = controller.mode == .idle && !controller.locked
        summary.stringValue = L("连招：%@  ·  密码：%@", controller.sequenceLength == 0 ? L("未设置") : L("已保存 %@ 下", String(controller.sequenceLength)), controller.hasPassword ? L("已保存") : L("未设置"))
        save.title = controller.hasPassword ? L("更换密码") : L("保存密码")
        record.isEnabled = idle; practice.isEnabled = idle && controller.sequenceLength > 0
        finish.isEnabled = controller.mode == .recording && (8...16).contains(controller.recorded.count)
        cancel.isEnabled = controller.mode != .idle
        save.isEnabled = idle; password.isEnabled = idle; clear.isEnabled = idle
        verify.isEnabled = idle && controller.configured
        enabled.isEnabled = idle && controller.validated
        enabled.state = controller.enabled ? .on : .off
        success.isHidden = !controller.canConfirmTest; failure.isHidden = !controller.canConfirmTest
        permissions.isHidden = controller.permissionsReady
        if controller.mode == .recording {
            progress.stringValue = controller.recorded.map { code in MappedButton.chromecast.first { $0.code == code }?.name ?? "?" }.joined(separator: " → ")
        } else if controller.mode == .confirming {
            progress.stringValue = L("再次确认：已输入 %@ 下", String(controller.recorded.count))
        } else { progress.stringValue = L("可点「练习」在不锁屏时试按；锁屏状态下连续按错 5 次将暂停 30 秒。") }
        status.stringValue = controller.status
    }
    func leave() { password.stringValue = ""; controller.settingsClosed() }

    @objc private func recordPressed() { controller.record() }
    @objc private func finishPressed() { controller.finishRecording() }
    @objc private func practicePressed() { controller.practice() }
    @objc private func cancelPressed() { controller.cancel() }
    @objc private func savePressed() {
        let value = password.stringValue
        password.stringValue = ""
        controller.savePassword(value)
    }
    @objc private func verifyPressed() { controller.verify() }
    @objc private func enabledPressed() { controller.setEnabled(enabled.state == .on) }
    @objc private func successPressed() { controller.confirmVerification(true) }
    @objc private func failurePressed() { controller.confirmVerification(false) }
    @objc private func permissionsPressed() { allowPermissions() }
    @objc private func clearPressed() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L("清除本机保存的连招与密码？")
        alert.informativeText = L("仅删除 Remote Vibe 的钥匙串项目。此操作不可撤销，之后可以重新设置。")
        alert.addButton(withTitle: L("取消")); alert.addButton(withTitle: L("清除"))
        alert.beginSheetModal(for: window) { [weak self] result in
            if result == .alertSecondButtonReturn { self?.password.stringValue = ""; self?.controller.clear() }
        }
    }
}
