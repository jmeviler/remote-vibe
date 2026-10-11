import AppKit
import IOKit.hid
import IOKit.hidsystem

struct MappingKey {
    // App-only selector: Fn has no ordinary USB keyboard usage and must never use native remapping.
    static let fnUsage: UInt64 = 0
    let name: String
    let usage: UInt64
    let code: CGKeyCode
    static let all: [MappingKey] = [
        .init(name: "Fn", usage: fnUsage, code: 63),
        .init(name: "Enter 回车", usage: 0x28, code: 36), .init(name: "Backspace 退格删除", usage: 0x2A, code: 51),
        .init(name: "Escape 取消", usage: 0x29, code: 53), .init(name: "Tab", usage: 0x2B, code: 48),
        .init(name: "Space 空格", usage: 0x2C, code: 49),
        .init(name: "↑ 上", usage: 0x52, code: 126), .init(name: "↓ 下", usage: 0x51, code: 125),
        .init(name: "← 左", usage: 0x50, code: 123), .init(name: "→ 右", usage: 0x4F, code: 124),
        .init(name: "Delete 向后删除", usage: 0x4C, code: 117),
        .init(name: "Home", usage: 0x4A, code: 115), .init(name: "End", usage: 0x4D, code: 119),
        .init(name: "Page Up", usage: 0x4B, code: 116), .init(name: "Page Down", usage: 0x4E, code: 121)
    ] + zip(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6])
        .enumerated().map { .init(name: String($0.element.0), usage: UInt64(4 + $0.offset), code: CGKeyCode($0.element.1)) }
      + zip(Array("1234567890"), [18,19,20,21,23,22,26,28,25,29])
        .enumerated().map { .init(name: String($0.element.0), usage: UInt64(0x1E + $0.offset), code: CGKeyCode($0.element.1)) }
      + [122,120,99,118,96,97,98,100,101,109,103,111].enumerated()
        .map { .init(name: "F\($0.offset + 1)", usage: UInt64(0x3A + $0.offset), code: CGKeyCode($0.element)) }
      + [105,107,113,106,64,79,80,90].enumerated()
        .map { .init(name: "F\($0.offset + 13)", usage: UInt64(0x68 + $0.offset), code: CGKeyCode($0.element)) }
      + [.init(name: "[", usage: 0x2F, code: 33), .init(name: "]", usage: 0x30, code: 30),
         .init(name: "/", usage: 0x38, code: 44), .init(name: "-", usage: 0x2D, code: 27),
         .init(name: "=", usage: 0x2E, code: 24), .init(name: ".", usage: 0x37, code: 47),
         .init(name: ",", usage: 0x36, code: 43), .init(name: ";", usage: 0x33, code: 41),
         .init(name: "`", usage: 0x35, code: 50), .init(name: "'", usage: 0x34, code: 39),
         .init(name: "\\", usage: 0x31, code: 42)]
      + [83,84,85,86,87,88,89,91,92].enumerated()
        .map { .init(name: "小键盘 \($0.offset + 1)", usage: UInt64(0x59 + $0.offset), code: CGKeyCode($0.element)) }
      + [.init(name: "小键盘 0", usage: 0x62, code: 82), .init(name: "小键盘 .", usage: 0x63, code: 65),
         .init(name: "小键盘 Enter", usage: 0x58, code: 76), .init(name: "小键盘 +", usage: 0x57, code: 69),
         .init(name: "小键盘 −", usage: 0x56, code: 78), .init(name: "小键盘 ×", usage: 0x55, code: 67),
         .init(name: "小键盘 ÷", usage: 0x54, code: 75), .init(name: "小键盘 =", usage: 0x67, code: 81),
         .init(name: "小键盘 Clear", usage: 0x53, code: 71)]
}

