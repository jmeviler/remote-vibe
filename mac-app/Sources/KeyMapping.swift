import AppKit
import IOKit.hid
import IOKit.hidsystem

struct MappingKey {
    let name: String
    let usage: UInt64
    let code: CGKeyCode
    static let all: [MappingKey] = [
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
      + [.init(name: "[", usage: 0x2F, code: 33), .init(name: "]", usage: 0x30, code: 30),
         .init(name: "/", usage: 0x38, code: 44), .init(name: "-", usage: 0x2D, code: 27),
         .init(name: "=", usage: 0x2E, code: 24), .init(name: ".", usage: 0x37, code: 47),
         .init(name: ",", usage: 0x36, code: 43), .init(name: ";", usage: 0x33, code: 41)]
}

struct KeyBinding: Codable, Equatable {
    enum Kind: String, Codable { case original, disabled, key, scrollUp, scrollDown, nextDisplay, nextWindow }
    var kind: Kind
    var usage: UInt64 = 0x28
    var modifiers: UInt64 = 0
    var usesListener: Bool {
        kind == .scrollUp || kind == .scrollDown || kind == .nextDisplay || kind == .nextWindow ||
        (kind == .key && (modifiers != 0 || usage == 0x29))
    }
    var key: MappingKey? { MappingKey.all.first { $0.usage == usage } }
    var title: String {
        switch kind {
        case .original: return "原按键功能"
        case .disabled: return "不执行"
        case .scrollUp: return "向上滚动"
        case .scrollDown: return "向下滚动"
        case .nextDisplay: return "切换屏幕"
        case .nextWindow: return "切换当前屏幕窗口"
        case .key:
            let flags = CGEventFlags(rawValue: modifiers)
            let prefix = [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
                .filter { flags.contains($0.0) }.map { $0.1 }.joined()
            return prefix + (key?.name ?? "Enter 回车")
        }
    }
}

struct MappedButton {
    let code: UInt8
    let name: String
    let usage: UInt64
    var initial: KeyBinding {
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
}

final class KeyMapping {
    typealias Bindings = [String: KeyBinding]
    private typealias HIDMappings = [[String: UInt64]]
    private struct Snapshot {
        let service: IOHIDServiceClient
        var original: HIDMappings
        var owned: HIDMappings = []
        var revision = -1
    }
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private let desktop = DesktopActions()
    private var actionFeedback: (text: String, until: Date)?
    private var manager: IOHIDManager?
    private var held = Set<UInt8>()
    private var repeats: [UInt8: Timer] = [:]
    private var snapshots: [UInt64: Snapshot] = [:]
    private var revision = 0
    private var activeShortcuts = Set<UInt8>()
    private let property = "UserKeyMapping" as CFString
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private(set) var bindings: Bindings
    private(set) var status = "等待遥控器连接"
    private(set) var connected = false
    private(set) var needsApply = false
    private var listenerOK = false
    var canPerform: () -> Bool = { true }
    var listening: Bool { manager != nil }
    var listeningAllowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    init() {
        if let data = UserDefaults.standard.data(forKey: "keyMappings.v1"),
           let stored = try? JSONDecoder().decode(Bindings.self, from: data) {
            let allowedFlags = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand]).rawValue
            bindings = stored.filter { code, b in
                MappedButton.all.contains { String($0.code) == code } &&
                (b.kind != .key || (b.key != nil && b.modifiers & ~allowedFlags == 0))
            }
        } else { bindings = [:] }
    }

    func binding(_ button: MappedButton) -> KeyBinding { bindings[String(button.code)] ?? button.initial }

