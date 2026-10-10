import AppKit

final class ComboUnlockView: NSView {
    override var isFlipped: Bool { true }
    private let controller: ComboUnlock
    private let allowPermissions: () -> Void
    private let summary = NSTextField(labelWithString: "")
    private let progress = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let password = NSSecureTextField()
    private let enabled = NSButton(checkboxWithTitle: "开启连招解锁", target: nil, action: nil)
    private let record = NSButton(title: "录制连招", target: nil, action: nil)
    private let finish = NSButton(title: "确认录制", target: nil, action: nil)
    private let practice = NSButton(title: "练习", target: nil, action: nil)
    private let cancel = NSButton(title: "结束 / 取消", target: nil, action: nil)
    private let save = NSButton(title: "保存 / 更换密码", target: nil, action: nil)
    private let clear = NSButton(title: "清除连招与密码…", target: nil, action: nil)
    private let verify = NSButton(title: "开始手动锁屏验证", target: nil, action: nil)
    private let success = NSButton(title: "看到了测试字符", target: nil, action: nil)
    private let failure = NSButton(title: "没有出现", target: nil, action: nil)
    private let permissions = NSButton(title: "允许按键控制", target: nil, action: nil)

    init(controller: ComboUnlock, allowPermissions: @escaping () -> Void) {
        self.controller = controller
        self.allowPermissions = allowPermissions
        super.init(frame: NSRect(x: 0, y: 0, width: 772, height: 540))
        let title = NSTextField(labelWithString: "用一段连招，解锁你的 Mac")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        place(title, x: 20, y: 14, w: 732, h: 34)
        let explanation = NSTextField(wrappingLabelWithString: "录入 8–16 次按键，再重复确认。语音、电源键不参与；每次间隔不超过 3 秒。")
        place(explanation, x: 20, y: 56, w: 732, h: 38)
        summary.font = .systemFont(ofSize: 13, weight: .medium)
        place(summary, x: 20, y: 97, w: 732, h: 24)
        for (button, x, width, action) in [
            (record, 20.0, 120.0, #selector(recordPressed)), (finish, 150, 120, #selector(finishPressed)),
            (practice, 280, 100, #selector(practicePressed)), (cancel, 390, 140, #selector(cancelPressed))
        ] { setup(button, action: action, x: x, y: 130, w: width) }
        setup(permissions, action: #selector(permissionsPressed), x: 544, y: 130, w: 170)
        progress.textColor = .secondaryLabelColor
        place(progress, x: 20, y: 170, w: 732, h: 52)
        let label = NSTextField(labelWithString: "本机登录密码")
        place(label, x: 20, y: 235, w: 140, h: 24)
        password.placeholderString = "仅保存到本机钥匙串"
        password.setAccessibilityLabel("本机登录密码")
        place(password, x: 160, y: 231, w: 350, h: 28)
        setup(save, action: #selector(savePressed), x: 524, y: 229, w: 190)
        let storage = NSTextField(wrappingLabelWithString: "连招与密码仅存本机钥匙串。关闭功能会保留设置；清除后需重新录制和填写。")
        storage.textColor = .secondaryLabelColor; storage.font = .systemFont(ofSize: 12)
        place(storage, x: 20, y: 269, w: 732, h: 36)
        setup(clear, action: #selector(clearPressed), x: 20, y: 311, w: 180)
        setup(verify, action: #selector(verifyPressed), x: 210, y: 311, w: 195)
        enabled.target = self; enabled.action = #selector(enabledPressed)
        place(enabled, x: 440, y: 314, w: 240, h: 28)
        let limitations = NSTextField(wrappingLabelWithString: "首次默认关闭。验证时由你手动锁屏；App 只试填一个字符，不按回车。\n仅适用于已登录后的锁屏，不支持重启 / FileVault 首次登录。")
        limitations.textColor = .secondaryLabelColor; limitations.font = .systemFont(ofSize: 12)
        place(limitations, x: 20, y: 354, w: 732, h: 44)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        place(status, x: 20, y: 409, w: 732, h: 60)
        setup(success, action: #selector(successPressed), x: 20, y: 481, w: 190)
        setup(failure, action: #selector(failurePressed), x: 224, y: 481, w: 140)
        controller.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func place(_ view: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        view.frame = NSRect(x: x, y: y, width: w, height: h); addSubview(view)
    }
    private func setup(_ button: NSButton, action: Selector, x: CGFloat, y: CGFloat, w: CGFloat) {
        button.target = self; button.action = action; button.bezelStyle = .rounded
        place(button, x: x, y: y, w: w, h: 32)
    }
    func refresh() {
        let idle = controller.mode == .idle && !controller.locked
        summary.stringValue = "连招：\(controller.sequenceLength == 0 ? "未设置" : "已保存 \(controller.sequenceLength) 次")    密码：\(controller.hasPassword ? "已保存" : "未设置")"
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
            progress.stringValue = controller.recorded.map { code in MappedButton.all.first { $0.code == code }?.name ?? "?" }.joined(separator: " → ")
        } else if controller.mode == .confirming {
            progress.stringValue = "再次确认：已输入 \(controller.recorded.count) 次"
        } else { progress.stringValue = "连续 5 次错误暂停 30 秒。练习模式不会锁屏或输入密码。" }
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
        alert.messageText = "清除本机保存的连招与密码？"
        alert.informativeText = "仅删除 Remote Vibe 的钥匙串项目。此操作不可撤销，之后可以重新设置。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清除")
        alert.beginSheetModal(for: window) { [weak self] result in
            if result == .alertSecondButtonReturn { self?.password.stringValue = ""; self?.controller.clear() }
        }
    }
}
