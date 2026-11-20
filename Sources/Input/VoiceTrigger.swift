import Foundation
import ApplicationServices

enum VoiceTriggerMode: String, Codable, CaseIterable {
    case hold
    case tapToggle

    var title: String {
        switch self {
        case .hold: return L("按住保持，松开释放")
        case .tapToggle: return L("点按开始，再点按结束")
        }
    }
}

enum VoiceTrigger: Equatable, Codable {
    case holdFn
    case holdRightOption
    case tapOptionSpace
    case none
    case custom(mode: VoiceTriggerMode, usage: UInt64, modifiers: UInt64)

    private enum CodingKeys: String, CodingKey {
        case kind, mode, usage, modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "holdFn": self = .holdFn
        case "holdRightOption": self = .holdRightOption
        case "tapOptionSpace": self = .tapOptionSpace
        case "none": self = .none
        case "custom":
            let mode = try container.decode(VoiceTriggerMode.self, forKey: .mode)
            let usage = try container.decode(UInt64.self, forKey: .usage)
            let modifiers = try container.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? 0
            let candidate = VoiceTrigger.custom(mode: mode, usage: usage, modifiers: modifiers).normalized
            guard candidate.isValid else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Invalid custom voice trigger")
            }
            self = candidate
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown voice trigger kind")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch normalized {
        case .holdFn:
            try container.encode("holdFn", forKey: .kind)
        case .holdRightOption:
            try container.encode("holdRightOption", forKey: .kind)
        case .tapOptionSpace:
            try container.encode("tapOptionSpace", forKey: .kind)
        case .none:
            try container.encode("none", forKey: .kind)
        case let .custom(mode, usage, modifiers):
            try container.encode("custom", forKey: .kind)
            try container.encode(mode, forKey: .mode)
            try container.encode(usage, forKey: .usage)
            try container.encode(modifiers, forKey: .modifiers)
        }
    }

    var normalized: VoiceTrigger {
        guard case let .custom(mode, usage, modifiers) = self else { return self }
        if usage == MappingKey.fnUsage && modifiers == 0 && mode == .hold { return .holdFn }
        if mode == .tapToggle && usage == 0x2C && modifiers == CGEventFlags.maskAlternate.rawValue { return .tapOptionSpace }
        return self
    }

    var isCustom: Bool {
        if case .custom = normalized { return true }
        return false
    }

    var requiresAccessibility: Bool {
        if case .none = normalized { return false }
        return true
    }

    var isValid: Bool {
        switch normalized {
        case .holdFn, .holdRightOption, .tapOptionSpace, .none:
            return true
        case let .custom(mode, usage, modifiers):
            let allowed = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]).rawValue
            guard modifiers & ~allowed == 0, MappingKey.all.contains(where: { $0.usage == usage }) else { return false }
            if usage == MappingKey.fnUsage { return modifiers == 0 && mode == .hold }
            return true
        }
    }

    var identifier: String {
        switch normalized {
        case .holdFn: return "wechat-hold-fn"
        case .holdRightOption: return "hold-right-option"
        case .tapOptionSpace: return "tap-option-space"
        case .none: return "audio-only"
        case .custom(.hold, _, _): return "custom-hold"
        case .custom(.tapToggle, _, _): return "custom-tap"
        }
    }

    var summaryTitle: String {
        switch normalized {
        case .holdFn: return L("按住 Fn（微信默认）")
        case .holdRightOption: return L("按住右 Option")
        case .tapOptionSpace: return L("点按 Option + Space 开始/结束")
        case .none: return L("仅送音（不发快捷键）")
        case let .custom(mode, usage, modifiers):
            let shortcut = ButtonAction(kind: .key, usage: usage, modifiers: modifiers).title
            return mode == .hold ? L("自定义按住：%@", shortcut) : L("自定义点按：%@", shortcut)
        }
    }
}

