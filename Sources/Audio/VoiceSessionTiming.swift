import Foundation

// One session's milestones, measured from ATVV AUDIO_START (not a physical key
// timestamp or a WeChat acknowledgement). Never stores audio or recognized text.
struct VoiceSessionTiming {
    private var started: TimeInterval?
    private var milestones: [String: Int] = [:]
    private(set) var outcome = "idle"

    mutating func begin(at now: TimeInterval) {
        started = now; milestones = [:]; outcome = "active"
    }
    mutating func mark(_ name: String, at now: TimeInterval) {
        guard let started, milestones[name] == nil, outcome == "active" else { return }
        milestones[name] = Int((max(0, now - started) * 1000).rounded())
    }
    mutating func finish(at now: TimeInterval, cancelled: Bool) {
        guard outcome == "active" else { return }
        mark("finished", at: now)
        outcome = cancelled ? "cancelled" : "completed"
    }
    var diagnostics: [String: Any] { ["outcome": outcome, "millisecondsFromAudioStart": milestones] }
}

// Common-mode timers keep voice preparation and cleanup moving while the menu
// is open. Cancellation also covers the delayed Fn and input-device cleanup.
final class VoiceSessionSchedule {
    private let now: () -> TimeInterval
    private var timers: [Timer] = []
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func after(_ delay: TimeInterval, action: @escaping () -> Void) {
        add(Timer(timeInterval: delay, repeats: false) { _ in action() })
    }
    func waitForDrain(ready: @escaping () -> Bool, completion: @escaping (_ timedOut: Bool) -> Void) {
        let started = now()
        add(Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let drained = ready()
            if drained || self.now() - started >= 4 {
                timer.invalidate()
                completion(!drained)
            }
        })
    }
    private func add(_ timer: Timer) {
        timers.removeAll { !$0.isValid }
        timers.append(timer)
        RunLoop.main.add(timer, forMode: .common)
    }
    func cancel() { timers.forEach { $0.invalidate() }; timers.removeAll() }
    deinit { cancel() }
}