struct KeyBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case original, disabled, key, scrollUp, scrollDown, scrollLeft, scrollRight
        case nextDisplay, nextWindow, text, systemKey, openApp, openURL
    }
    var kind: Kind
    var usage: UInt64 = 0x28
    var modifiers: UInt64 = 0
    var text: String?
    var appPath: String?
    var url: String?
    var isFn: Bool { kind == .key && usage == MappingKey.fnUsage }
    var isScroll: Bool { [.scrollUp, .scrollDown, .scrollLeft, .scrollRight].contains(kind) }
    var usesListener: Bool {
        isFn || kind == .text || isScroll || kind == .nextDisplay || kind == .nextWindow ||
        kind == .systemKey || kind == .openApp || kind == .openURL ||
        (kind == .key && (modifiers != 0 || usage == 0x29))
    }
    var key: MappingKey? { MappingKey.all.first { $0.usage == usage } }
    var isValid: Bool {
        let allowed = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]).rawValue
        if kind == .systemKey { return SystemControl(rawValue: usage) != nil && modifiers == 0 }
        return kind != .key || (key != nil && modifiers & ~allowed == 0 && (!isFn || modifiers == 0))
    }
    var configurationError: String? {
        if !isValid { return "按键动作无效，请重新选择。" }
        if kind == .openApp && !(appPath?.hasPrefix("/") == true && (appPath! as NSString).pathExtension.lowercased() == "app") {
            return "请先选择要打开的应用。"
        }
        if kind == .openURL && webpageURL == nil { return "请输入完整的 http:// 或 https:// 网页地址。" }
        return nil
    }
    var webpageURL: URL? {
        guard let url, let value = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(value.scheme?.lowercased() ?? ""), let host = value.host, !host.isEmpty else { return nil }
        return value
    }
    var title: String {
        switch kind {
        case .original: return "原按键功能"
        case .disabled: return "不执行"
        case .scrollUp: return "向上滚动"
        case .scrollDown: return "向下滚动"
        case .scrollLeft: return "向左滚动"
        case .scrollRight: return "向右滚动"
        case .nextDisplay: return "切换屏幕"
        case .nextWindow: return "切换当前屏幕窗口"
        case .text: return "输入常用文本"
        case .systemKey: return SystemControl(rawValue: usage)?.title ?? "系统按键"
        case .openApp: return appPath.map { "打开 \(($0 as NSString).lastPathComponent)" } ?? "打开指定应用"
        case .openURL: return "打开指定网页"
        case .key:
            if isFn { return "Fn（按住 / 松开）" }
            let flags = CGEventFlags(rawValue: modifiers)
            let prefix = [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "Fn + ")]
                .filter { flags.contains($0.0) }.map { $0.1 }.joined()
            return prefix + (key?.name ?? "Enter 回车")
        }
    }
}

struct ButtonBinding: Codable, Equatable {
    var singleClick: KeyBinding
    var doubleClick: KeyBinding?
    var longPress: KeyBinding?

    init(singleClick: KeyBinding, doubleClick: KeyBinding? = nil, longPress: KeyBinding? = nil) {
        self.singleClick = singleClick; self.doubleClick = doubleClick; self.longPress = longPress
    }

