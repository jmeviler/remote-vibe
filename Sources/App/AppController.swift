import AppKit
import ApplicationServices
import CoreBluetooth
import CoreAudio

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let remote = RemoteController()
    private let xiaomiVoiceKey = XiaomiVoiceKeyOverride()
    private let mic = VirtualMicrophone()
    private let fn = FnKey()
    private let mapping = KeyMapping()
    private lazy var unlock = ComboUnlock(mapping: mapping)
    private var mappingView: KeyMappingView!
    private var unlockView: ComboUnlockView!
    private var pages: NSSegmentedControl!
    private var remotePicker: NSPopUpButton!
    private var discoveryButton: NSButton!
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
    private var workspaceObservers: [NSObjectProtocol] = []
    private var stopping = false
    private var lastStatus: Data?
    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteVibe/status.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        buildUI()
        updateRemoteUI()
        mapping.onDeviceChange = { [weak self] in self?.refresh() }
        mapping.onFnChange = { [weak self] in self?.writeStatus() }
        mapping.canPerform = { [weak self] in
            guard let self else { return false }
            return !self.active && !self.remote.voiceBusy && !self.unlock.blocksActions
        }
        mapping.onVoicePress = { [weak self] in
            guard let self, AXIsProcessTrusted(), !self.mapping.fnHeld, self.mic.connect() else { return false }
            return self.remote.beginMappedVoice()
        }
        mapping.onVoiceRelease = { [weak self] normal in self?.remote.endMappedVoice(normal: normal) }
        unlock.voiceActive = { [weak self] in self?.active == true }
        unlock.onLock = { [weak self] in
            guard let self else { return }
            self.unlockView.leave()
            self.mapping.suspendActions()
            if self.active || self.remote.voiceBusy { self.remote.cancelVoice(); self.abort() }
        }
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        remote.onStatus = { [weak self] text in
            guard let self else { return }
            self.connection.stringValue = text
            self.updateDiscoveryButton()
            self.mapping.refresh()
            self.xiaomiVoiceKey.refresh(enabled: self.remote.xiaomiReady)
            self.writeStatus()
        }
        remote.canBegin = { [weak self] profile in
            guard let self, !self.active, !self.mapping.fnHeld, !self.unlock.blocksActions else { return false }
            if profile == .xiaomiRC003 {
                self.xiaomiVoiceKey.refresh(enabled: self.remote.xiaomiReady)
                guard self.xiaomiVoiceKey.ready else { self.message.stringValue = self.xiaomiVoiceKey.status; return false }
            }
            return true
        }
        remote.onBegin = { [weak self] in self?.begin() }
        remote.onSamples = { [weak self] values, rate in self?.mic.feed(values, rate: rate) }
        remote.onEnd = { [weak self] normal in self?.end(normal) }
        remote.start()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.mapping.suspendActions()
                self?.refresh()
            })
        }
        refresh()
        show()
    }

    private func begin() {
        guard !unlock.blocksActions else { remote.cancelVoice(); message.stringValue = "锁屏或连招录入期间暂停语音"; return }
        if active { remote.cancelVoice(); abort(); message.stringValue = "请等上一段结束后再说话"; return }
        guard AXIsProcessTrusted() else { remote.cancelVoice(); message.stringValue = "请先允许模拟 Fn 按键"; return }
        guard mic.begin() else { remote.cancelVoice(); message.stringValue = "请先完成麦克风组件安装"; return }
        sessionID = UUID()
        let id = sessionID
        active = true; released = false; drainStarted = false
        scheduleMaintenance()
        remotePicker.isEnabled = false
        updateDiscoveryButton()
        mapping.cancelPendingActions()
        item.button?.title = "● 语音"
        message.stringValue = "正在准备微信语音输入…"
        // Change the input before Fn starts WeChat's capture session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.sessionID == id, self.active, !self.released else { return }
            guard self.fn.down() else { self.remote.cancelVoice(); self.abort(); self.message.stringValue = "Fn 已被按住或没有权限，请重试"; return }
            self.fnDowns += 1
            self.message.stringValue = "正在说话 · 松开当前按键结束"
            // Retain the first syllables while WeChat opens its microphone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, self.sessionID == id, self.active else { return }
                self.drainStarted = true
                self.mic.startDraining()
            }
        }
        writeStatus()
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
                        self.scheduleMaintenance()
                        self.remotePicker.isEnabled = true
                        self.updateDiscoveryButton()
                        self.completedSessions += 1
                        self.item.button?.title = "遥控语音"
                        self.message.stringValue = "本次语音已结束；可以继续按住语音键说话。"
                        self.writeStatus()
                    }
                }
            }
        }
        writeStatus()
    }

    private func abort() {
        sessionID = UUID()
        drainTimer?.invalidate()
        if fn.held { fn.up(); fnUps += 1 }
        mic.end()
        active = false; released = false
        scheduleMaintenance()
        remotePicker.isEnabled = true
        updateDiscoveryButton()
        item.button?.title = "遥控语音"
        writeStatus()
    }

    private func refresh() {
        guard !stopping else { return }
        mapping.refresh()
        unlock.refresh()
        if settingsVisible {
            if !mappingView.isHidden { mappingView.refreshStatus() }
            if !unlockView.isHidden { unlockView.refresh() }
        }
        xiaomiVoiceKey.refresh(enabled: remote.xiaomiReady)
        let audioReady = mic.connect()
        if settingsVisible {
            audioLabel.stringValue = audioReady ? "麦克风：Chromecast Mic 已就绪" : "麦克风：等待安装组件"
            permission.stringValue = AXIsProcessTrusted() ? "Fn 按键权限：已允许" : "Fn 按键权限：需要在系统设置中允许"
        }
        if CBCentralManager.authorization == .allowedAlways && !allowPrompted && !AXIsProcessTrusted() {
            allowPrompted = true
            // This only registers the app in the system permission list.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        scheduleMaintenance()
        writeStatus()
    }

    private var settingsVisible: Bool { window?.isVisible == true && window?.isMiniaturized == false && !NSApplication.shared.isHidden }

    private func scheduleMaintenance() {
        guard !stopping else { return }
        // Voice and key callbacks run immediately; this timer only audits state and updates diagnostics.
        let interval: TimeInterval = active || settingsVisible || unlock.mode != .idle ? 1 : 10
        guard poll?.timeInterval != interval else { return }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        poll?.tolerance = interval == 1 ? 0.2 : 2
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
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1080, visible.width - 64), height: min(812, visible.height - 76)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Remote Vibe · 遥控器设置"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsTheme.canvas
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 900, height: 640)
        window.isReleasedWhenClosed = false
        window.center()
        remotePicker = NSPopUpButton()
        remotePicker.addItems(withTitles: RemoteProfile.allCases.map { $0.title })
        remotePicker.selectItem(at: RemoteProfile.allCases.firstIndex(of: remote.profile) ?? 0)
        remotePicker.target = self; remotePicker.action = #selector(changeRemote)
        discoveryButton = SettingsTheme.button("扫描遥控器", target: self, action: #selector(toggleDiscovery))
        pages = NSSegmentedControl(labels: ["按键映射", "连招解锁"], trackingMode: .selectOne, target: self, action: #selector(changePage))
        pages.selectedSegment = 0
        mappingView = KeyMappingView(mapping: mapping)
        unlockView = ComboUnlockView(controller: unlock, allowPermissions: { [weak self] in self?.mappingView.allowListener() })
        unlockView.isHidden = true
        let permissionsButton = SettingsTheme.button("权限设置", target: self, action: #selector(allowFn))
        let shell = SettingsView(mapping: mappingView, unlock: unlockView, remote: remotePicker, discovery: discoveryButton,
            pages: pages, connection: connection, audio: audioLabel, permission: permission,
            permissionsButton: permissionsButton, message: message)
        let scroll = SettingsScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.backgroundColor = SettingsTheme.canvas
        scroll.documentView = shell
        window.contentView = scroll
    }

    @objc private func show() {
        unlock.reload(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
        refresh()
    }
    @objc private func changeRemote() {
        guard !active else { return }
        unlockView.leave()
        xiaomiVoiceKey.stop()
        remote.select(RemoteProfile.allCases[remotePicker.indexOfSelectedItem])
        updateDiscoveryButton()
        updateRemoteUI()
        connection.stringValue = "\(remote.sourceName)：正在连接…"
        message.stringValue = "已选择\(remote.sourceName)，连接后按住语音键说话。"
        writeStatus()
    }
    @objc private func toggleDiscovery() {
        guard !active else { return }
        remote.toggleDiscovery()
    }
    private func updateDiscoveryButton() {
        discoveryButton.isEnabled = !active && !remote.ready
        discoveryButton.title = remote.ready ? "已连接" : remote.scanning ? "停止扫描" : remote.connecting ? "取消等待" : "扫描遥控器"
    }
    private func updateRemoteUI() {
        let google = remote.profile == .chromecast
        mapping.selectProfile(remote.profile)
        mappingView.switchProfile()
        mapping.refresh()
        pages.isHidden = !google
        mappingView.isHidden = google && pages.selectedSegment == 1
        unlockView.isHidden = !google || pages.selectedSegment == 0
    }
    @objc private func changePage() {
        let combo = pages.selectedSegment == 1
        if !combo { unlockView.leave() } else { unlock.reload() }
        mappingView.isHidden = combo; unlockView.isHidden = !combo
        if combo { unlockView.refresh() }
        window.makeFirstResponder(nil)
    }
    func windowWillClose(_ notification: Notification) {
        unlockView.leave()
        DispatchQueue.main.async { [weak self] in self?.scheduleMaintenance() }
    }
    func windowDidMiniaturize(_ notification: Notification) { scheduleMaintenance() }
    func windowDidDeminiaturize(_ notification: Notification) { refresh() }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func applicationDidHide(_ notification: Notification) { scheduleMaintenance(); writeStatus() }
    func applicationDidUnhide(_ notification: Notification) { refresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    @objc private func allowFn() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func stopVoice() { mapping.suspendActions(); remote.cancelVoice(); abort() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func writeStatus() {
        var status: [String: Any] = [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "mode": "wechat-hold-fn",
            "bluetoothAuthorization": CBCentralManager.authorization.rawValue,
            "accessibility": AXIsProcessTrusted(), "connected": remote.ready,
            "microphoneReady": mic.available, "recording": remote.streaming,
            "sessionActive": active, "fnHeld": fn.held || mapping.fnHeld, "mappedFnHeld": mapping.fnHeld, "fnDowns": fnDowns, "fnUps": fnUps,
            "audioFrames": remote.frameCount, "fedSamples": mic.fedFrames, "renderedSamples": mic.renderedFrames,
            "completedSessions": completedSessions, "status": message.stringValue,
            "voiceSource": remote.sourceName, "voiceProfile": remote.profile.rawValue,
            "voiceProtocol": remote.protocolSummary, "connectionStatus": connection.stringValue,
            "bluetoothScanning": remote.scanning, "bluetoothConnecting": remote.connecting,
            "bluetoothScanStarts": remote.scanStarts,
            "mappedVoiceHeld": mapping.mappedVoiceHeld, "mappedVoiceActive": remote.mappedVoiceActive, "voiceBusy": remote.voiceBusy,
            "xiaomiVoiceKeyReady": xiaomiVoiceKey.ready, "xiaomiVoiceKeyStatus": xiaomiVoiceKey.status,
            "keyMappingStatus": mapping.status, "keyMappingConnected": mapping.connected,
            "inputMonitoring": mapping.listeningAllowed,
            "shortcutListener": mapping.listening,
            "keyActionChoices": ActionCatalog.presets.count,
            "maintenanceInterval": poll?.timeInterval ?? 0,
            "defaultInput": AudioDevices.string(AudioDevices.defaultInput(), kAudioObjectPropertyName) ?? "none"
        ]
        guard let snapshot = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]), snapshot != lastStatus else { return }
        status["updated"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            do { try data.write(to: statusURL, options: .atomic); lastStatus = snapshot } catch { /* Diagnostics must not interrupt input. */ }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopping = true
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        mapping.onDeviceChange = nil
        mapping.onFnChange = nil
        poll?.invalidate(); unlock.stop(); mapping.stop(); remote.shutdown(); xiaomiVoiceKey.stop(); abort(); mic.stop()
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
        let delegate = AppController()
        app.delegate = delegate
        app.run()
    }
}
