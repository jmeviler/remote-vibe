import AppKit

// Exercises timed input streams without posting keys or modifying HID mappings.
@main
enum ButtonGestureTest {
    private struct Fired: Equatable {
        let button: UInt8
        let trigger: ButtonTrigger
    }
    private struct TimerKey: Hashable {
        let button: UInt8
        let trigger: ButtonTrigger
    }
    private struct Remote {
        var recognizer = ButtonGestureRecognizer()
        var timers: [TimerKey: TimeInterval] = [:]
        var fired: [Fired] = []

        mutating func apply(_ commands: [ButtonGestureRecognizer.Command]) {
            for command in commands {
                switch command {
                case let .schedule(button, trigger, deadline): timers[.init(button: button, trigger: trigger)] = deadline
                case let .cancel(button, trigger): timers.removeValue(forKey: .init(button: button, trigger: trigger))
                case let .trigger(button, trigger): fired.append(.init(button: button, trigger: trigger))
                }
            }
        }
        mutating func down(_ button: UInt8 = 7, at time: TimeInterval, double: Bool = true, long: Bool = true) {
            apply(recognizer.press(button, doubleClick: double, longPress: long, at: time))
        }
        mutating func up(_ button: UInt8 = 7, at time: TimeInterval) { apply(recognizer.release(button, at: time)) }
        mutating func advance(_ time: TimeInterval) {
            while let (key, deadline) = timers.min(by: { $0.value < $1.value }), deadline <= time {
                timers.removeValue(forKey: key)
                apply(recognizer.timeout(key.button, trigger: key.trigger, at: deadline))
            }
        }
        mutating func cancel() { timers.removeAll(); recognizer.reset() }
        func expect(_ triggers: [ButtonTrigger], button: UInt8 = 7) {
            precondition(fired == triggers.map { Fired(button: button, trigger: $0) }, "Unexpected actions: \(fired)")
        }
    }

    static func main() throws {
        for profile in RemoteProfile.allCases {
            for button in MappedButton.buttons(for: profile) {
                var single = Remote()
                single.down(button.code, at: 0)
                single.up(button.code, at: 0.1)
                single.advance(0.399)
                single.expect([], button: button.code)
                single.advance(0.401)
                single.expect([.singleClick], button: button.code)
                precondition(single.timers.isEmpty)

                var double = Remote()
                double.down(button.code, at: 0)
                double.up(button.code, at: 0.1)
                double.down(button.code, at: 0.2)
                double.up(button.code, at: 0.25)
                double.advance(10)
                double.expect([.doubleClick], button: button.code)
                precondition(double.timers.isEmpty)

                var long = Remote()
                long.down(button.code, at: 0)
                long.down(button.code, at: 0.2) // Duplicate reports must not restart the threshold.
                long.advance(0.549)
                long.expect([], button: button.code)
                long.advance(0.551)
                long.expect([.longPress], button: button.code)
                long.down(button.code, at: 1)
                long.up(button.code, at: 2)
                long.advance(10)
                long.expect([.longPress], button: button.code)
                precondition(long.timers.isEmpty)
            }
        }

        var longOnly = Remote()
        longOnly.down(at: 0, double: false)
        longOnly.up(at: 0.1)
        longOnly.expect([.singleClick])
        longOnly.advance(10)
        longOnly.expect([.singleClick])

        var secondLong = Remote()
        secondLong.down(at: 0)
        secondLong.up(at: 0.1)
        secondLong.down(at: 0.2)
        secondLong.advance(1)
        secondLong.up(at: 1.1)
        secondLong.advance(10)
        secondLong.expect([.longPress])

        var delayed = Remote()
        delayed.down(at: 0)
        delayed.up(at: 0.1)
        delayed.down(at: 0.4) // Exactly at expiry, even if timer delivery was delayed.
        delayed.up(at: 0.5)
        delayed.advance(10)
        delayed.expect([.singleClick, .singleClick])

        var releaseBeforeTimer = Remote()
        releaseBeforeTimer.down(at: 0)
        releaseBeforeTimer.up(at: 0.55)
        releaseBeforeTimer.advance(10)
        releaseBeforeTimer.expect([.longPress])

        var triple = Remote()
        for time in [0.0, 0.15, 0.3] {
            triple.down(at: time)
            triple.up(at: time + 0.05)
        }
        triple.advance(10)
        triple.expect([.doubleClick, .singleClick])

        var separate = Remote()
        separate.down(3, at: 0)
        separate.up(3, at: 0.1)
        separate.down(4, at: 0.2)
        separate.advance(1)
        separate.up(4, at: 1.1)
        precondition(separate.fired == [.init(button: 3, trigger: .singleClick), .init(button: 4, trigger: .longPress)])

        for releaseFirst in [false, true] {
            var cancelled = Remote()
            cancelled.down(at: 0)
            if releaseFirst { cancelled.up(at: 0.1) }
            cancelled.cancel() // Disconnect, save, voice, lock, capture or profile change.
            cancelled.up(at: 0.2)
            cancelled.advance(10)
            cancelled.expect([])
            precondition(cancelled.timers.isEmpty)
            cancelled.down(at: 11)
            cancelled.up(at: 11.1)
            cancelled.advance(12)
            cancelled.expect([.singleClick])
        }

        var early = Remote()
        early.down(at: 0)
        early.apply(early.recognizer.timeout(7, trigger: .longPress, at: 0.2))
        early.expect([])
        early.advance(1)
        early.apply(early.recognizer.timeout(7, trigger: .longPress, at: 1))
        early.expect([.longPress])

        try MouseModeTests.run()
        try configurations()
        try actions()
        reports()
        print("PASS: gestures for all 26 buttons, v1 migration, Fn, HID reports and \(ActionCatalog.presets.count) action choices (events constructed, never posted).")
    }

