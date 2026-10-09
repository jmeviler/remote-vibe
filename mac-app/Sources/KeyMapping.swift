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
    enum Kind: String, Codable { case original, disabled, key, scrollUp, scrollDown }
    var kind: Kind
    var usage: UInt64 = 0x28
    var modifiers: UInt64 = 0
    var usesListener: Bool { kind == .scrollUp || kind == .scrollDown || (kind == .key && modifiers != 0) }
    var key: MappingKey? { MappingKey.all.first { $0.usage == usage } }
    var title: String {
        switch kind {
        case .original: return "原按键功能"
        case .disabled: return "不执行"
        case .scrollUp: return "向上滚动"
        case .scrollDown: return "向下滚动"
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
        let keys: [UInt8: UInt64] = [3:0x52, 4:0x51, 5:0x50, 6:0x4F, 7:0x28, 8:0x28, 11:0x2A]
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
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var manager: IOHIDManager?
    private var held = Set<UInt8>()
    private var repeats: [UInt8: Timer] = [:]
    private var snapshots: [UInt64: (service: IOHIDServiceClient, original: NSArray, applied: NSArray?)] = [:]
    private let property = "UserKeyMapping" as CFString
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private(set) var bindings: Bindings
    private(set) var status = "等待遥控器连接"
    private(set) var connected = false
    private var listenerOK = false
    var canPerform: () -> Bool = { true }
    var onPress: (UInt8) -> Void = { _ in }
    var listeningAllowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    init() {
        if let data = UserDefaults.standard.data(forKey: "keyMappings.v1"),
           let stored = try? JSONDecoder().decode(Bindings.self, from: data) {
            bindings = stored.filter { _, b in b.kind != .key || b.key != nil }
        } else { bindings = [:] }
    }

    func binding(_ button: MappedButton) -> KeyBinding { bindings[String(button.code)] ?? button.initial }

    func save(_ values: Bindings) {
        bindings = values
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "keyMappings.v1") }
        cancelRepeats()
        refresh()
    }

    func refresh() {
        let needsListener = MappedButton.all.contains { binding($0).usesListener }
        if listeningAllowed && manager == nil { startListener() }
        listenerOK = manager != nil && listeningAllowed && AXIsProcessTrusted()
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []).filter {
            (IOHIDServiceClientCopyProperty($0, "VendorID" as CFString) as? NSNumber)?.intValue == 6353 &&
            (IOHIDServiceClientCopyProperty($0, "ProductID" as CFString) as? NSNumber)?.intValue == 37968
        }
        connected = !services.isEmpty
        var present = Set<UInt64>()
        var applied = true
        for service in services {
            guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { continue }
            present.insert(id)
            let current = IOHIDServiceClientCopyProperty(service, property) as? NSArray ?? []
            if snapshots[id] == nil { snapshots[id] = (service, current, nil) }
            // Preserve unrelated mappings; only the listed physical buttons belong to this App.
            let owned = Set(MappedButton.all.map { (UInt64(12) << 32) | $0.usage })
            var entries = (snapshots[id]!.original as? [[String: UInt64]] ?? []).filter { !owned.contains($0[src] ?? 0) }
            for button in MappedButton.all {
                let value = binding(button)
                guard value.kind != .original else { continue }
                // No event (usage 0) suppresses native action for custom shortcuts/scrolling.
                // Keep the native function if permission for a custom action is missing.
                guard !value.usesListener || listenerOK else { continue }
                let target = value.kind == .key && !value.usesListener ? value.usage : 0
                entries.append([src: (UInt64(12) << 32) | button.usage, dst: (UInt64(7) << 32) | target])
            }
            let desired = entries as NSArray
            if !current.isEqual(desired) {
                let ok = IOHIDServiceClientSetProperty(service, property, desired)
                let readBack = IOHIDServiceClientCopyProperty(service, property) as? NSArray ?? []
                if ok && readBack.isEqual(desired) { snapshots[id]?.applied = desired }
                else { applied = false }
            } else { snapshots[id]?.applied = desired }
        }
        snapshots = snapshots.filter { present.contains($0.key) }
        status = !connected ? "设置已保存 · 等待遥控器连接" : !applied ? "按键设置未能生效，请检查权限" :
            needsListener && !listenerOK ? "基础按键已生效 · 组合快捷键需要输入监控和辅助功能权限" : "按键已生效 · 重连后自动恢复"
    }

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
            onPress(code)
            let value = binding(button)
            guard value.usesListener, listenerOK, canPerform() else { continue }
            perform(value)
            // Only scrolling repeats; Enter and modifier shortcuts execute once per press.
            if value.kind == .scrollUp || value.kind == .scrollDown {
                let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                    guard let self, self.held.contains(code), self.listenerOK, self.canPerform() else { return }
                    self.perform(value)
                }
                timer.fireDate = Date().addingTimeInterval(0.4)
                repeats[code] = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func perform(_ value: KeyBinding) {
        guard AXIsProcessTrusted() else { return }
        if value.kind == .scrollUp || value.kind == .scrollDown {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                    wheel1: value.kind == .scrollUp ? 3 : -3, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        } else if let key = value.key {
            let source = CGEventSource(stateID: .privateState)
            let flags = CGEventSource.flagsState(.combinedSessionState).union(CGEventFlags(rawValue: value.modifiers))
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false) else { return }
            down.flags = flags; up.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
            up.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
    }

    private func cancelRepeats() { repeats.values.forEach { $0.invalidate() }; repeats.removeAll() }

    func stop() {
        cancelRepeats(); held.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        for snapshot in snapshots.values {
            let current = IOHIDServiceClientCopyProperty(snapshot.service, property) as? NSArray ?? []
            // Do not undo changes made by another tool after our last application.
            if let applied = snapshot.applied, current.isEqual(applied) {
                _ = IOHIDServiceClientSetProperty(snapshot.service, property, snapshot.original)
            }
        }
        snapshots.removeAll()
    }
}