    // Keep the v1 single-action fields at the top level. Existing preferences
    // decode unchanged, and older builds can still read the single action.
    private enum CodingKeys: String, CodingKey { case doubleClick, longPress }
    init(from decoder: Decoder) throws {
        singleClick = try KeyBinding(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        doubleClick = try values.decodeIfPresent(KeyBinding.self, forKey: .doubleClick)
        longPress = try values.decodeIfPresent(KeyBinding.self, forKey: .longPress)
    }
    func encode(to encoder: Encoder) throws {
        try singleClick.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(doubleClick, forKey: .doubleClick)
        try values.encodeIfPresent(longPress, forKey: .longPress)
    }

    subscript(_ trigger: ButtonTrigger) -> KeyBinding? {
        get {
            switch trigger {
            case .singleClick: return singleClick
            case .doubleClick: return doubleClick
            case .longPress: return longPress
            }
        }
        set {
            switch trigger {
            case .singleClick: if let newValue { singleClick = newValue }
            case .doubleClick: doubleClick = newValue
            case .longPress: longPress = newValue
            }
        }
    }

    var hasGestures: Bool { doubleClick != nil || longPress != nil }
    var usesListener: Bool { hasGestures || singleClick.usesListener }
    var validationMessage: String? {
        if let error = [singleClick, doubleClick, longPress].compactMap({ $0?.configurationError }).first { return error }
        if hasGestures && singleClick.kind == .original { return "使用双击或长按前，请为单击选择明确动作（也可选“不执行”）。" }
        if hasGestures && singleClick.isFn { return "单击 Fn 需要按下即保持；请将 Fn 放到长按，或取消双击和长按。" }
        if doubleClick?.isFn == true { return "双击不支持保持 Fn；请将 Fn 放到长按。" }
        if doubleClick?.kind == .original || longPress?.kind == .original { return "双击和长按需要选择明确动作。" }
        return nil
    }
    var summary: String {
        ButtonTrigger.allCases.compactMap { trigger in self[trigger].map { "\(trigger.title)：\($0.title)" } }.joined(separator: "；")
    }
}

struct MappedButton {
    let code: UInt8
    let name: String
    let usage: UInt64
    var page: UInt64 = 12
    var defaultBinding: KeyBinding? = nil
    var source: UInt64 { (page << 32) | usage }
    var initial: KeyBinding {
        if let defaultBinding { return defaultBinding }
        if code == 10 { return KeyBinding(kind: .nextWindow) }
        if code == 14 { return KeyBinding(kind: .nextDisplay) }
        let keys: [UInt8: UInt64] = [3:0x52, 4:0x51, 5:0x50, 6:0x4F, 7:0x29, 8:0x28, 11:0x2A]
        return keys[code].map { KeyBinding(kind: .key, usage: $0) } ?? KeyBinding(kind: .original)
    }
    // Report-array indices and consumer usages from this remote's HID descriptor.
    static let all: [MappedButton] = [
        .init(code: 3, name: "方向上", usage: 0x42), .init(code: 4, name: "方向下", usage: 0x43),
        .init(code: 5, name: "方向左", usage: 0x44), .init(code: 6, name: "方向右", usage: 0x45),
        .init(code: 7, name: "中央确认", usage: 0x41), .init(code: 11, name: "返回箭头", usage: 0x224),
        .init(code: 10, name: "主页", usage: 0x223), .init(code: 8, name: "静音", usage: 0xE2),
        .init(code: 14, name: "YouTube", usage: 0x77), .init(code: 15, name: "Netflix", usage: 0x78),
        .init(code: 1, name: "电源", usage: 0x19E), .init(code: 17, name: "信源", usage: 0x89),
        .init(code: 12, name: "音量＋", usage: 0xE9), .init(code: 13, name: "音量－", usage: 0xEA)
    ]

    static let xiaomi: [MappedButton] = [
        .init(code: 3, name: "方向上", usage: 0x52, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 4, name: "方向下", usage: 0x51, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 5, name: "方向左", usage: 0x50, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 6, name: "方向右", usage: 0x4F, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 7, name: "中央确认", usage: 0x28, page: 7, defaultBinding: .init(kind: .key, usage: 0x28)),
        .init(code: 11, name: "返回", usage: 0xF1, page: 7, defaultBinding: .init(kind: .key, usage: 0x2A)),
        .init(code: 10, name: "主页", usage: 0x4A, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 12, name: "音量＋", usage: 0x80, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 13, name: "音量－", usage: 0x81, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 18, name: "菜单", usage: 0x65, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 19, name: "TV", usage: 0x35, page: 7, defaultBinding: .init(kind: .original)),
        .init(code: 1, name: "电源", usage: 0x66, page: 7, defaultBinding: .init(kind: .original))
    ]

    static func buttons(for profile: RemoteProfile) -> [MappedButton] { profile == .chromecast ? all : xiaomi }

