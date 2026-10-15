import AppKit
import CoreFoundation

// Run the same timer owner used by BluetoothRemote without creating a central
// manager, touching preferences, discovering devices or opening a window.
@main
enum BluetoothTimersTest {
    static func wait(in mode: RunLoop.Mode = .eventTracking, until condition: () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.02))
        }
        precondition(condition(), "Timer did not complete in \(mode.rawValue)")
    }

    static func settle(in mode: RunLoop.Mode = .eventTracking) {
        var done = false
        let checkpoint = Timer(timeInterval: 0.04, repeats: false) { _ in done = true }
        RunLoop.main.add(checkpoint, forMode: mode)
        defer { checkpoint.invalidate() }
        wait(in: mode, until: { done })
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        trackingMode()
        cancellationAndReplacement()
        reentrantScheduling()
        shutdownAndRelease()
        print("PASS: Bluetooth scan/initialization/reconnect timers run in menu tracking mode; replacement, cancellation, shutdown and release suppress old callbacks (no Bluetooth access).")
    }

    private static func trackingMode() {
        let timers = BluetoothTimers()
        var calls: [BluetoothTimers.Kind] = []
        var defaultFired = false
        let defaultTimer = Timer(timeInterval: 0.005, repeats: false) { _ in defaultFired = true }
        RunLoop.main.add(defaultTimer, forMode: .default)
        defer { defaultTimer.invalidate() }
        for kind in BluetoothTimers.Kind.allCases {
            timers.schedule(kind, after: 0.005) { calls.append(kind) }
        }
        wait { calls.count == 3 }
        precondition(Set(calls) == Set(BluetoothTimers.Kind.allCases))
        // A default-mode timer stays paused here: this is the original bug.
        precondition(!defaultFired)
        wait(in: .default, until: { defaultFired })
        settle()
        precondition(calls.count == 3, "Bluetooth deadlines must be one-shot")
    }

    private static func cancellationAndReplacement() {
        for kind in BluetoothTimers.Kind.allCases {
            let timers = BluetoothTimers()
            var calls: [String] = []
            timers.schedule(kind, after: 0.005) { calls.append("cancelled") }
            timers.cancel(kind)
            // A cancelled callback must not reappear when the menu closes either.
            settle(); settle(in: .default)
            precondition(calls.isEmpty)
            timers.schedule(kind, after: 0.005) { calls.append("replaced") }
            timers.schedule(kind, after: 0.01) { calls.append("current") }
            wait { !calls.isEmpty }
            settle()
            precondition(calls == ["current"])
        }
        let timers = BluetoothTimers()
        var remaining: [BluetoothTimers.Kind] = []
        for kind in BluetoothTimers.Kind.allCases {
            timers.schedule(kind, after: 0.005) { remaining.append(kind) }
        }
        timers.cancel(.initialization)
        wait { remaining.count == 2 }
        precondition(Set(remaining) == [.scan, .reconnect], "Cancelling initialization must not cancel unrelated deadlines")
    }

    private static func reentrantScheduling() {
        let timers = BluetoothTimers()
        var attempts = 0
        timers.schedule(.reconnect, after: 0.005) {
            attempts += 1
            timers.schedule(.reconnect, after: 0.005) { attempts += 1 }
        }
        wait { attempts == 2 }
        settle()
        precondition(attempts == 2)
    }

    private static func shutdownAndRelease() {
        let timers = BluetoothTimers()
        var cancelledCalls = 0
        for kind in BluetoothTimers.Kind.allCases {
            timers.schedule(kind, after: 0.005) { cancelledCalls += 1 }
        }
        timers.cancelAll()
        settle(); settle(in: .default)
        precondition(cancelledCalls == 0, "Power-off/shutdown must cancel all deadlines")
        var fresh = false
        timers.schedule(.scan, after: 0.005) { fresh = true }
        wait { fresh }
        weak var released: BluetoothTimers?
        do {
            let owner = BluetoothTimers()
            released = owner
            for kind in BluetoothTimers.Kind.allCases {
                owner.schedule(kind, after: 0.005) { cancelledCalls += 1 }
            }
        }
        precondition(released == nil, "Run-loop timers must not retain their owner")
        settle(); settle(in: .default)
        precondition(cancelledCalls == 0, "Released connections must not leave timers running")
    }
}