struct VoiceTimingProfile: Equatable {
    let preTriggerDelay: TimeInterval
    let preDrainDelay: TimeInterval
    let postDrainDelay: TimeInterval
    let postReleaseDelay: TimeInterval

    static func resolve(switchDefaultInput: Bool, fastTurnaround: Bool, trigger: VoiceTrigger) -> VoiceTimingProfile {
        if trigger.normalized == .none {
            return VoiceTimingProfile(
                preTriggerDelay: switchDefaultInput ? (fastTurnaround ? 0.05 : 0.10) : 0,
                preDrainDelay: 0.05,
                postDrainDelay: 0.05,
                postReleaseDelay: switchDefaultInput ? (fastTurnaround ? 0.25 : 0.40) : 0.05
            )
        }
        if !switchDefaultInput {
            return VoiceTimingProfile(
                preTriggerDelay: 0.02,
                preDrainDelay: fastTurnaround ? 0.25 : 0.45,
                postDrainDelay: fastTurnaround ? 0.10 : 0.15,
                postReleaseDelay: 0.10
            )
        }
        if fastTurnaround {
            return VoiceTimingProfile(
                preTriggerDelay: 0.08,
                preDrainDelay: 0.25,
                postDrainDelay: 0.10,
                postReleaseDelay: 0.35
            )
        }
        return VoiceTimingProfile(preTriggerDelay: 0.20, preDrainDelay: 0.55, postDrainDelay: 0.20, postReleaseDelay: 0.80)
    }
}

final class VoiceInputSettings {
    static let switchDefaultInputKey = "voice.switchDefaultInput.v1"
    static let fastTurnaroundKey = "voice.fastTurnaround.v1"
    static let triggerKey = "voice.trigger.v1"

    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    var switchDefaultInput: Bool {
        get { preferences.object(forKey: Self.switchDefaultInputKey) as? Bool ?? true }
        set { preferences.set(newValue, forKey: Self.switchDefaultInputKey) }
    }

    var fastTurnaround: Bool {
        get { preferences.bool(forKey: Self.fastTurnaroundKey) }
        set { preferences.set(newValue, forKey: Self.fastTurnaroundKey) }
    }

    var trigger: VoiceTrigger {
        get {
            guard let data = preferences.data(forKey: Self.triggerKey),
                  let decoded = try? JSONDecoder().decode(VoiceTrigger.self, from: data),
                  decoded.isValid else { return .holdFn }
            return decoded.normalized
        }
        set {
            let clean = newValue.normalized
            guard clean.isValid, let data = try? JSONEncoder().encode(clean) else { return }
            preferences.set(data, forKey: Self.triggerKey)
        }
    }

    var timing: VoiceTimingProfile {
        .resolve(switchDefaultInput: switchDefaultInput, fastTurnaround: fastTurnaround, trigger: trigger)
    }
}

final class VoiceTriggerController {
    private enum ActiveState {
        case none
        case heldFlag(keyCode: CGKeyCode, flag: CGEventFlags)
        case heldShortcut(keyCode: CGKeyCode, addedModifiers: [(CGEventFlags, CGKeyCode)], activeFlags: CGEventFlags)
        case toggledShortcut(action: ButtonAction)
    }

