import Foundation
import ApplicationServices

final class FnKey {
    private(set) var held = false
    func down() -> Bool {
        guard AXIsProcessTrusted(), !held else { return held }
        let current = CGEventSource.flagsState(.combinedSessionState)
        guard !current.contains(.maskSecondaryFn) else { return false }
        held = true
        post(down: true)
        return true
    }
    func up() { guard held else { return }; post(down: false); held = false }
    private func post(down: Bool) {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 63, keyDown: down)
        event?.type = .flagsChanged
        var flags = CGEventSource.flagsState(.combinedSessionState)
        if down { flags.insert(.maskSecondaryFn) } else { flags.remove(.maskSecondaryFn) }
        event?.flags = flags
        event?.setIntegerValueField(.eventSourceUserData, value: 0x524D5642)
        event?.post(tap: .cghidEventTap)
    }
}