    func save(_ values: Bindings) {
        cancelPendingActions()
        actionFeedback = nil
        bindings = values
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "keyMappings.v1") }
        cancelRepeats()
        revision += 1
        refresh()
    }

    func refresh() {
        let needsListener = MappedButton.all.contains { binding($0).usesListener }
        if needsListener && listeningAllowed && AXIsProcessTrusted() {
            if manager == nil { startListener() }
        } else { stopListener() }
        listenerOK = manager != nil && listeningAllowed && AXIsProcessTrusted()
        let entries: HIDMappings = MappedButton.all.compactMap { button in
            let value = binding(button)
            guard value.kind != .original else { return nil }
            // Unassigned usage suppresses a custom key even while permission is missing.
            let target = value.kind == .key && !value.usesListener ? value.usage : 0
            return [src: (UInt64(12) << 32) | button.usage, dst: (UInt64(7) << 32) | target]
        }
        let sources = Set(entries.compactMap { $0[src] })
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []).filter {
            (IOHIDServiceClientCopyProperty($0, "VendorID" as CFString) as? NSNumber)?.intValue == 6353 &&
            (IOHIDServiceClientCopyProperty($0, "ProductID" as CFString) as? NSNumber)?.intValue == 37968
        }
        if connected && services.isEmpty { cancelPendingActions() }
        connected = !services.isEmpty
        var present = Set<UInt64>()
        var applied = true
        needsApply = false
        activeShortcuts = listenerOK ? Set(MappedButton.all.filter { binding($0).usesListener }.map { $0.code }) : []
        for service in services {
            guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { continue }
            present.insert(id)
            var current = IOHIDServiceClientCopyProperty(service, property) as? HIDMappings ?? []
            var snapshot = snapshots[id] ?? Snapshot(service: service, original: current)
            // Apply only on connection or explicit save; never fight another remapper.
            if snapshot.revision != revision {
                snapshot.original = restored(current, snapshot: snapshot)
                snapshot.owned = entries
                let desired = snapshot.original.filter { !sources.contains($0[src] ?? 0) } + entries
                let ok = current == desired || IOHIDServiceClientSetProperty(service, property, desired as CFArray)
                current = IOHIDServiceClientCopyProperty(service, property) as? HIDMappings ?? []
                if ok && current == desired { snapshot.revision = revision }
                else { applied = false }
                snapshots[id] = snapshot
            }
            needsApply = needsApply || !entries.allSatisfy { current.contains($0) }
            // Emit a custom action only after its native action is confirmed suppressed.
            activeShortcuts = activeShortcuts.filter { code in
                guard let button = MappedButton.all.first(where: { $0.code == code }) else { return false }
                return current.contains([src: (UInt64(12) << 32) | button.usage, dst: UInt64(7) << 32])
            }
        }
        if !connected { activeShortcuts.removeAll(); cancelRepeats(); held.removeAll() }
        snapshots = snapshots.filter { present.contains($0.key) }
        status = !connected ? "设置已保存 · 等待遥控器连接" : !applied ? "按键设置未能生效，请检查权限" :
            needsApply ? "按键设置被其他程序更改 · 保存可重新应用" :
            needsListener && !listenerOK ? "Esc、组合键和桌面动作需要输入监控及辅助功能权限" : "按键已生效 · 重连后自动恢复"
        if connected && applied && !needsApply && (!needsListener || listenerOK),
           let feedback = actionFeedback, feedback.until > Date() { status = feedback.text }
    }

    private func restored(_ current: HIDMappings, snapshot: Snapshot) -> HIDMappings {
        let unchanged = snapshot.owned.filter { current.contains($0) }
        let sources = Set(unchanged.compactMap { $0[src] })
        return current.filter { !unchanged.contains($0) } + snapshot.original.filter { sources.contains($0[src] ?? 0) }
    }

    func requestListeningAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    private func startListener() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey:6353, kIOHIDProductIDKey:37968] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(m, { context, result, _, _, reportID, bytes, count in
            guard let context, result == kIOReturnSuccess, reportID == 1 else { return }
            let data = Array(UnsafeBufferPointer(start: bytes, count: count))
            let payload = data.count == 3 && data[0] == 1 ? Array(data.dropFirst()) : data
            guard payload.count == 2 else { return }
            Unmanaged<KeyMapping>.fromOpaque(context).takeUnretainedValue().handle(Set(payload.filter { $0 != 0 }))
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<KeyMapping>.fromOpaque(context).takeUnretainedValue().handle([])
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
        for code in added {
            guard let button = MappedButton.all.first(where: { $0.code == code }) else { continue }
            let value = binding(button)
            guard activeShortcuts.contains(code), canPerform() else { continue }
            perform(value, button: code)
            // Only scrolling repeats here; Esc, shortcuts and desktop actions fire once.
            if value.kind == .scrollUp || value.kind == .scrollDown {
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

    private func perform(_ value: KeyBinding, button: UInt8) {
        guard AXIsProcessTrusted() else { return }
        if value.kind == .nextDisplay || value.kind == .nextWindow {
            desktop.perform(nextDisplay: value.kind == .nextDisplay, allowed: { [weak self] in
                guard let self else { return false }
                return self.connected && self.listenerOK && self.activeShortcuts.contains(button) && self.canPerform()
            }, completion: { [weak self] message in
                self?.actionFeedback = (message, Date().addingTimeInterval(5))
                self?.status = message
            })
        } else if value.kind == .scrollUp || value.kind == .scrollDown {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                    wheel1: value.kind == .scrollUp ? 3 : -3, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        } else if value.kind == .key, let key = value.key {
            let source = CGEventSource(stateID: .privateState)
            var flags = CGEventSource.flagsState(.combinedSessionState)
            let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
                .filter { CGEventFlags(rawValue: value.modifiers).contains($0.0) && !flags.contains($0.0) }
            var events: [CGEvent] = []
            for (flag, code) in modifiers {
                flags.insert(flag)
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return }
                event.type = .flagsChanged; event.flags = flags; events.append(event)
            }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false) else { return }
            down.flags = flags; up.flags = flags
            events += [down, up]
            for (flag, code) in modifiers.reversed() {
                flags.remove(flag)
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
                event.type = .flagsChanged; event.flags = flags; events.append(event)
            }
            for event in events {
                event.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    func cancelPendingActions() { desktop.cancel() }

    private func cancelRepeats() { repeats.values.forEach { $0.invalidate() }; repeats.removeAll() }

    private func stopListener() {
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