    private let isTrusted: () -> Bool
    private let flagsState: () -> CGEventFlags
    private let post: (CGEvent) -> Void
    private var state: ActiveState?

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         flagsState: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) },
         post: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.isTrusted = isTrusted
        self.flagsState = flagsState
        self.post = post
    }

    var active: Bool { state != nil }

    var fnHeld: Bool {
        switch state {
        case let .heldFlag(_, flag):
            return flag.contains(.maskSecondaryFn)
        case let .heldShortcut(_, addedModifiers, _):
            return addedModifiers.contains { $0.0 == .maskSecondaryFn }
        default:
            return false
        }
    }

    func activate(_ trigger: VoiceTrigger) -> Bool {
        guard state == nil else { return true }
        let normalized = trigger.normalized
        guard normalized.isValid else { return false }
        switch normalized {
        case .none:
            state = .none
            return true
        case .holdFn:
            return activateHeldFlag(keyCode: 63, flag: .maskSecondaryFn)
        case .holdRightOption:
            return activateHeldFlag(keyCode: 61, flag: .maskAlternate)
        case .tapOptionSpace:
            return activateTap(.init(kind: .key, usage: 0x2C, modifiers: CGEventFlags.maskAlternate.rawValue))
        case let .custom(mode, usage, modifiers):
            if usage == MappingKey.fnUsage {
                return activateHeldFlag(keyCode: 63, flag: .maskSecondaryFn)
            }
            let action = ButtonAction(kind: .key, usage: usage, modifiers: modifiers)
            if mode == .tapToggle {
                return activateTap(action)
            }
            return activateHoldShortcut(action)
        }
    }

    func deactivate() {
        guard let current = state else { return }
        state = nil
        switch current {
        case .none:
            break
        case let .heldFlag(keyCode, flag):
            postFlagEvent(keyCode: keyCode, flag: flag, down: false)
        case let .heldShortcut(keyCode, addedModifiers, activeFlags):
            let source = CGEventSource(stateID: .privateState)
            var flags = activeFlags
            var events: [CGEvent] = []
            if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                up.flags = flags
                events.append(up)
            }
            for (flag, code) in addedModifiers.reversed() {
                flags.remove(flag)
                if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                    event.type = .flagsChanged
                    event.flags = flags
                    events.append(event)
                }
            }
            for event in events {
                event.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
                post(event)
            }
        case let .toggledShortcut(action):
            guard let events = KeyMapping.keyEvents(action, currentFlags: flagsState()) else { return }
            for event in events {
                event.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
                post(event)
            }
        }
    }

    private func activateHeldFlag(keyCode: CGKeyCode, flag: CGEventFlags) -> Bool {
        guard isTrusted() else { return false }
        let current = flagsState()
        guard !current.contains(flag) else { return false }
        guard let event = makeFlagEvent(keyCode: keyCode, flag: flag, down: true, baseFlags: current) else { return false }
        state = .heldFlag(keyCode: keyCode, flag: flag)
        post(event)
        return true
    }

    private func activateTap(_ action: ButtonAction) -> Bool {
        guard isTrusted(), let events = KeyMapping.keyEvents(action, currentFlags: flagsState()) else { return false }
        state = .toggledShortcut(action: action)
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
            post(event)
        }
        return true
    }

    private func activateHoldShortcut(_ action: ButtonAction) -> Bool {
        guard isTrusted(), let key = action.key else { return false }
        let source = CGEventSource(stateID: .privateState)
        let current = flagsState()
        let modifiers: [(CGEventFlags, CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63)
        ].filter { CGEventFlags(rawValue: action.modifiers).contains($0.0) && !current.contains($0.0) }
        var flags = current
        var events: [CGEvent] = []
        for (flag, code) in modifiers {
            flags.insert(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return false }
            event.type = .flagsChanged
            event.flags = flags
            events.append(event)
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true) else { return false }
        down.flags = flags
        events.append(down)
        state = .heldShortcut(keyCode: key.code, addedModifiers: modifiers, activeFlags: flags)
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
            post(event)
        }
        return true
    }

    private func makeFlagEvent(keyCode: CGKeyCode, flag: CGEventFlags, down: Bool, baseFlags: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: down) else { return nil }
        event.type = .flagsChanged
        var flags = baseFlags
        if down { flags.insert(flag) } else { flags.remove(flag) }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
        return event
    }

    private func postFlagEvent(keyCode: CGKeyCode, flag: CGEventFlags, down: Bool) {
        guard let event = makeFlagEvent(keyCode: keyCode, flag: flag, down: down, baseFlags: flagsState()) else { return }
        post(event)
    }
}
