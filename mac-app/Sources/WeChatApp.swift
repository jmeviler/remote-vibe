import AppKit
import ApplicationServices
import CoreBluetooth
import CoreAudio

final class WeChatApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let remote = Remote()
    private let mic = VirtualMicrophone()
    private let fn = FnKey()
    private let mapping = KeyMapping()
    private lazy var unlock = ComboUnlock(mapping: mapping)
    private var mappingView: KeyMappingView!
    private var unlockView: ComboUnlockView!
    private var pages: NSSegmentedControl!
    private var item: NSStatusItem!
    private var window: NSWindow!
    private let connection = NSTextField(wrappingLabelWithString: "正在连接遥控器…")
    private let audioLabel = NSTextField(wrappingLabelWithString: "正在检查麦克风…")
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "准备就绪后，在当前输入框里按住语音键说话。")
    private var sessionID = UUID()
    private var active = false
    private var released = false
    private var drainStarted = false
    private var drainTimer: Timer?
    private var poll: Timer?
    private var endedAt = Date()
    private var completedSessions = 0
    private var fnDowns = 0
    private var fnUps = 0
    private var allowPrompted = false
    private var signalSources: [DispatchSourceSignal] = []
    private var lastStatus: Data?
    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteVibe/status.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        buildUI()
        mapping.canPerform = { [weak self] in
            guard let self else { return false }
            return !self.active && !self.unlock.blocksActions
        }
        unlock.voiceActive = { [weak self] in self?.active == true }
        unlock.onLock = { [weak self] in
            guard let self else { return }
            self.unlockView.leave()
            if self.active { self.remote.close(); self.abort() }
        }
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        remote.onStatus = { [weak self] text in self?.connection.stringValue = text; self?.save() }
        remote.onBegin = { [weak self] in self?.begin() }
        remote.onSamples = { [weak self] values, rate in self?.mic.feed(values, rate: rate) }
        remote.onEnd = { [weak self] normal in self?.end(normal) }
        remote.start()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        poll?.tolerance = 0.2
        refresh()
        show()
    }

    private func begin() {
        guard !unlock.blocksActions else { remote.close(); message.stringValue = "锁屏或连招录入期间暂停语音"; return }
        if active { abort(); remote.close(); message.stringValue = "请等上一段结束后再说话"; return }
        guard AXIsProcessTrusted() else { remote.close(); message.stringValue = "请先允许模拟 Fn 按键"; return }
        guard mic.begin() else { remote.close(); message.stringValue = "请先完成麦克风组件安装"; return }
        sessionID = UUID()
        let id = sessionID
        active = true; released = false; drainStarted = false
        mapping.cancelPendingActions()
        item.button?.title = "● 语音"
        message.stringValue = "正在准备微信语音输入…"
        // Change the input before Fn starts WeChat's capture session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.sessionID == id, self.active, !self.released else { return }
            guard self.fn.down() else { self.abort(); self.remote.close(); self.message.stringValue = "Fn 已被按住或没有权限，请重试"; return }
            self.fnDowns += 1
            self.message.stringValue = "正在说话 · 松开遥控器语音键结束"
            // Retain the first syllables while WeChat opens its microphone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, self.sessionID == id, self.active else { return }
                self.drainStarted = true
                self.mic.startDraining()
            }
        }
        save()
    }

    private func end(_ normal: Bool) {
        guard active else { return }
        guard normal, fn.held else { abort(); return }
        released = true
        endedAt = Date()
        message.stringValue = "正在结束，文字由微信生成…"
        drainTimer?.invalidate()
        let id = sessionID
        drainTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, self.sessionID == id, self.active else { timer.invalidate(); return }
            if (self.drainStarted && self.mic.pendingFrames == 0) || Date().timeIntervalSince(self.endedAt) > 4 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, self.sessionID == id else { return }
                    if self.fn.held { self.fn.up(); self.fnUps += 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.mic.end()
                        self.active = false
                        self.completedSessions += 1
                        self.item.button?.title = "遥控语音"
                        self.message.stringValue = "本次语音已结束；可以继续按住语音键说话。"
                        self.save()
                    }
                }
            }
        }
        save()
    }

    private func abort() {
        sessionID = UUID()
        drainTimer?.invalidate()
        if fn.held { fn.up(); fnUps += 1 }
        mic.end()
        active = false; released = false
        item.button?.title = "遥控语音"
        save()
    }

    private func refresh() {
        unlock.refresh()
        mapping.refresh()
        mappingView.refreshStatus()
        let audioReady = mic.connect()
        audioLabel.stringValue = audioReady ? "麦克风：Chromecast Mic 已就绪" : "麦克风：等待安装组件"
        permission.stringValue = AXIsProcessTrusted() ? "Fn 按键权限：已允许" : "Fn 按键权限：需要在系统设置中允许"
        if CBCentralManager.authorization == .allowedAlways && !allowPrompted && !AXIsProcessTrusted() {
            allowPrompted = true
            // This only registers the app in the system permission list.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        save()
    }

    private func buildUI() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "Remote Vibe")
        let quitItem = appMenu.addItem(withTitle: "退出 Remote Vibe", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        mainMenu.addItem(withTitle: "Remote Vibe", action: nil, keyEquivalent: "").submenu = appMenu
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"),
                                    ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                    ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = editMenu
        NSApplication.shared.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "遥控语音"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开遥控语音", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "立即结束本次语音", action: #selector(stopVoice), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 771), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Remote Vibe · 遥控器设置"
        window.isReleasedWhenClosed = false
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24)
        ])
        let title = NSTextField(labelWithString: "你的遥控器，你来定义")
        title.font = .boldSystemFont(ofSize: 24)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(labelWithString: "点击一个按键，选择功能。语音键始终按住说话。"))
        pages = NSSegmentedControl(labels: ["按键映射", "连招解锁"], trackingMode: .selectOne, target: self, action: #selector(changePage))
        pages.selectedSegment = 0
        stack.addArrangedSubview(pages)
        let content = NSView()
        content.widthAnchor.constraint(equalToConstant: 772).isActive = true
        content.heightAnchor.constraint(equalToConstant: 540).isActive = true
        mappingView = KeyMappingView(mapping: mapping)
        mappingView.frame = NSRect(x: 0, y: 0, width: 772, height: 540)
        unlockView = ComboUnlockView(controller: unlock, allowPermissions: { [weak self] in self?.mappingView.allowListener() })
        unlockView.isHidden = true
        content.addSubview(mappingView); content.addSubview(unlockView)
        stack.addArrangedSubview(content)
        let deviceRow = NSStackView(views: [connection, audioLabel])
        deviceRow.spacing = 20
        stack.addArrangedSubview(deviceRow)
        let permissionsButton = NSButton(title: "权限设置", target: self, action: #selector(allowFn))
        let permissionRow = NSStackView(views: [permission, permissionsButton])
        permissionRow.spacing = 12
        stack.addArrangedSubview(permissionRow)
        message.font = .systemFont(ofSize: 12, weight: .medium)
        message.widthAnchor.constraint(equalToConstant: 760).isActive = true
        stack.addArrangedSubview(message)
    }

    @objc private func show() { unlock.reload(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    @objc private func changePage() {
        let combo = pages.selectedSegment == 1
        if !combo { unlockView.leave() } else { unlock.reload() }
        mappingView.isHidden = combo; unlockView.isHidden = !combo
        window.makeFirstResponder(nil)
    }
    func windowWillClose(_ notification: Notification) { unlockView.leave() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    @objc private func allowFn() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func stopVoice() { remote.close(); abort() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func save() {
        var status: [String: Any] = [
            "mode": "wechat-hold-fn",
            "bluetoothAuthorization": CBCentralManager.authorization.rawValue,
            "accessibility": AXIsProcessTrusted(), "connected": remote.ready,
            "microphoneReady": mic.available, "recording": remote.streaming,
            "sessionActive": active, "fnHeld": fn.held, "fnDowns": fnDowns, "fnUps": fnUps,
            "audioFrames": remote.frameCount, "fedSamples": mic.fedFrames, "renderedSamples": mic.renderedFrames,
            "completedSessions": completedSessions, "status": message.stringValue,
            "keyMappingStatus": mapping.status, "keyMappingConnected": mapping.connected,
            "inputMonitoring": mapping.listeningAllowed,
            "shortcutListener": mapping.listening,
            "defaultInput": AudioDevices.string(AudioDevices.defaultInput(), kAudioObjectPropertyName) ?? "none"
        ]
        guard let snapshot = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]), snapshot != lastStatus else { return }
        status["updated"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            do { try data.write(to: statusURL, options: .atomic); lastStatus = snapshot } catch { /* Diagnostics must not interrupt input. */ }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        poll?.invalidate(); unlock.stop(); mapping.stop(); remote.shutdown(); abort(); mic.stop()
    }
}

@main
enum Main {
    static func main() {
        // Reject a second instance before it can acquire devices or run cleanup.
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.ben.RemoteVibe")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            if let url = existing.bundleURL { NSWorkspace.shared.open(url) }
            else { existing.activate(options: []) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WeChatApp()
        app.delegate = delegate
        app.run()
    }
}
