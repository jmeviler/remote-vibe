import AppKit
import Security
import LocalAuthentication

/// A press matcher shared by practice and lock-screen input. It never emits keyboard events.
struct ComboMatcher {
    enum Result { case progress, matched, failed, coolingDown }
    private(set) var count = 0
    private(set) var failures = 0
    private(set) var cooldownUntil: TimeInterval = 0
    private var lastPress: TimeInterval = 0

    mutating func reset() { count = 0; lastPress = 0 }

    mutating func press(_ code: UInt8, sequence: [UInt8], now: TimeInterval) -> Result {
        guard now >= cooldownUntil else { return .coolingDown }
        guard !sequence.isEmpty else { return .failed }
        if count > 0 && now - lastPress > 3 { reset() }
        lastPress = now
        guard code == sequence[count] else {
            reset(); failures += 1
            if failures >= 5 { cooldownUntil = now + 30; failures = 0 }
            return .failed
        }
        count += 1
        if count == sequence.count { reset(); failures = 0; return .matched }
        return .progress
    }

    mutating func expire(now: TimeInterval) {
        if count > 0 && now - lastPress > 3 { reset() }
    }
}

private enum UnlockKeychain {
    static let service = "local.ben.RemoteVibe.unlock"
    static func query(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: context]
    }
    struct Failure: Error { let status: OSStatus }
    static func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return data
    }
    static func write(_ data: Data, account: String) throws {
        let q = query(account)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Remote Vibe 连招解锁"
            // Classic local login Keychain; no iCloud synchronization or shared access group.
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
    static func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

enum ScreenSession {
    /// nil means the session cannot be established: callers must refuse input.
    static var locked: Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let console = session[kCGSessionOnConsoleKey as String] as? Bool else { return nil }
        if !console { return true }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    static func passwordTarget() -> InputFocus? {
        guard locked == true, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first,
              app.executableURL?.path == "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow" else { return nil }
        // Check the running process, not just a spoofable bundle identifier.
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: app.processIdentifier] as CFDictionary,
                                            [], &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.loginwindow\"" as CFString,
                                             [], &requirement) == errSecSuccess,
              let code, let requirement, SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
              let element = InputFocus.focusedElement(app.processIdentifier),
              InputFocus.attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole,
              InputFocus.attribute(element, kAXFocusedAttribute) as? Bool == true,
              InputFocus.attribute(element, kAXEnabledAttribute) as? Bool != false else { return nil }
        return InputFocus(pid: app.processIdentifier, element: element)
    }

    /// No global events, clipboard, automatic retry, or claimed delivery acknowledgement.
    static func send(_ text: String, to target: InputFocus, submit: Bool) -> Bool {
        guard !text.isEmpty,
              CGEventSource.flagsState(.combinedSessionState).intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]).isEmpty else { return false }
        let source = CGEventSource(stateID: .privateState)
        var events: [CGEvent] = []
        func pair(_ key: CGKeyCode, flags: CGEventFlags = [], text: String? = nil) -> Bool {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
            down.flags = flags; up.flags = flags
            if let text {
                let units = Array(text.utf16)
                units.withUnsafeBufferPointer { buffer in
                    if let address = buffer.baseAddress { down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: address) }
                }
            }
            events += [down, up]
            return true
        }
        // The harmless verification uses the same replacement path as real input, without Return.
        guard pair(0, flags: .maskCommand), pair(51) else { return false }
        for character in text { guard pair(0, text: String(character)) else { return false } }
        if submit && !pair(36) { return false }
        for event in events {
            if event.type == .keyDown {
                guard let current = passwordTarget(), current.pid == target.pid,
                      CFEqual(current.element, target.element) else { return false }
            }
            // Release events contain no text; still pair them if Return has already unlocked the screen.
            event.postToPid(target.pid)
        }
        return true
    }
}

