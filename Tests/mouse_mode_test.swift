import AppKit

// Exercise timing and event construction with injected pointer/display/event
// sinks. No HID devices, preference writes, or synthetic input reaches macOS.
enum MouseModeTests {
    static func run() throws {
        var mode = MouseModeState()
        precondition(!mode.active && mode.pending == nil)
        mode.requestToggle()
        mode.requestToggle() // Duplicate reports do not undo a pending transition.
        precondition(!mode.applyIfReleased([3, 14]) && !mode.active)
        precondition(!mode.applyIfReleased([3]))
        precondition(mode.applyIfReleased([]) && mode.active)
        precondition(!mode.applyIfReleased([]))
        mode.requestToggle(); mode.cancelPending()
        precondition(mode.active && !mode.applyIfReleased([]))
        mode.requestToggle()
        precondition(mode.applyIfReleased([]) && !mode.active)
        mode.requestToggle(); mode.reset()
        precondition(!mode.applyIfReleased([]) && !mode.active)
        mode.requestToggle(); _ = mode.applyIfReleased([])
        precondition(mode.reset() && !mode.active && !mode.reset())

        for profile in RemoteProfile.allCases {
            let buttons = MappedButton.buttons(for: profile)
            let toggle = buttons.first { $0.code == 10 }!
            let direction = buttons.first { $0.code == 3 }!
            let normal: KeyMapping.Bindings = ["10": .init(singleClick: .init(kind: .toggleMouseMode)),
                                               "3": .init(singleClick: .init(kind: .key, usage: 0x52))]
            let mouse: KeyMapping.Bindings = ["10": .init(singleClick: .init(kind: .mouseLeftClick)),
                                              "3": .init(singleClick: .init(kind: .mouseRight))]
            precondition(KeyMapping.binding(toggle, normal: normal, mouse: mouse, inMouseMode: true).togglesMouseMode)
            precondition(KeyMapping.binding(direction, normal: normal, mouse: mouse, inMouseMode: true).singleClick.kind == .mouseRight)
            precondition(KeyMapping.binding(direction, normal: normal, mouse: mouse, inMouseMode: false) == normal["3"])
            precondition(KeyMapping.binding(direction, normal: normal, mouse: [:], inMouseMode: true).singleClick.kind == .mouseUp)
            for code: UInt8 in [3, 4, 5, 6] { precondition(KeyMapping.mouseDefault(code).isMouseMovement) }
            precondition(KeyMapping.mouseDefault(7).kind == .mouseLeftClick)
            precondition(KeyMapping.mouseDefault(11).kind == .mouseRightClick)
            precondition(profile.mouseMappingKey != profile.mappingKey)
            for bindings in [normal, mouse] {
                let data = try JSONEncoder().encode(bindings)
                let decoded = try JSONDecoder().decode(KeyMapping.Bindings.self, from: data)
                precondition(decoded == bindings)
            }
        }
        precondition(RemoteProfile.chromecast.mouseMappingKey != RemoteProfile.xiaomiRC003.mouseMappingKey)
        let move = ButtonAction(kind: .mouseUp), toggle = ButtonAction(kind: .toggleMouseMode)
        precondition(move.requiresHold && move.usesListener && toggle.usesListener)
        precondition(ButtonBinding(singleClick: move).validationMessage == nil)
        precondition(ButtonBinding(singleClick: move, doubleClick: .init(kind: .mouseLeftClick)).validationMessage != nil)
        precondition(ButtonBinding(singleClick: .init(kind: .disabled), longPress: move).validationMessage == nil)
        precondition(ButtonBinding(singleClick: .init(kind: .disabled), doubleClick: move).validationMessage != nil)
        precondition(ButtonBinding(singleClick: toggle, longPress: move).validationMessage == nil)
        precondition(ButtonBinding(singleClick: .init(kind: .disabled), longPress: toggle).validationMessage == nil)
        precondition(ButtonBinding(singleClick: toggle).validationMessage == nil)

        try toggleGestures()

        var point = CGPoint(x: 500, y: 500)
        var now = 0.0, permitted = true
        var events: [CGEvent] = []
        let pointer = MousePointer(position: { point }, screens: { [CGRect(x: 0, y: 0, width: 2000, height: 1500)] },
            post: { events.append($0); point = $0.location }, clock: { now })
        pointer.press(3, direction: .mouseUp, allowed: { permitted })
        precondition(pointer.moving && point == CGPoint(x: 500, y: 497))
        pointer.press(3, direction: .mouseUp, allowed: { permitted })
        precondition(events.count == 1)
        now = 1.0 / 60; pointer.tick()
        precondition(point.y < 497 && point.x == 500)
        let slowDistance = 497 - point.y
        let previous = point
        now = 0.8; pointer.tick() // Delayed callback is bounded, not a giant jump.
        precondition(previous.y - point.y > slowDistance && previous.y - point.y <= 30.001)
        pointer.release(3)
        precondition(!pointer.moving)
        let stopped = events.count
        now = 2; pointer.tick(); pointer.release(3)
        precondition(events.count == stopped)

        point = CGPoint(x: 500, y: 500)
        pointer.press(3, direction: .mouseUp, allowed: { permitted })
        pointer.press(6, direction: .mouseRight, allowed: { permitted })
        let diagonalStart = point
        now += 1.0 / 60; pointer.tick()
        precondition(abs((point.x - diagonalStart.x) + (point.y - diagonalStart.y)) < 0.001)
        pointer.release(3)
        let horizontalStart = point
        now += 1.0 / 60; pointer.tick()
        precondition(point.x > horizontalStart.x && point.y == horizontalStart.y)
        pointer.press(5, direction: .mouseLeft, allowed: { permitted })
        let oppositeStart = point
        now += 1.0 / 60; pointer.tick()
        precondition(point == oppositeStart)
        permitted = false; pointer.tick()
        precondition(!pointer.moving)
        let cancelled = events.count
        permitted = true; now += 1; pointer.tick()
        precondition(events.count == cancelled) // Permission/voice recovery must not restart an old hold.
        pointer.press(6, direction: .mouseRight, allowed: { permitted })
        precondition(pointer.moving)
        pointer.stop(); pointer.release(6)
        precondition(!pointer.moving)

        let screens = [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 2560, height: 1440)]
        precondition(MousePointer.clamped(CGPoint(x: -1919, y: 40), screens: screens) == CGPoint(x: -1919, y: 40))
        precondition(MousePointer.clamped(CGPoint(x: -9999, y: 40), screens: screens) == CGPoint(x: -1920, y: 40))
        precondition(MousePointer.clamped(CGPoint(x: 9999, y: 9999), screens: screens) == CGPoint(x: 2559, y: 1439))
        precondition(MousePointer.clamped(.zero, screens: []) == nil)
        for right in [false, true] {
            let click = MousePointer.clickEvents(right: right, point: point)!
            precondition(click.count == 2 && click[0].type == (right ? .rightMouseDown : .leftMouseDown))
            precondition(click[1].type == (right ? .rightMouseUp : .leftMouseUp))
            precondition(click.allSatisfy { $0.location == point && $0.getIntegerValueField(.mouseEventClickState) == 1 })
        }
        pointer.click(right: false)
        pointer.release(7) // Releasing the remote click key must preserve double-click timing.
        now += NSEvent.doubleClickInterval / 2
        pointer.click(right: false)
        precondition(events.last!.getIntegerValueField(.mouseEventClickState) == 2)
        now += NSEvent.doubleClickInterval + 0.1
        pointer.click(right: false)
        precondition(events.last!.getIntegerValueField(.mouseEventClickState) == 1)
        pointer.click(right: true)
        precondition(events.last!.type == .rightMouseUp && events.last!.getIntegerValueField(.mouseEventClickState) == 1)
        precondition(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == 0x524D564B })
        print("PASS: mouse-mode transitions, independent bindings, balanced clicks, double-click timing, acceleration, diagonal movement, display bounds and cancellation (no input posted).")
    }
    private static func toggleGestures() throws {
        let toggle = ButtonAction(kind: .toggleMouseMode)
        for trigger in ButtonTrigger.allCases {
            var binding = ButtonBinding(singleClick: .init(kind: .key, usage: 0x28))
            binding[trigger] = toggle
            precondition(binding.validationMessage == nil && binding.togglesMouseMode)
            precondition(binding.immediateMouseToggle == (trigger == .singleClick))
            let decoded = try JSONDecoder().decode(ButtonBinding.self, from: JSONEncoder().encode(binding))
            precondition(decoded == binding)
            for profile in RemoteProfile.allCases {
                let button = MappedButton.buttons(for: profile).first { $0.code == 10 }!
                let resolved = KeyMapping.binding(button, normal: ["10": binding], mouse: ["10": .init(singleClick: .init(kind: .mouseLeftClick))], inMouseMode: true)
                precondition(resolved == binding) // The same gesture must always exit.
            }
        }
        let combined = ButtonBinding(singleClick: toggle, doubleClick: .init(kind: .key), longPress: toggle)
        precondition(combined.validationMessage == nil && !combined.immediateMouseToggle)

        // Feed the actual recognizer into the mode state: double click switches
        // once on release; long press waits for release and never adds a click.
        for trigger in [ButtonTrigger.doubleClick, .longPress] {
            var gestures = ButtonGestureRecognizer()
            var mode = MouseModeState()
            var held = Set<UInt8>()
            var transitions = 0
            func apply(_ commands: [ButtonGestureRecognizer.Command]) {
                for command in commands {
                    if case let .trigger(_, fired) = command, fired == trigger {
                        mode.requestToggle()
                        if mode.applyIfReleased(held) { transitions += 1 }
                    }
                }
            }
            for cycle in 0..<2 {
                let base = Double(cycle) * 2
                held = [10]
                apply(gestures.press(10, doubleClick: trigger == .doubleClick, longPress: trigger == .longPress, at: base))
                precondition(transitions == cycle)
                if trigger == .doubleClick {
                    held = []; apply(gestures.release(10, at: base + 0.05))
                    precondition(transitions == cycle)
                    held = [10]; apply(gestures.press(10, doubleClick: true, longPress: false, at: base + 0.1))
                    held = []; apply(gestures.release(10, at: base + 0.15))
                } else {
                    apply(gestures.timeout(10, trigger: .longPress, at: base + 0.56))
                    precondition(mode.pending != nil && transitions == cycle)
                    held = []; apply(gestures.release(10, at: base + 0.6))
                    if mode.applyIfReleased(held) { transitions += 1 }
                }
                precondition(transitions == cycle + 1 && mode.active == (cycle == 0))
                apply(gestures.timeout(10, trigger: .singleClick, at: base + 1))
                precondition(transitions == cycle + 1)
            }
        }
    }

}