    static func pressed(reportID: UInt32, bytes: [UInt8], profile: RemoteProfile) -> Set<UInt8>? {
        guard reportID == 1 else { return nil }
        if profile == .chromecast {
            let payload = bytes.count == 3 && bytes.first == 1 ? Array(bytes.dropFirst()) : bytes
            guard payload.count == 2 else { return nil }
            return Set(payload.filter { $0 != 0 })
        }
        let payload = bytes.count == 7 && bytes.first == 1 ? Array(bytes.dropFirst()) : bytes
        guard payload.count == 6 else { return nil }
        let usages = Set(stride(from: 0, to: 6, by: 2).map { UInt64(payload[$0]) | UInt64(payload[$0 + 1]) << 8 })
        return Set(xiaomi.filter { usages.contains($0.usage) }.map(\.code))
    }
}

final class KeyMapping {
    typealias Bindings = [String: ButtonBinding]
    private typealias HIDMappings = [[String: UInt64]]
    private struct Snapshot {
        let service: IOHIDServiceClient
        var original: HIDMappings
        var owned: HIDMappings = []
        var revision = -1
        var bindingsRevision = -1
        var conflictedSources = Set<UInt64>()
    }
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private let desktop = DesktopActions()
    private let textInput = TextInput()
    private var actionFeedback: (text: String, until: Date)?
    private var actionGeneration = 0
    private var manager: IOHIDManager?
    private var held = Set<UInt8>()
    private let mappedFn = FnKey()
    private var fnButtons = Set<UInt8>()
    var fnHeld: Bool { mappedFn.held }
    var onFnChange: (() -> Void)?
    private var repeats: [UInt8: Timer] = [:]
    private var gestures = ButtonGestureRecognizer()
    private struct GestureTimerKey: Hashable {
        let button: UInt8
        let trigger: ButtonTrigger
    }
    private var gestureTimers: [GestureTimerKey: Timer] = [:]
    private var snapshots: [UInt64: Snapshot] = [:]
    private var revision = 0
    private var bindingsRevision = 0
    private var activeShortcuts = Set<UInt8>()
    private(set) var capturedButtons = Set<UInt8>()
    private var pendingCapture: Set<UInt8>?
    var onCapturedPress: ((UInt8) -> Void)?
    var onInputReset: (() -> Void)?
    var onDeviceChange: (() -> Void)?
    var captureReady: Bool { !capturedButtons.isEmpty && connected && listenerOK && capturedButtons.isSubset(of: activeShortcuts) }
    private let property = "UserKeyMapping" as CFString
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private(set) var bindings: Bindings
    private(set) var profile: RemoteProfile
    var buttons: [MappedButton] { MappedButton.buttons(for: profile) }
    private(set) var status = "等待遥控器连接"
    private(set) var connected = false
    private(set) var needsApply = false
    private var listenerOK = false
    var canPerform: () -> Bool = { true }
    var listening: Bool { manager != nil }
    private var accessCheckedAt = -Double.infinity
    private var accessGranted = false
    // IOHIDCheckAccess performs synchronous TCC IPC. Share one result across a refresh pass.
    // Real action injection still checks Accessibility at the point of use.
    var listeningAllowed: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - accessCheckedAt >= 1 {
            accessGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            accessCheckedAt = now
        }
        return accessGranted
    }

    init(profile: RemoteProfile = .chromecast) {
        self.profile = profile
        bindings = Self.load(profile)
    }

    private static func load(_ profile: RemoteProfile) -> Bindings {
        if let data = UserDefaults.standard.data(forKey: profile.mappingKey),
           let stored = try? JSONDecoder().decode(Bindings.self, from: data) {
            return stored.filter { code, b in
                MappedButton.buttons(for: profile).contains { String($0.code) == code } &&
                b.validationMessage == nil
            }
        } else { return [:] }
    }

    func selectProfile(_ profile: RemoteProfile) {
        guard self.profile != profile else { return }
        stop()
        capturedButtons.removeAll(); pendingCapture = nil
        self.profile = profile
        bindings = Self.load(profile)
        bindingsRevision += 1; revision += 1
        refresh()
    }