final class ComboUnlock {
    enum Mode { case idle, recording, confirming, practice, verifying, awaitingResult }
    static let buttons = Set(MappedButton.chromecast.map(\.code).filter { $0 != 1 })
    private let mapping: KeyMapping
    private let enabledKey = "comboUnlock.enabled.v1"
    private var sequence: [UInt8] = []
    private var candidate: [UInt8] = []
    private var matcher = ComboMatcher()
    private var lastRecordedAt: TimeInterval = 0
    private var verificationDeadline: TimeInterval = 0
    private var attemptedThisLock = false
    private var observers: [NSObjectProtocol] = []
    private(set) var mode: Mode = .idle
    private(set) var recorded: [UInt8] = []
    private(set) var locked = ScreenSession.locked != false
    private(set) var hasPassword = false
    private(set) var validated = false
    private(set) var enabled = false
    private(set) var status = "先录制连招，再保存本机登录密码。"
    var onChange: (() -> Void)?
    var onLock: (() -> Void)?
    var voiceActive: () -> Bool = { false }
    var configured: Bool { !sequence.isEmpty && hasPassword }
    var sequenceLength: Int { sequence.count }
    var permissionsReady: Bool { mapping.listeningAllowed && AXIsProcessTrusted() }
    var blocksActions: Bool { locked || ScreenSession.locked != false || mode == .recording || mode == .confirming || mode == .practice }
    var canConfirmTest: Bool { mode == .awaitingResult && !locked && ScreenSession.locked == false }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var identity: Data? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return Data(ProcessInfo.processInfo.operatingSystemVersionString.utf8) + hash
    }

    init(mapping: KeyMapping) {
        self.mapping = mapping
        mapping.onCapturedPress = { [weak self] in self?.press($0) }
        // Only reset state here: never re-enter KeyMapping.refresh from its callback.
        mapping.onInputReset = { [weak self] in
            self?.matcher.reset(); self?.recorded.removeAll(); self?.lastRecordedAt = 0
        }
        reload()
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if note.name.rawValue == "com.apple.screenIsLocked" { self.setLocked(true) }
                else { self.refresh() }
            })
        }
    }

    func reload() {
        guard mode == .idle else { return }
        do {
            let data = try UnlockKeychain.read("sequence.v1")
            let stored = Array(data ?? Data())
            sequence = (8...16).contains(stored.count) && stored.allSatisfy(Self.buttons.contains) ? stored : []
            hasPassword = try UnlockKeychain.read("password.v1")?.isEmpty == false
            let verification = try UnlockKeychain.read("validation.v1")
            validated = configured && identity != nil && verification == identity
            enabled = validated && UserDefaults.standard.bool(forKey: enabledKey)
            if !validated { UserDefaults.standard.set(false, forKey: enabledKey) }
            status = enabled ? "连招解锁已开启" : configured ? "已保存 · 可先练习，再手动验证锁屏输入" : "先录制连招，再保存本机登录密码。"
        } catch {
            enabled = false; validated = false; hasPassword = false; sequence.removeAll()
            status = "本机钥匙串不可用，请解锁钥匙串后重新打开设置。"
        }
        onChange?()
    }

    private func invalidateValidation() throws {
        enabled = false; validated = false
        UserDefaults.standard.set(false, forKey: enabledKey)
        try UnlockKeychain.remove("validation.v1")
    }

    func setEnabled(_ value: Bool) {
        guard !value || (validated && configured && mode == .idle) else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: enabledKey)
        status = value ? "连招解锁已开启 · 每次锁屏最多提交一次密码" : "连招解锁已关闭 · 保留已保存的设置"
        onChange?()
    }

    func savePassword(_ password: String) {
        guard !locked, mode == .idle, !password.isEmpty,
              !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            status = "请在安全输入框中输入有效密码。"; onChange?(); return
        }
        do {
            try invalidateValidation()
            try UnlockKeychain.write(Data(password.utf8), account: "password.v1")
            hasPassword = true
            status = "密码已保存到本机钥匙串 · 需要重新验证锁屏输入"
        } catch { status = "钥匙串保存失败，解锁保持关闭。" }
        onChange?()
    }

    func clear() {
        guard !locked else { return }
        cancel()
        do {
            try invalidateValidation()
            try UnlockKeychain.remove("password.v1")
            hasPassword = false
            try UnlockKeychain.remove("sequence.v1")
            sequence.removeAll()
            status = "已删除本 App 的连招与密码"
        } catch { status = "部分钥匙串项目未能删除，请重试；解锁已关闭。" }
        onChange?()
    }

    private func start(_ next: Mode) -> Bool {
        guard mapping.profile == .chromecast else { return false }
        guard !locked, ScreenSession.locked == false, mode == .idle else { return false }
        guard !voiceActive() else { status = "请先结束本次语音。"; onChange?(); return false }
        guard mapping.connected && mapping.listeningAllowed && AXIsProcessTrusted() else {
            status = "请连接遥控器，并允许输入监控和辅助功能。"; onChange?(); return false
        }
        mode = next; matcher = ComboMatcher(); recorded.removeAll(); candidate.removeAll(); lastRecordedAt = 0
        syncCapture()
        guard mapping.captureReady || next == .verifying else {
            mode = .idle; syncCapture(); status = "无法接管按键，请在按键映射页重新保存。"; onChange?(); return false
        }
        return true
    }

    func record() {
        guard start(.recording) else { return }
        status = "按遥控器录入 8–16 次，完成后点击「确认录制」。"; onChange?()
    }

    func finishRecording() {
        guard mode == .recording, (8...16).contains(recorded.count) else { return }
        candidate = recorded; recorded.removeAll(); lastRecordedAt = 0
        mode = .confirming
        status = "请重复刚才的连招，确认后保存。"; onChange?()
    }

    func practice() {
        guard !sequence.isEmpty, start(.practice) else { return }
        status = "练习中 · 只核对连招，不锁屏、不输入密码。"; onChange?()
    }

    func verify() {
        guard configured, start(.verifying) else { return }
        do { try invalidateValidation() }
        catch { mode = .idle; status = "无法更新钥匙串，验证未开始。"; onChange?(); return }
        verificationDeadline = now + 90
        status = "请在 90 秒内手动锁屏并输入连招。仅替换密码框为一个测试字符，不按回车；之后手动解锁。"
        onChange?()
    }

    func confirmVerification(_ success: Bool) {
        guard canConfirmTest else { return }
        do {
            if success, let identity { try UnlockKeychain.write(identity, account: "validation.v1"); validated = true }
            else { try invalidateValidation() }
            status = validated ? "验证已确认 · 可以开启连招解锁" : "未通过验证 · 连招解锁保持关闭"
        } catch { validated = false; status = "无法保存验证结果，解锁保持关闭。" }
        mode = .idle; onChange?()
    }

    func cancel() {
        mode = .idle; recorded.removeAll(); candidate.removeAll(); matcher.reset(); verificationDeadline = 0
        syncCapture(); status = "已取消 · 已保存的设置保留"; onChange?()
    }

    func settingsClosed() {
        if mode == .recording || mode == .confirming || mode == .practice { cancel() }
    }

    func refresh() {
        setLocked(ScreenSession.locked != false)
        let previousCount = matcher.count
        matcher.expire(now: now)
        if mode == .practice && previousCount > 0 && matcher.count == 0 { status = "间隔超过 3 秒，请从头输入。" }
        if mode == .confirming, lastRecordedAt > 0, now - lastRecordedAt > 3 {
            recorded.removeAll(); lastRecordedAt = 0
            status = "间隔超过 3 秒，请从头输入。"
        }
        if mode == .verifying && now > verificationDeadline {
            mode = .idle; status = "验证已超时 · 未确认成功，解锁保持关闭"
        }
        if !mapping.connected || !mapping.listeningAllowed || !AXIsProcessTrusted() {
            matcher.reset()
            if mode == .recording || mode == .confirming || mode == .practice {
                mode = .idle; candidate.removeAll(); recorded.removeAll()
                status = "录入已停止 · 遥控器断开或按键权限不可用"
            }
        }
        syncCapture()
        onChange?()
    }

    private func setLocked(_ value: Bool) {
        guard locked != value else { return }
        locked = value; matcher.reset(); attemptedThisLock = false
        if value {
            mapping.suspendActions(); onLock?()
            if mode == .recording || mode == .confirming || mode == .practice {
                mode = .idle; candidate.removeAll(); recorded.removeAll()
            }
        } else if mode == .verifying {
            mode = .idle; status = "本次验证未发送测试字符 · 解锁保持关闭"
        }
        syncCapture(); onChange?()
    }

    private func syncCapture() {
        let capturing = locked || mode == .recording || mode == .confirming || mode == .practice
        mapping.capture(capturing ? Set(mapping.buttons.map(\.code).filter { $0 != 1 }) : [])
    }

    private func press(_ code: UInt8) {
        guard mapping.profile == .chromecast else { return }
        guard mapping.captureReady else { matcher.reset(); return }
        if mode == .recording || mode == .confirming {
            if !Self.buttons.contains(code) || (lastRecordedAt > 0 && now - lastRecordedAt > 3) { recorded.removeAll() }
            guard Self.buttons.contains(code) else { status = "请每次只按一个键，从头录入。"; onChange?(); return }
            lastRecordedAt = now
            guard recorded.count < 16 else { status = "最多 16 次，请确认录制或重新录入。"; onChange?(); return }
            recorded.append(code)
            if mode == .confirming {
                guard candidate.starts(with: recorded) else {
                    recorded.removeAll(); status = "两次连招不同，请重新确认。"; onChange?(); return
                }
                if recorded == candidate {
                    do {
                        try invalidateValidation()
                        try UnlockKeychain.write(Data(candidate), account: "sequence.v1")
                        sequence = candidate; status = "连招已保存 · 可练习；真实解锁需要重新验证"
                    } catch { status = "连招未能保存到钥匙串，解锁保持关闭。" }
                    mode = .idle; recorded.removeAll(); candidate.removeAll(); syncCapture()
                }
            }
            onChange?(); return
        }
        guard mode == .practice || (locked && (enabled || mode == .verifying) && !attemptedThisLock) else { return }
        if mode == .verifying && now > verificationDeadline { return }
        switch matcher.press(code, sequence: sequence, now: now) {
        case .progress: if !locked { status = "练习中 · 已输入 \(matcher.count) / \(sequence.count) 次" }
        case .failed:
            status = matcher.cooldownUntil > now ? "连续 5 次错误，请等待 30 秒。" : "连招不匹配，请从头输入。"
        case .coolingDown: status = "请等待 \(Int(ceil(matcher.cooldownUntil - now))) 秒后重试。"
        case .matched:
            if mode == .practice { status = "连招正确 · 可以继续练习或结束" }
            else { unlock() }
        }
        onChange?()
    }

    private func unlock() {
        attemptedThisLock = true
        do {
            guard let data = try UnlockKeychain.read("password.v1"), let password = String(data: data, encoding: .utf8),
                  !password.isEmpty, let target = ScreenSession.passwordTarget() else {
                status = "无法确认系统密码框或读取钥匙串，未输入；请手动解锁。"; return
            }
            let testing = mode == .verifying
            guard testing || (enabled && validated), ScreenSession.send(testing ? "x" : password, to: target, submit: !testing) else {
                status = "定向输入未完成，请手动解锁；不会自动重试。"; return
            }
            if testing {
                mode = .awaitingResult
                status = "测试事件已发送。请清除测试字符并手动解锁，再确认是否看到了一个字符。"
            } else { status = "已发送一次解锁请求；若未解锁，请使用键盘。" }
        } catch { status = "锁屏时钥匙串不可读，未输入密码；请手动解锁。" }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; observers.removeAll()
        mapping.onCapturedPress = nil; mapping.onInputReset = nil
    }
}
