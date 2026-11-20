import AppKit
import ApplicationServices
import CoreBluetooth
import CoreAudio

private final class FlippedAccessoryView: NSView {
    override var isFlipped: Bool { true }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let remote = RemoteController()
    private let xiaomiVoiceKey = XiaomiVoiceKeyOverride()
    private let mic = VirtualMicrophone()
    private let voiceSettings = VoiceInputSettings()
    private let voiceTrigger = VoiceTriggerController()
    private let launchAtLogin = LaunchAtLoginController()
    private let mapping = KeyMapping()
    private lazy var unlock = ComboUnlock(mapping: mapping)
    private var mappingView: KeyMappingView!
    private var unlockView: ComboUnlockView!
    private var pages: NSSegmentedControl!
    private var remotePicker: NSPopUpButton!
    private var discoveryButton: NSButton!
    private var item: NSStatusItem!
    private var window: NSWindow!
    private let connection = NSTextField(wrappingLabelWithString: L("正在连接遥控器…"))
    private let audioLabel = NSTextField(wrappingLabelWithString: L("正在检查麦克风…"))
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let readiness = NSTextField(labelWithString: L("正在检查使用条件…"))
    private let permissionsButton = SettingsTheme.button(L("权限设置"))
    private let message = NSTextField(wrappingLabelWithString: L("准备就绪后，在当前输入框里按住语音键说话。"))
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版")
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    private let updateStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: L("登录时自动打开"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var voicePresetItems: [(VoiceTrigger, NSMenuItem)] = []
    private var customVoiceTriggerItem: NSMenuItem!
    private var switchDefaultMicItem: NSMenuItem!
    private var fastTurnaroundItem: NSMenuItem!
    private var updateCheck: URLSessionDataTask?
    private var sessionID = UUID()
    private var active = false
    private var released = false
    private var drainStarted = false
    private let voiceSchedule = VoiceSessionSchedule()
    private var voiceTiming = VoiceSessionTiming()
    private var drainTimedOut = false
    private var poll: Timer?
    private var completedSessions = 0
    private var fnDowns = 0
    private var fnUps = 0
    private var allowPrompted = false
    private var signalSources: [DispatchSourceSignal] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var stopping = false
    private let statusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteVibe/status.json")
    private lazy var statusWriter = StatusWriter(url: statusURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        buildUI()
        updateRemoteUI()
        mic.onUnavailable = { [weak self] in
            guard let self, !self.stopping else { return }
            self.remote.cancelVoice(); self.abort()
            self.message.stringValue = L("音频设备已变化，本次语音已取消；请重新按住语音键")
            self.writeStatus()
        }
        mic.onAvailabilityChange = { [weak self] in self?.refreshReadiness(); self?.writeStatus() }
        mapping.onDeviceChange = { [weak self] in self?.refresh() }
        mapping.onMouseModeChange = { [weak self] in
            guard let self else { return }
            self.mappingView.refreshStatus()
            self.updateStatusItem()
            self.writeStatus()
        }
        mapping.onFnChange = { [weak self] in self?.refreshReadiness(); self?.writeStatus() }
        mapping.canPerform = { [weak self] in
            guard let self else { return false }
            return !self.active && !self.remote.voiceBusy && !self.unlock.blocksActions
        }
        mapping.onVoicePress = { [weak self] in
            guard let self else { return false }
            let needsAX = self.voiceSettings.trigger.requiresAccessibility
            guard (!needsAX || AXIsProcessTrusted()), !self.mapping.fnHeld, self.mic.connect() else { return false }
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
            self.connection.toolTip = text
            self.updateDiscoveryButton()
            self.mapping.refresh()
            self.xiaomiVoiceKey.refresh(enabled: self.remote.xiaomiReady)
            self.refreshReadiness()
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
        remote.onSamples = { [weak self] values, rate in
            guard let self else { return }
            if self.active && !values.isEmpty { self.voiceTiming.mark("firstSamples", at: ProcessInfo.processInfo.systemUptime) }
            self.mic.feed(values, rate: rate)
        }
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
        guard !unlock.blocksActions else { remote.cancelVoice(); message.stringValue = L("锁屏或连招录入期间暂停语音"); return }
        if active { remote.cancelVoice(); abort(); message.stringValue = L("请等上一段结束后再说话"); return }
        let trigger = voiceSettings.trigger
        let switchInput = voiceSettings.switchDefaultInput
        let timing = voiceSettings.timing
        if trigger.requiresAccessibility && !AXIsProcessTrusted() {
            remote.cancelVoice()
            message.stringValue = trigger == .holdFn ? L("请先允许模拟 Fn 按键") : L("请先允许辅助功能以发送语音快捷键")
            return
        }
        voiceTiming.begin(at: ProcessInfo.processInfo.systemUptime)
        drainTimedOut = false
        guard mic.begin(switchDefaultInput: switchInput) else {
            voiceTiming.finish(at: ProcessInfo.processInfo.systemUptime, cancelled: true)
            remote.cancelVoice(); message.stringValue = L("语音组件暂不可用，请检查安装或稍后重试")
            refreshReadiness(); writeStatus(); return
        }
        voiceTiming.mark("microphoneStarted", at: ProcessInfo.processInfo.systemUptime)
        voiceSchedule.cancel()
        sessionID = UUID()
        let id = sessionID
        active = true; released = false; drainStarted = false
        scheduleMaintenance()
        remotePicker.isEnabled = false
        updateDiscoveryButton()
        mapping.cancelPendingActions()
        updateStatusItem()
        message.stringValue = trigger == .holdFn ? L("正在准备微信语音输入…") : L("正在准备语音输入…")
        let startTrigger: () -> Void = { [weak self] in
            guard let self, self.sessionID == id, self.active, !self.released else { return }
            guard self.voiceTrigger.activate(trigger) else {
                self.remote.cancelVoice(); self.abort()
                self.message.stringValue = trigger == .holdFn ? L("Fn 已被按住或没有权限，请重试") : L("语音触发键已被占用或缺少权限，请重试")
                return
            }
            if trigger != .none { self.fnDowns += 1 }
            self.voiceTiming.mark("fnDown", at: ProcessInfo.processInfo.systemUptime)
            self.message.stringValue = L("正在说话 · 松开当前按键结束")
            // Retain the first syllables while WeChat opens its microphone.
            self.voiceSchedule.after(timing.preDrainDelay) { [weak self] in
                guard let self, self.sessionID == id, self.active else { return }
                self.drainStarted = true
                self.mic.startDraining()
                self.voiceTiming.mark("drainStarted", at: ProcessInfo.processInfo.systemUptime)
            }
        }
        // Change the input before Fn starts WeChat's capture session.
        if timing.preTriggerDelay > 0 {
            voiceSchedule.after(timing.preTriggerDelay, action: startTrigger)
        } else {
            startTrigger()
        }
        refreshReadiness(); writeStatus()
    }

    private func end(_ normal: Bool) {
        guard active else { return }
        guard normal else { abort(); return }
        guard !released else { return }
        guard voiceTrigger.active else { abort(); return }
        released = true
        let trigger = voiceSettings.trigger
        let timing = voiceSettings.timing
        voiceTiming.mark("audioStopped", at: ProcessInfo.processInfo.systemUptime)
        message.stringValue = trigger == .holdFn ? L("正在结束，文字由微信生成…") : L("正在结束语音输入…")
        let id = sessionID
        voiceSchedule.waitForDrain(ready: { [weak self] in
            guard let self else { return true }
            return self.drainStarted && self.mic.pendingFrames == 0
        }, completion: { [weak self] timedOut in
            guard let self, self.sessionID == id, self.active else { return }
            self.drainTimedOut = timedOut
            self.voiceTiming.mark("drainFinished", at: ProcessInfo.processInfo.systemUptime)
            self.voiceSchedule.after(timing.postDrainDelay) { [weak self] in
                guard let self, self.sessionID == id else { return }
                if self.voiceTrigger.active {
                    self.voiceTrigger.deactivate()
                    if trigger != .none { self.fnUps += 1 }
                }
                self.voiceTiming.mark("fnUp", at: ProcessInfo.processInfo.systemUptime)
                self.voiceSchedule.after(timing.postReleaseDelay) { [weak self] in
                    guard let self, self.sessionID == id else { return }
                    self.mic.end()
                    self.active = false
                    self.voiceTiming.finish(at: ProcessInfo.processInfo.systemUptime, cancelled: false)
                    self.voiceSchedule.cancel()
                    self.scheduleMaintenance()
                    self.remotePicker.isEnabled = true
                    self.updateDiscoveryButton()
                    self.completedSessions += 1
                    self.refreshReadiness()
                    self.updateStatusItem()
                    self.message.stringValue = L("本次语音已结束；可以继续按住语音键说话。")
                    self.writeStatus()
                }
            }
        })
        writeStatus()
    }

    private func abort() {
        sessionID = UUID()
        voiceSchedule.cancel()
        let hadKey = voiceSettings.trigger != .none
        if voiceTrigger.active {
            voiceTrigger.deactivate()
            if hadKey { fnUps += 1 }
            voiceTiming.mark("fnUp", at: ProcessInfo.processInfo.systemUptime)
        }
        mic.end()
        voiceTiming.finish(at: ProcessInfo.processInfo.systemUptime, cancelled: true)
        active = false; released = false
        scheduleMaintenance()
        remotePicker.isEnabled = true
        updateDiscoveryButton()
        updateStatusItem()
        refreshReadiness(); writeStatus()
    }

    private func updateStatusItem() {
        guard let button = item?.button else { return }
        let icon: StatusBarIcon = active ? .speaking : mapping.mouseModeActive ? .mouse : .normal
        button.title = ""
        button.image = icon.image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = icon.label
        button.setAccessibilityLabel(icon.label)
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
        _ = mic.connect()
        syncVoiceMenuStates()
        syncLaunchAtLoginItem()
        refreshReadiness()
        if CBCentralManager.authorization == .allowedAlways && !allowPrompted && voiceSettings.trigger.requiresAccessibility && !AXIsProcessTrusted() {
            allowPrompted = true
            // This only registers the app in the system permission list.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        scheduleMaintenance()
        writeStatus()
    }

    private var settingsVisible: Bool { window?.isVisible == true && window?.isMiniaturized == false && !NSApplication.shared.isHidden }

    private func refreshReadiness() {
        guard settingsVisible else { return }
        let accessibility = AXIsProcessTrusted(), inputMonitoring = mapping.listeningAllowed
        audioLabel.stringValue = !mic.available ? L("语音组件：需要安装") :
            mic.driverNeedsUpdate ? L("语音组件：需运行完整安装包更新") :
            voiceSettings.switchDefaultInput ? L("语音组件：已就绪") : L("语音组件：已就绪（免切默认麦）")
        permission.stringValue = L("辅助功能：%@\n输入监控：%@", accessibility ? L("已允许") : L("未允许"), inputMonitoring ? L("已允许") : L("未允许（自定义按键）"))
        permissionsButton.title = !accessibility ? L("允许辅助功能") : !inputMonitoring ? L("允许输入监控") : L("权限设置")
        var missing: [String] = []
        if !remote.ready { missing.append(L("连接遥控器")) }
        if !mic.available { missing.append(L("安装语音组件")) }
        else if mic.driverNeedsUpdate { missing.append(L("更新语音组件")) }
        if voiceSettings.trigger.requiresAccessibility && !accessibility { missing.append(L("允许辅助功能")) }
        if remote.xiaomiReady && !xiaomiVoiceKey.ready { missing.append(L("重新连接小米语音键")) }
        if !missing.isEmpty {
            readiness.stringValue = L("语音待就绪 · ") + missing.joined(separator: " · ")
        } else if unlock.blocksActions {
            readiness.stringValue = L("语音暂停 · 锁屏或连招录入中")
        } else if active || remote.voiceBusy {
            readiness.stringValue = L("语音处理中 · 请等待本次结束")
        } else if mapping.fnHeld {
            readiness.stringValue = L("语音等待 · 请先松开 Fn 按键")
        } else if voiceSettings.trigger != .holdFn || !voiceSettings.switchDefaultInput {
            readiness.stringValue = L("设备已就绪 · %@ · %@", voiceSettings.trigger.summaryTitle,
                                      voiceSettings.switchDefaultInput ? L("临时切换默认输入") : L("固定输入源 Chromecast Mic"))
        } else {
            readiness.stringValue = inputMonitoring ? L("设备与权限已就绪 · 微信语音请试说确认") :
                L("语音设备已就绪 · 自定义按键需输入监控 · 微信请试说确认")
        }
        readiness.textColor = missing.isEmpty ? SettingsTheme.forest : SettingsTheme.error
        readiness.toolTip = readiness.stringValue
    }

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
        let quitItem = appMenu.addItem(withTitle: L("退出 Remote Vibe"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        mainMenu.addItem(withTitle: "Remote Vibe", action: nil, keyEquivalent: "").submenu = appMenu
        let editMenu = NSMenu(title: L("编辑"))
        for (title, action, key) in [(L("撤销"), "undo:", "z"), (L("重做"), "redo:", "Z"),
                                    (L("剪切"), "cut:", "x"), (L("复制"), "copy:", "c"),
                                    (L("粘贴"), "paste:", "v"), (L("全选"), "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        mainMenu.addItem(withTitle: L("编辑"), action: nil, keyEquivalent: "").submenu = editMenu
        NSApplication.shared.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItem()
        let menu = NSMenu()
        menu.addItem(withTitle: "Remote Vibe \(version) (\(build))", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: L("打开遥控语音"), action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: L("立即结束本次语音"), action: #selector(stopVoice), keyEquivalent: "")
        menu.addItem(withTitle: L("退出鼠标模式"), action: #selector(exitMouseMode), keyEquivalent: "")
        let configurations = NSMenu(title: L("键位配置"))
        for (title, action) in [(L("导入键位到草稿…"), #selector(importMappings)),
                                (L("导出已保存键位…"), #selector(exportMappings)),
                                (L("载入上次有效备份"), #selector(restoreMappings))] {
            configurations.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: L("键位配置"), action: nil, keyEquivalent: "").submenu = configurations
        let voiceMenu = NSMenu(title: L("语音输入设置"))
        let presets: [(VoiceTrigger, String)] = [
            (.holdFn, L("按住 Fn（微信默认）")),
            (.holdRightOption, L("按住右 Option")),
            (.tapOptionSpace, L("点按 Option + Space 开始/结束")),
            (.none, L("仅送音（不发快捷键）"))
        ]
        for (index, entry) in presets.enumerated() {
            let presetItem = voiceMenu.addItem(withTitle: entry.1, action: #selector(selectVoiceTriggerPreset(_:)), keyEquivalent: "")
            presetItem.tag = index
            presetItem.target = self
            voicePresetItems.append((entry.0, presetItem))
        }
        customVoiceTriggerItem = voiceMenu.addItem(withTitle: L("自定义语音触发键…"), action: #selector(configureCustomVoiceTrigger), keyEquivalent: "")
        customVoiceTriggerItem.target = self
        voiceMenu.addItem(.separator())
        switchDefaultMicItem = voiceMenu.addItem(withTitle: L("说话时切换系统默认麦克风"), action: #selector(toggleSwitchDefaultMic), keyEquivalent: "")
        switchDefaultMicItem.target = self
        fastTurnaroundItem = voiceMenu.addItem(withTitle: L("快速连续说话（缩短缓冲等待）"), action: #selector(toggleFastTurnaround), keyEquivalent: "")
        fastTurnaroundItem.target = self
        menu.addItem(withTitle: L("语音输入设置"), action: nil, keyEquivalent: "").submenu = voiceMenu
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateStatus.isHidden = true
        menu.addItem(updateStatus)
        menu.addItem(withTitle: L("发布说明与下载…"), action: #selector(openReleases), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("退出"), action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        syncVoiceMenuStates()
        syncLaunchAtLoginItem()
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1080, visible.width - 64), height: min(812, visible.height - 76)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = L("Remote Vibe %@ · 遥控器设置", version)
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
        discoveryButton = SettingsTheme.button(L("扫描遥控器"), target: self, action: #selector(toggleDiscovery))
        pages = NSSegmentedControl(labels: [L("按键映射"), L("连招解锁")], trackingMode: .selectOne, target: self, action: #selector(changePage))
        pages.selectedSegment = 0
        mappingView = KeyMappingView(mapping: mapping)
        unlockView = ComboUnlockView(controller: unlock, allowPermissions: { [weak self] in self?.mappingView.allowListener() })
        unlockView.isHidden = true
        permissionsButton.target = self; permissionsButton.action = #selector(allowFn)
        let wechatButton = SettingsTheme.button(L("微信试说说明"), target: self, action: #selector(showVoiceHelp))
        let shell = SettingsView(mapping: mappingView, unlock: unlockView, remote: remotePicker, discovery: discoveryButton,
            pages: pages, connection: connection, audio: audioLabel, permission: permission,
            permissionsButton: permissionsButton, message: message, readiness: readiness, wechatButton: wechatButton)
        let scroll = SettingsScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.backgroundColor = SettingsTheme.canvas
        scroll.documentView = shell
        window.contentView = scroll
    }

    @objc private func show() {
        unlock.reload(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate()
        refresh()
    }
    @objc private func changeRemote() {
        guard !active else { return }
        unlockView.leave()
        xiaomiVoiceKey.stop()
        remote.select(RemoteProfile.allCases[remotePicker.indexOfSelectedItem])
        updateDiscoveryButton()
        updateRemoteUI()
        connection.stringValue = L("%@：正在连接…", remote.sourceName)
        message.stringValue = L("已选择%@，连接后按住语音键说话。", remote.sourceName)
        writeStatus()
    }
    @objc private func toggleDiscovery() {
        guard !active else { return }
        remote.toggleDiscovery()
    }
    private func updateDiscoveryButton() {
        discoveryButton.isEnabled = !active && !remote.ready
        discoveryButton.title = remote.ready ? L("已连接") : remote.scanning ? L("停止扫描") : remote.connecting ? L("取消等待") : L("扫描遥控器")
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
        if AXIsProcessTrusted() { mappingView.allowListener(); return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func showVoiceHelp() {
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = L("确认微信语音能出字")
        alert.informativeText = L("1. 在微信启用“长按 Fn 全局语音输入”，并允许微信使用麦克风。\n2. 微信输入设备选择系统默认输入或 Chromecast Mic。\n3. 关闭此说明，点击其他软件的文本框，按住遥控器原语音键说话，松开后确认文字出现。\n\n设备就绪不代表微信识别已验证；App 不读取识别结果。模拟 Fn 按键本身不会开启遥控器麦克风。")
        alert.addButton(withTitle: L("知道了，去试说"))
        alert.beginSheetModal(for: window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let idleForConfig = !active && !remote.voiceBusy && !unlock.blocksActions && window.attachedSheet == nil
        if [#selector(importMappings), #selector(exportMappings), #selector(restoreMappings)].contains(menuItem.action) {
            return idleForConfig
        }
        if [#selector(selectVoiceTriggerPreset(_:)), #selector(configureCustomVoiceTrigger),
            #selector(toggleSwitchDefaultMic), #selector(toggleFastTurnaround)].contains(menuItem.action) {
            syncVoiceMenuStates()
            return idleForConfig
        }
        if menuItem.action == #selector(toggleLaunchAtLogin) {
            syncLaunchAtLoginItem()
            return true
        }
        if menuItem.action == #selector(exitMouseMode) { return mapping.mouseModeActive }
        return menuItem.action != #selector(checkForUpdates) || updateCheck == nil
    }

    private func syncVoiceMenuStates() {
        let current = voiceSettings.trigger
        for (preset, menuItem) in voicePresetItems {
            menuItem.state = current == preset ? .on : .off
        }
        customVoiceTriggerItem?.state = current.isCustom ? .on : .off
        customVoiceTriggerItem?.title = current.isCustom ? L("%@…", current.summaryTitle) : L("自定义语音触发键…")
        switchDefaultMicItem?.state = voiceSettings.switchDefaultInput ? .on : .off
        fastTurnaroundItem?.state = voiceSettings.fastTurnaround ? .on : .off
    }

    private func syncLaunchAtLoginItem() {
        switch launchAtLogin.state {
        case .enabled: launchAtLoginItem.state = .on
        case .requiresApproval: launchAtLoginItem.state = .mixed
        case .notRegistered, .notFound: launchAtLoginItem.state = .off
        }
    }

    @objc private func selectVoiceTriggerPreset(_ sender: NSMenuItem) {
        guard !active, !remote.voiceBusy, !unlock.blocksActions,
              voicePresetItems.indices.contains(sender.tag) else { return }
        voiceSettings.trigger = voicePresetItems[sender.tag].0
        syncVoiceMenuStates()
        message.stringValue = L("语音触发方式已设为：%@", voiceSettings.trigger.summaryTitle)
        refreshReadiness()
        writeStatus()
    }

    @objc private func toggleSwitchDefaultMic() {
        guard !active, !remote.voiceBusy, !unlock.blocksActions else { return }
        voiceSettings.switchDefaultInput.toggle()
        syncVoiceMenuStates()
        message.stringValue = voiceSettings.switchDefaultInput ?
            L("已开启说话时自动切换系统默认麦克风") :
            L("已关闭切换系统默认麦克风；请在目标软件将输入设备设为 Chromecast Mic")
        refreshReadiness()
        writeStatus()
    }

    @objc private func toggleFastTurnaround() {
        guard !active, !remote.voiceBusy, !unlock.blocksActions else { return }
        voiceSettings.fastTurnaround.toggle()
        syncVoiceMenuStates()
        message.stringValue = voiceSettings.fastTurnaround ?
            L("已开启快速连续说话（若首字缺失可关闭此项）") :
            L("已恢复标准缓冲等待时间")
        refreshReadiness()
        writeStatus()
    }

    @objc private func configureCustomVoiceTrigger() {
        guard !active, !remote.voiceBusy, !unlock.blocksActions else { return }
        show()
        guard window.attachedSheet == nil else { return }
        let accessory = FlippedAccessoryView(frame: NSRect(x: 0, y: 0, width: 396, height: 142))
        let modeControl = NSSegmentedControl(labels: VoiceTriggerMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        modeControl.frame = NSRect(x: 0, y: 4, width: 396, height: 28)
        modeControl.segmentDistribution = .fillEqually
        accessory.addSubview(modeControl)

        let modifierEntries: [(String, CGEventFlags)] = [
            ("⌃ Control", .maskControl), ("⇧ Shift", .maskShift), ("⌥ Option", .maskAlternate),
            ("⌘ Command", .maskCommand), ("Fn", .maskSecondaryFn)
        ]
        var checkboxes: [(NSButton, CGEventFlags)] = []
        for (index, entry) in modifierEntries.enumerated() {
            let box = NSButton(checkboxWithTitle: entry.0, target: nil, action: nil)
            box.font = .systemFont(ofSize: 12)
            box.frame = NSRect(x: CGFloat(index % 3) * 132, y: 44 + CGFloat(index / 3) * 26, width: 126, height: 22)
            accessory.addSubview(box)
            checkboxes.append((box, entry.1))
        }

        let keyPopup = NSPopUpButton(frame: NSRect(x: 0, y: 106, width: 396, height: 28), pullsDown: false)
        keyPopup.addItems(withTitles: MappingKey.all.map(\.name))
        accessory.addSubview(keyPopup)

        if case let .custom(mode, usage, modifiers) = voiceSettings.trigger {
            modeControl.selectedSegment = VoiceTriggerMode.allCases.firstIndex(of: mode) ?? 0
            keyPopup.selectItem(at: MappingKey.all.firstIndex { $0.usage == usage } ?? 0)
            let flags = CGEventFlags(rawValue: modifiers)
            for (box, flag) in checkboxes { box.state = flags.contains(flag) ? .on : .off }
        } else {
            modeControl.selectedSegment = 0
            keyPopup.selectItem(at: MappingKey.all.firstIndex { $0.usage == 0x2C } ?? 0)
            for (box, flag) in checkboxes { box.state = flag == .maskAlternate ? .on : .off }
        }

        let alert = NSAlert()
        alert.messageText = L("自定义语音触发快捷键")
        alert.informativeText = L("选择遥控器语音开始和结束时发送的快捷键，可用于系统听写、豆包、Superwhisper 等语音软件。")
        alert.accessoryView = accessory
        alert.addButton(withTitle: L("保存"))
        alert.addButton(withTitle: L("取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let selectedKey = MappingKey.all[max(0, keyPopup.indexOfSelectedItem)]
            let trigger: VoiceTrigger
            if selectedKey.usage == MappingKey.fnUsage {
                trigger = .holdFn
            } else {
                let mode = VoiceTriggerMode.allCases[max(0, modeControl.selectedSegment)]
                let flags = checkboxes.filter { $0.0.state == .on }.reduce(UInt64(0)) { $0 | $1.1.rawValue }
                trigger = .custom(mode: mode, usage: selectedKey.usage, modifiers: flags)
            }
            self.voiceSettings.trigger = trigger
            self.syncVoiceMenuStates()
            self.message.stringValue = L("语音触发方式已设为：%@", self.voiceSettings.trigger.summaryTitle)
            self.refreshReadiness()
            self.writeStatus()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let feedback = launchAtLogin.toggle()
        syncLaunchAtLoginItem()
        if !active && !remote.voiceBusy {
            message.stringValue = feedback
        }
        writeStatus()
    }

    private func showMappings() -> Bool {
        guard !active, !remote.voiceBusy, !unlock.blocksActions, window.attachedSheet == nil else { return false }
        pages.selectedSegment = 0; changePage(); show()
        return true
    }
    @objc private func importMappings() { if showMappings() { mappingView.importConfiguration() } }
    @objc private func exportMappings() { if showMappings() { mappingView.exportConfiguration() } }
    @objc private func restoreMappings() { if showMappings() { mappingView.restoreConfiguration() } }

    @objc private func checkForUpdates() {
        guard updateCheck == nil, !stopping else { return }
        updateStatus.isHidden = false; updateStatus.title = L("正在检查 GitHub 发布版本…")
        updateStatus.action = nil
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/jmeviler/remote-vibe/releases/latest")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RemoteVibe/\(version)", forHTTPHeaderField: "User-Agent")
        updateCheck = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, !self.stopping else { return }
                self.updateCheck = nil
                let result: String
                if error != nil {
                    result = L("检查失败，请检查网络或打开发布页")
                } else if let http = response as? HTTPURLResponse,
                          http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
                    result = L("GitHub 暂时限流，请稍后重试或打开发布页")
                } else if (response as? HTTPURLResponse)?.statusCode == 404 {
                    result = L("暂无正式发布版本")
                } else if (response as? HTTPURLResponse)?.statusCode == 200,
                          let data,
                          let release = try? JSONDecoder().decode(ReleaseUpdate.self, from: data) {
                    result = release.message(installed: self.version)
                } else {
                    result = L("GitHub 查询失败，可稍后重试或打开发布页")
                }
                self.updateStatus.title = result
                self.updateStatus.action = #selector(self.openReleases)
                // Keep the result in the menu; no delayed dialog steals a voice-input target.
                if !self.active && !self.remote.voiceBusy {
                    self.message.stringValue = L("%@ · 当前 %@ · 下载请打开菜单中的发布页", result, self.version)
                    self.writeStatus()
                }
            }
        }
        updateCheck?.resume()
    }

    @objc private func openReleases() {
        if !NSWorkspace.shared.open(ReleaseUpdate.releasesURL) {
            updateStatus.isHidden = false; updateStatus.title = L("无法打开浏览器，请手动访问 GitHub 项目")
        }
    }
    @objc private func exitMouseMode() { mapping.exitMouseMode(); mappingView.refreshStatus(); writeStatus() }

    @objc private func stopVoice() { mapping.suspendActions(); remote.cancelVoice(); abort() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func buildStatusPayload() -> [String: Any] {
        [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "mode": voiceSettings.trigger.identifier,
            "voiceTrigger": voiceSettings.trigger.summaryTitle,
            "switchDefaultInput": voiceSettings.switchDefaultInput,
            "fastTurnaround": voiceSettings.fastTurnaround,
            "bluetoothAuthorization": CBCentralManager.authorization.rawValue,
            "accessibility": AXIsProcessTrusted(), "connected": remote.ready,
            "microphoneReady": mic.available, "driverNeedsUpdate": mic.driverNeedsUpdate, "recording": remote.streaming,
            "sessionActive": active, "fnHeld": voiceTrigger.fnHeld || mapping.fnHeld, "mappedFnHeld": mapping.fnHeld, "fnDowns": fnDowns, "fnUps": fnUps,
            "audioFrames": remote.frameCount, "fedSamples": mic.fedFrames, "renderedSamples": mic.renderedFrames,
            "voiceTiming": voiceTiming.diagnostics, "audioBuffer": mic.bufferDiagnostics, "drainTimedOut": drainTimedOut,
            "completedSessions": completedSessions, "status": message.stringValue,
            "voiceSource": remote.sourceName, "voiceProfile": remote.profile.rawValue,
            "voiceProtocol": remote.protocolSummary, "connectionStatus": connection.stringValue,
            "bluetoothScanning": remote.scanning, "bluetoothConnecting": remote.connecting,
            "bluetoothScanStarts": remote.scanStarts,
            "mappedVoiceHeld": mapping.mappedVoiceHeld, "mappedVoiceActive": remote.mappedVoiceActive, "voiceBusy": remote.voiceBusy,
            "xiaomiVoiceKeyReady": xiaomiVoiceKey.ready, "xiaomiVoiceKeyStatus": xiaomiVoiceKey.status,
            "mouseModeActive": mapping.mouseModeActive,
            "launchAtLogin": launchAtLogin.state.rawValue,
            "keyMappingStatus": mapping.status, "keyMappingConnected": mapping.connected,
            "configurationNotice": mapping.configurationNotice ?? "",
            "inputMonitoring": mapping.listeningAllowed,
            "shortcutListener": mapping.listening,
            "keyActionChoices": ActionCatalog.presets.count,
            "maintenanceInterval": poll?.timeInterval ?? 0,
            "defaultInput": AudioDevices.string(AudioDevices.defaultInput(), kAudioObjectPropertyName) ?? "none"
        ]
    }

    private func writeStatus() {
        statusWriter.schedule(buildStatusPayload())
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopping = true
        mic.onUnavailable = {}; mic.onAvailabilityChange = {}
        updateCheck?.cancel(); updateCheck = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        mapping.onDeviceChange = nil
        mapping.onFnChange = nil
        mapping.onMouseModeChange = nil
        poll?.invalidate(); unlock.stop(); mapping.stop(); remote.shutdown(); xiaomiVoiceKey.stop(); abort(); mic.stop()
        statusWriter.flushSync(buildStatusPayload())
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