    private static func configurations() throws {
        let old: [String: ButtonAction] = [
            "7": .init(kind: .key, usage: 0x29),
            "8": .init(kind: .key, usage: MappingKey.fnUsage),
            "11": .init(kind: .text, text: "你好\n🙂"),
            "14": .init(kind: .key, usage: 0x52, modifiers: CGEventFlags([.maskSecondaryFn, .maskShift]).rawValue)
        ]
        let migrated = try JSONDecoder().decode(KeyMapping.Bindings.self, from: JSONEncoder().encode(old))
        for (code, original) in old {
            precondition(migrated[code]?.singleClick == original && migrated[code]?.hasGestures == false)
            precondition(migrated[code]?.validationMessage == nil)
        }
        let fn = ButtonAction(kind: .key, usage: MappingKey.fnUsage)
        let configured = ButtonBinding(singleClick: .init(kind: .key), doubleClick: .init(kind: .text, text: "双击"), longPress: fn)
        precondition(configured.hasGestures && configured.usesListener && configured.validationMessage == nil)
        let data = try JSONEncoder().encode(configured)
        let decoded = try JSONDecoder().decode(ButtonBinding.self, from: data)
        let legacy = try JSONDecoder().decode(ButtonAction.self, from: data)
        precondition(decoded == configured && legacy == configured.singleClick)
        precondition(ButtonBinding(singleClick: .init(kind: .original), longPress: fn).validationMessage != nil)
        precondition(ButtonBinding(singleClick: fn, doubleClick: .init(kind: .disabled)).validationMessage != nil)
        precondition(ButtonBinding(singleClick: .init(kind: .key), doubleClick: fn).validationMessage != nil)
        precondition(ButtonBinding(singleClick: .init(kind: .disabled), longPress: fn).validationMessage == nil)
        for profile in RemoteProfile.allCases {
            for button in MappedButton.buttons(for: profile) {
                let plain = ButtonBinding(singleClick: button.initial)
                precondition(!plain.hasGestures && plain.usesListener == button.initial.usesListener)
            }
        }
        let voice = ButtonAction(kind: .remoteVoice)
        precondition(voice.requiresHold && voice.usesListener && !voice.isFn)
        precondition(voice.isValid && !ButtonAction(kind: .remoteVoice, modifiers: 1).isValid)
        let voiceHold = ButtonBinding(singleClick: voice)
        let voiceLong = ButtonBinding(singleClick: .init(kind: .key), longPress: voice)
        precondition(voiceHold.validationMessage(for: .chromecast) == nil)
        precondition(voiceLong.validationMessage(for: .chromecast) == nil)
        precondition(voiceHold.validationMessage(for: .xiaomiRC003) != nil)
        precondition(voiceLong.validationMessage(for: .xiaomiRC003) != nil)
        precondition(ButtonBinding(singleClick: voice, doubleClick: .init(kind: .disabled)).validationMessage != nil)
        precondition(ButtonBinding(singleClick: .init(kind: .disabled), doubleClick: voice).validationMessage != nil)
        let voiceDecoded = try JSONDecoder().decode(ButtonBinding.self, from: JSONEncoder().encode(voiceLong))
        precondition(voiceDecoded == voiceLong)
        precondition(RemoteProfile.chromecast.mappingKey != RemoteProfile.xiaomiRC003.mappingKey)
        // Construct balanced shortcuts without posting them to the session.
        let events = KeyMapping.keyEvents(old["14"]!, currentFlags: .maskCommand)!
        precondition(events.count == 6 && events.last?.flags == .maskCommand)
    }

