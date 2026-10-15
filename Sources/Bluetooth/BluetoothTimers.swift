import Foundation

// Main-thread, one-shot deadlines for Bluetooth discovery and connection setup.
// Common modes let them run while an AppKit menu is tracking mouse/keyboard input.
final class BluetoothTimers {
    enum Kind: Hashable, CaseIterable { case scan, initialization, reconnect }
    private var timers: [Kind: Timer] = [:]

    func schedule(_ kind: Kind, after delay: TimeInterval, action: @escaping () -> Void) {
        cancel(kind)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] timer in
            guard let self, self.timers[kind] === timer else { return }
            // Remove before the callback so it can safely schedule the next attempt.
            self.timers.removeValue(forKey: kind)
            action()
        }
        timers[kind] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel(_ kind: Kind) { timers.removeValue(forKey: kind)?.invalidate() }

    func cancelAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    deinit { cancelAll() }
}
