import Foundation

enum ButtonTrigger: String, CaseIterable {
    case singleClick, doubleClick, longPress

    var title: String {
        switch self {
        case .singleClick: return "单击"
        case .doubleClick: return "双击"
        case .longPress: return "长按"
        }
    }
}

// Gesture transitions adapted from SayAll's RemoteButtonGestureRecognizer,
// GPL-3.0-only. See THIRD_PARTY_NOTICES.md. Timing is monotonic and injected so
// delayed run-loop callbacks cannot extend the double-click window.
struct ButtonGestureRecognizer {
    static let doubleClickInterval: TimeInterval = 0.3
    static let longPressInterval: TimeInterval = 0.55

    enum Command: Equatable {
        case schedule(UInt8, ButtonTrigger, TimeInterval)
        case cancel(UInt8, ButtonTrigger)
        case trigger(UInt8, ButtonTrigger)
    }

    private struct State {
        var pressedAt: TimeInterval?
        var singleDeadline: TimeInterval?
        var secondPress = false
        var longTriggered = false
        let doubleClick: Bool
        let longPress: Bool
    }
    private var states: [UInt8: State] = [:]

    mutating func press(_ button: UInt8, doubleClick: Bool, longPress: Bool, at now: TimeInterval) -> [Command] {
        var commands: [Command] = []
        if var state = states[button] {
            guard let deadline = state.singleDeadline else { return [] } // repeated HID report
            commands.append(.cancel(button, .singleClick))
            if now < deadline {
                state.pressedAt = now
                state.singleDeadline = nil
                state.secondPress = true
                states[button] = state
                if state.longPress { commands.append(.schedule(button, .longPress, now + Self.longPressInterval)) }
                return commands
            }
            commands.append(.trigger(button, .singleClick))
        }
        states[button] = State(pressedAt: now, doubleClick: doubleClick, longPress: longPress)
        if longPress { commands.append(.schedule(button, .longPress, now + Self.longPressInterval)) }
        return commands
    }

    mutating func release(_ button: UInt8, at now: TimeInterval) -> [Command] {
        guard var state = states[button], let pressedAt = state.pressedAt else { return [] }
        var commands: [Command] = state.longPress ? [.cancel(button, .longPress)] : []
        states.removeValue(forKey: button)
        if state.longTriggered { return commands }
        // The release may arrive before a delayed long-press timer callback.
        if state.longPress && now >= pressedAt + Self.longPressInterval {
            commands.append(.trigger(button, .longPress))
        } else if state.secondPress {
            commands.append(.trigger(button, .doubleClick))
        } else if state.doubleClick {
            state.pressedAt = nil
            state.singleDeadline = now + Self.doubleClickInterval
            states[button] = state
            commands.append(.schedule(button, .singleClick, now + Self.doubleClickInterval))
        } else {
            commands.append(.trigger(button, .singleClick))
        }
        return commands
    }

    mutating func timeout(_ button: UInt8, trigger: ButtonTrigger, at now: TimeInterval) -> [Command] {
        guard var state = states[button] else { return [] }
        if trigger == .singleClick, let deadline = state.singleDeadline {
            guard now >= deadline else { return [.schedule(button, trigger, deadline)] }
            states.removeValue(forKey: button)
            return [.trigger(button, .singleClick)]
        }
        if trigger == .longPress, let pressedAt = state.pressedAt, state.longPress, !state.longTriggered {
            let deadline = pressedAt + Self.longPressInterval
            guard now >= deadline else { return [.schedule(button, trigger, deadline)] }
            state.longTriggered = true
            states[button] = state
            return [.trigger(button, .longPress)]
        }
        return []
    }

    mutating func reset() { states.removeAll() }
}