    func binding(_ button: MappedButton) -> ButtonBinding { bindings[String(button.code)] ?? .init(singleClick: button.initial) }

    func capture(_ codes: Set<UInt8>) {
        guard codes != capturedButtons else { pendingCapture = nil; return }
        releaseMappedFn()
        cancelPendingActions()
        // Restore normal mappings after the last captured press has been released.
        guard capturedButtons.isEmpty || held.isEmpty else { pendingCapture = codes; return }
        pendingCapture = nil
        cancelRepeats()
        capturedButtons = codes
        revision += 1
        refresh()
    }

    func save(_ values: Bindings) {
        if let error = values.values.compactMap(\.validationMessage).first { status = error; return }
        releaseMappedFn()
        cancelPendingActions()
        actionFeedback = nil
        bindings = values
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: profile.mappingKey) }
        cancelRepeats()
        bindingsRevision += 1
        revision += 1
        refresh()
    }

    func refresh() {
        let needsListener = !capturedButtons.isEmpty || buttons.contains { binding($0).usesListener }
        if needsListener && listeningAllowed && AXIsProcessTrusted() {
            if manager == nil { startListener() }
        } else { stopListener() }
        listenerOK = manager != nil && listeningAllowed && AXIsProcessTrusted()
        let entries: HIDMappings = buttons.compactMap { button in
            let configuration = binding(button)
            let value = configuration.singleClick
            guard value.kind != .original || configuration.hasGestures || capturedButtons.contains(button.code) else { return nil }
            // Unassigned usage suppresses a custom key even while permission is missing.
            let target = !capturedButtons.contains(button.code) && value.kind == .key && !configuration.usesListener ? value.usage : 0
            return [src: button.source, dst: (UInt64(7) << 32) | target]
        }
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []).filter {
            (IOHIDServiceClientCopyProperty($0, "VendorID" as CFString) as? NSNumber)?.intValue == profile.vendorID &&
            (IOHIDServiceClientCopyProperty($0, "ProductID" as CFString) as? NSNumber)?.intValue == profile.productID
        }
        let disconnected = connected && services.isEmpty
        if disconnected { cancelPendingActions() }
        connected = !services.isEmpty
        var present = Set<UInt64>()
        var applied = true
        needsApply = false
        let previousShortcuts = activeShortcuts
        activeShortcuts = listenerOK ? Set(buttons.filter { binding($0).usesListener }.map { $0.code }).union(capturedButtons) : []
        for service in services {
            guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { continue }
            present.insert(id)
            var current = IOHIDServiceClientCopyProperty(service, property) as? HIDMappings ?? []
            var snapshot = snapshots[id] ?? Snapshot(service: service, original: current)
            // Apply only on connection or explicit save; never fight another remapper.
            if snapshot.revision != revision {
                if snapshot.bindingsRevision != bindingsRevision {
                    snapshot.conflictedSources.removeAll()
                } else {
                    // A temporary capture must not reclaim mappings another tool has changed.
                    snapshot.conflictedSources.formUnion(snapshot.owned.filter { !current.contains($0) }.compactMap { $0[src] })
                }
                snapshot.original = restored(current, snapshot: snapshot)
                snapshot.owned = entries.filter { !snapshot.conflictedSources.contains($0[src] ?? 0) }
                let sources = Set(snapshot.owned.compactMap { $0[src] })
                let desired = snapshot.original.filter { !sources.contains($0[src] ?? 0) } + snapshot.owned
                let ok = current == desired || IOHIDServiceClientSetProperty(service, property, desired as CFArray)
                current = IOHIDServiceClientCopyProperty(service, property) as? HIDMappings ?? []
                if ok && current == desired { snapshot.revision = revision; snapshot.bindingsRevision = bindingsRevision }
                else { applied = false }
                snapshots[id] = snapshot
            }
            needsApply = needsApply || !entries.allSatisfy { current.contains($0) }
            // Emit a custom action only after its native action is confirmed suppressed.
            activeShortcuts = activeShortcuts.filter { code in
                guard let button = buttons.first(where: { $0.code == code }) else { return false }
                return current.contains([src: button.source, dst: UInt64(7) << 32])
            }
        }
        if !connected { activeShortcuts.removeAll(); cancelRepeats(); held.removeAll() }
        if !previousShortcuts.isSubset(of: activeShortcuts) { cancelPendingActions() }
        if !fnButtons.isSubset(of: activeShortcuts) { releaseMappedFn() }
        snapshots = snapshots.filter { present.contains($0.key) }
        status = !connected ? "设置已保存 · 等待遥控器连接" : !applied ? "按键设置未能生效，请检查权限" :
            needsApply ? "按键设置被其他程序更改 · 保存可重新应用" :
            needsListener && !listenerOK ? "自定义动作需要输入监控及辅助功能权限" : "按键已生效 · 重连后自动恢复"
        if connected && applied && !needsApply && (!needsListener || listenerOK),
           let feedback = actionFeedback, feedback.until > Date() { status = feedback.text }
        if disconnected { onInputReset?() }
    }

    private func restored(_ current: HIDMappings, snapshot: Snapshot) -> HIDMappings {
        let unchanged = snapshot.owned.filter { current.contains($0) }
        let sources = Set(unchanged.compactMap { $0[src] })
        return current.filter { !unchanged.contains($0) } + snapshot.original.filter { sources.contains($0[src] ?? 0) }
    }

    func requestListeningAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent); accessCheckedAt = -Double.infinity }

    private func startListener() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey:profile.vendorID, kIOHIDProductIDKey:profile.productID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, _ in
            guard let context else { return }
            let mapping = Unmanaged<KeyMapping>.fromOpaque(context).takeUnretainedValue()
            // Defer until startListener has finished assigning its manager.
            DispatchQueue.main.async { [weak mapping] in mapping?.onDeviceChange?() }
        }, context)
        IOHIDManagerRegisterInputReportCallback(m, { context, result, _, _, reportID, bytes, count in
            guard let context, result == kIOReturnSuccess, reportID == 1 else { return }
            let data = Array(UnsafeBufferPointer(start: bytes, count: count))
            let mapping = Unmanaged<KeyMapping>.fromOpaque(context).takeUnretainedValue()
            guard let pressed = MappedButton.pressed(reportID: reportID, bytes: data, profile: mapping.profile) else { return }
            mapping.handle(pressed)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, _ in
            guard let context else { return }
            let mapping = Unmanaged<KeyMapping>.fromOpaque(context).takeUnretainedValue()
            // Removal is cancellation, never a physical release that could emit a click.
            mapping.suspendActions()
            mapping.held.removeAll()
            mapping.onInputReset?()
            DispatchQueue.main.async { [weak mapping] in
                guard let mapping else { return }
                if let pending = mapping.pendingCapture { mapping.capture(pending) }
                mapping.onDeviceChange?()
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // Observe raw reports only; normal keys still use macOS's native per-device mapping.
        guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(m, 0)
            return
        }
        manager = m
    }

    private func handle(_ pressed: Set<UInt8>) {
        let released = held.subtracting(pressed)
        for code in released { repeats.removeValue(forKey: code)?.invalidate() }
        let added = pressed.subtracting(held)
        held = pressed
        fnButtons.subtract(released)
        if fnButtons.isEmpty { releaseMappedFn() }
        if pressed.isEmpty, let pendingCapture { capture(pendingCapture) }
        for code in released.sorted() {
            execute(gestures.release(code, at: ProcessInfo.processInfo.systemUptime))
        }
        if !added.isDisjoint(with: capturedButtons), pressed.count > 1 {
            if captureReady { onCapturedPress?(0) }
            return
        }
        for code in added.sorted() {
            if capturedButtons.contains(code) {
                if captureReady { onCapturedPress?(code) }
                continue
            }
            guard let button = buttons.first(where: { $0.code == code }) else { continue }
            let configuration = binding(button)
            guard activeShortcuts.contains(code), canPerform() else { continue }
            if configuration.hasGestures {
                execute(gestures.press(code, doubleClick: configuration.doubleClick != nil,
                                       longPress: configuration.longPress != nil, at: ProcessInfo.processInfo.systemUptime))
                continue
            }
            let value = configuration.singleClick
            perform(value, button: code)
            // Only scrolling repeats here; Esc, shortcuts and desktop actions fire once.
            if value.isScroll {
                let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                    guard let self, self.held.contains(code), self.activeShortcuts.contains(code), self.canPerform() else { return }
                    self.perform(value, button: code)
                }
                timer.fireDate = Date().addingTimeInterval(0.4)
                repeats[code] = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func execute(_ commands: [ButtonGestureRecognizer.Command]) {
        for command in commands {
            switch command {
            case let .cancel(code, trigger):
                gestureTimers.removeValue(forKey: .init(button: code, trigger: trigger))?.invalidate()
            case let .schedule(code, trigger, deadline):
                let key = GestureTimerKey(button: code, trigger: trigger)
                gestureTimers.removeValue(forKey: key)?.invalidate()
                let timer = Timer(timeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] timer in
                    guard let self, self.gestureTimers[key] === timer else { return }
                    self.gestureTimers.removeValue(forKey: key)
                    self.execute(self.gestures.timeout(code, trigger: trigger, at: ProcessInfo.processInfo.systemUptime))
                }
                gestureTimers[key] = timer
                RunLoop.main.add(timer, forMode: .common)
            case let .trigger(code, trigger):
                guard connected, listenerOK, listeningAllowed, activeShortcuts.contains(code),
                      capturedButtons.isEmpty, pendingCapture == nil, canPerform(),
                      let button = buttons.first(where: { $0.code == code }),
                      let value = binding(button)[trigger] else { continue }
                // A remapper or disconnect can intervene while a gesture is waiting.
                // Recheck ownership at delivery without rewriting any HID property.
                guard !snapshots.isEmpty, snapshots.values.allSatisfy({ snapshot in
                    let current = IOHIDServiceClientCopyProperty(snapshot.service, property) as? HIDMappings ?? []
                    return current.contains([src: button.source, dst: UInt64(7) << 32])
                }) else {
                    cancelPendingActions()
                    releaseMappedFn()
                    needsApply = true
                    status = "按键设置已变化，本次手势已取消 · 保存可重新应用"
                    return
                }
                // A delayed long-press callback must never leave Fn down after release.
                if value.isFn && !held.contains(code) { continue }
                perform(value, button: code)
            }
        }
    }

    private func perform(_ value: KeyBinding, button: UInt8, targetPID: pid_t? = nil) {
        guard AXIsProcessTrusted() else { return }
        if value.isFn {
            let wasHeld = mappedFn.held
            guard mappedFn.down() else {
                status = "Fn 已被按住或没有权限，本次未接管"
                return
            }
            fnButtons.insert(button)
            if !wasHeld { onFnChange?() }
        } else if value.kind == .text {
            let result = textInput.paste(value.text ?? "", allowed: { [weak self] in
                guard let self else { return false }
                return self.connected && self.activeShortcuts.contains(button) && self.canPerform()
            }, sendPaste: { [weak self] pid in
                self?.perform(.init(kind: .key, usage: 0x19, modifiers: CGEventFlags.maskCommand.rawValue), button: button, targetPID: pid)
            })
            actionFeedback = (result, Date().addingTimeInterval(5)); status = result
        } else if value.kind == .nextDisplay || value.kind == .nextWindow {
            desktop.perform(nextDisplay: value.kind == .nextDisplay, allowed: { [weak self] in
                guard let self else { return false }
                return self.connected && self.listenerOK && self.activeShortcuts.contains(button) && self.canPerform()
            }, completion: { [weak self] message in
                self?.actionFeedback = (message, Date().addingTimeInterval(5))
                self?.status = message
            })
        } else if value.isScroll {
            let vertical: Int32 = value.kind == .scrollUp ? 3 : value.kind == .scrollDown ? -3 : 0
            let horizontal: Int32 = value.kind == .scrollLeft ? 3 : value.kind == .scrollRight ? -3 : 0
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                    wheel1: vertical, wheel2: horizontal, wheel3: 0)?.post(tap: .cghidEventTap)
        } else if value.kind == .systemKey, let events = SystemControl(rawValue: value.usage)?.events() {
            for event in events {
                event.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
                event.post(tap: .cghidEventTap)
            }
        } else if value.kind == .openApp {
            guard let path = value.appPath, let url = Self.applicationURL(path) else {
                feedback("找不到所选应用，请重新选择应用并保存"); return
            }
            let generation = actionGeneration
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self, self.actionGeneration == generation else { return }
                    self.feedback(error == nil ? "已打开 \(url.deletingPathExtension().lastPathComponent)" : "无法打开所选应用，请检查应用是否可正常启动")
                }
            }
        } else if value.kind == .openURL, let url = value.webpageURL {
            feedback(NSWorkspace.shared.open(url) ? "已交给默认浏览器打开" : "无法打开网页，请检查默认浏览器")
        } else if value.kind == .key,
                  let events = Self.keyEvents(value, currentFlags: CGEventSource.flagsState(.combinedSessionState)) {
            for event in events {
                event.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
                if let targetPID { event.postToPid(targetPID) } else { event.post(tap: .cghidEventTap) }
            }
        }
    }

    static func applicationURL(_ path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return url
    }

    private func feedback(_ message: String) {
        actionFeedback = (message, Date().addingTimeInterval(5))
        status = message
    }

    // Build the entire shortcut before posting, including balanced Fn flagsChanged events.
    static func keyEvents(_ value: KeyBinding, currentFlags: CGEventFlags) -> [CGEvent]? {
        guard value.kind == .key, !value.isFn, let key = value.key else { return nil }
        let source = CGEventSource(stateID: .privateState)
        var flags = currentFlags
        let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63)]
            .filter { CGEventFlags(rawValue: value.modifiers).contains($0.0) && !flags.contains($0.0) }
        var events: [CGEvent] = []
        for (flag, code) in modifiers {
            flags.insert(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return nil }
            event.type = .flagsChanged; event.flags = flags; events.append(event)
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false) else { return nil }
        down.flags = flags; up.flags = flags
        events += [down, up]
        for (flag, code) in modifiers.reversed() {
            flags.remove(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return nil }
            event.type = .flagsChanged; event.flags = flags; events.append(event)
        }
        return events
    }

    // Once paste events are posted, let the short clipboard restore timer finish.
    func cancelPendingActions() {
        actionGeneration += 1
        desktop.cancel()
        gestureTimers.values.forEach { $0.invalidate() }
        gestureTimers.removeAll()
        gestures.reset()
    }

    func suspendActions() { releaseMappedFn(); cancelRepeats(); cancelPendingActions() }

    private func releaseMappedFn() {
        fnButtons.removeAll()
        guard mappedFn.held else { return }
        mappedFn.up()
        onFnChange?()
    }

    private func cancelRepeats() { repeats.values.forEach { $0.invalidate() }; repeats.removeAll() }

    private func stopListener() {
        releaseMappedFn()
        if manager != nil { cancelPendingActions() }
        cancelRepeats(); held.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        listenerOK = false
        activeShortcuts.removeAll()
    }

    func stop() {
        cancelPendingActions()
        textInput.stop()
        stopListener()
        for snapshot in snapshots.values {
            let current = IOHIDServiceClientCopyProperty(snapshot.service, property) as? HIDMappings ?? []
            let original = restored(current, snapshot: snapshot)
            if current != original { _ = IOHIDServiceClientSetProperty(snapshot.service, property, original as CFArray) }
        }
        snapshots.removeAll()
        connected = false
        status = "按键映射已停止"
    }
}