    private static func reports() {
        for profile in RemoteProfile.allCases {
            for button in MappedButton.buttons(for: profile) {
                let report: [UInt8] = profile == .chromecast ? [button.code, 0] :
                    [UInt8(button.usage & 0xFF), UInt8(button.usage >> 8), 0, 0, 0, 0]
                precondition(MappedButton.pressed(reportID: 1, bytes: report, profile: profile) == [button.code])
                precondition(MappedButton.pressed(reportID: 1, bytes: [1] + report, profile: profile) == [button.code])
                precondition(MappedButton.pressed(reportID: 1, bytes: Array(repeating: 0, count: report.count), profile: profile) == [])
                precondition(MappedButton.pressed(reportID: 2, bytes: report, profile: profile) == nil)
            }
        }
        precondition(MappedButton.pressed(reportID: 1, bytes: [0x3E, 0, 0, 0, 0, 0], profile: .xiaomiRC003) == [])
    }

    private static func actions() throws {
        let presets = ActionCatalog.presets
        precondition(Set(presets.map(\.title)).count == presets.count)
        precondition(Set(MappingKey.all.map(\.usage)).count == MappingKey.all.count)
        for preset in presets {
            guard let value = preset.binding else { continue }
            precondition(value.isValid, "Invalid preset: \(preset.title)")
            if value.kind == .key && !value.isFn {
                for heldFlags: CGEventFlags in [[], .maskCommand, [.maskControl, .maskAlternate, .maskSecondaryFn]] {
                    let events = KeyMapping.keyEvents(value, currentFlags: heldFlags)!
                    let keyDown = events.filter { $0.type == .keyDown }
                    let keyUp = events.filter { $0.type == .keyUp }
                    precondition(keyDown.count == 1 && keyUp.count == 1)
                    precondition(keyDown[0].getIntegerValueField(.keyboardEventKeycode) == Int64(value.key!.code))
                    precondition(keyUp[0].getIntegerValueField(.keyboardEventKeycode) == Int64(value.key!.code))
                    precondition(keyDown[0].flags.contains(heldFlags.union(CGEventFlags(rawValue: value.modifiers))))
                    // Remove only modifiers added by this shortcut.
                    precondition(events.last!.flags == heldFlags)
                }
            }
        }
        for control in SystemControl.allCases {
            let events = control.events()!
            precondition(events.count == 2)
            for (index, event) in events.enumerated() {
                let native = NSEvent(cgEvent: event)!
                precondition(native.type == .systemDefined && native.subtype.rawValue == 8)
                precondition(native.data1 >> 16 == Int(control.rawValue))
                precondition((native.data1 >> 8) & 0xFF == (index == 0 ? 0xA : 0xB))
            }
        }
        for address in ["https://example.com/path?q=a%20b", "http://localhost:8000", " https://example.com "] {
            precondition(ButtonAction(kind: .openURL, url: address).configurationError == nil)
        }
        for address in ["", "example.com", "https://", "file:///etc/hosts", "javascript:alert(1)", "mailto:a@example.com"] {
            precondition(ButtonAction(kind: .openURL, url: address).configurationError != nil)
        }
        precondition(ButtonAction(kind: .openApp).configurationError != nil)
        precondition(KeyMapping.applicationURL("/bin/sh") == nil)
        precondition(KeyMapping.applicationURL("/missing.app") == nil)
        precondition(KeyMapping.applicationURL("relative.app") == nil)
        precondition(KeyMapping.applicationURL("/System/Applications/TextEdit.app") != nil)
        let targets = ButtonBinding(singleClick: .init(kind: .openApp, appPath: "/System/Applications/TextEdit.app"),
            doubleClick: .init(kind: .openURL, url: "https://example.com"),
            longPress: .init(kind: .systemKey, usage: SystemControl.playPause.rawValue))
        let decoded = try JSONDecoder().decode(ButtonBinding.self, from: JSONEncoder().encode(targets))
        precondition(decoded == targets && decoded.validationMessage == nil)
        precondition(MappingKey.all.filter { $0.name.hasPrefix("F") && Int($0.name.dropFirst()) != nil }.count == 20)
    }
}
