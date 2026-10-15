import AppKit
import CoreAudio

private final class FakeWriter: MicrophoneWriter {
    let render: (UnsafeMutablePointer<AudioBufferList>) -> Void
    let succeeds: Bool
    var starts = 0, stops = 0, disposals = 0
    init(succeeds: Bool, render: @escaping (UnsafeMutablePointer<AudioBufferList>) -> Void) {
        self.succeeds = succeeds; self.render = render
    }
    func start() -> Bool { starts += 1; return succeeds }
    func stop() { stops += 1 }
    func dispose() { disposals += 1 }
    func output(_ frames: Int) -> [Float] {
        var samples = [Float](repeating: .nan, count: frames)
        samples.withUnsafeMutableBytes { bytes in
            var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            withUnsafeMutablePointer(to: &buffers) { render($0) }
        }
        return samples
    }
}

private final class FakeHardware: MicrophoneHardware {
    var ids: [AudioDeviceID: String] = [1: "physical", 2: "other", 10: "RemoteVibeMic_UID"]
    var current: AudioDeviceID = 1
    var microphoneID: AudioDeviceID? = 10
    var startResults: [Bool] = []
    var routeAllowed = true
    var writers: [FakeWriter] = []
    var observers: [UUID: (Bool) -> Void] = [:]
    var registrations = 0
    func microphone() -> AudioDeviceID? { microphoneID }
    func alive(_ device: AudioDeviceID) -> Bool { device == microphoneID && ids[device] == "RemoteVibeMic_UID" }
    func defaultInput() -> AudioDeviceID { current }
    func uid(_ device: AudioDeviceID) -> String? { ids[device] }
    func device(uid: String) -> AudioDeviceID? { ids.first { $0.value == uid }?.key }
    func setDefaultInput(_ device: AudioDeviceID) -> Bool {
        guard routeAllowed, ids[device] != nil else { return false }
        current = device; return true
    }
    func writer(_ device: AudioDeviceID, render: @escaping (UnsafeMutablePointer<AudioBufferList>) -> Void) -> MicrophoneWriter? {
        let writer = FakeWriter(succeeds: startResults.isEmpty ? true : startResults.removeFirst(), render: render)
        writers.append(writer); return writer
    }
    func observe(_ changed: @escaping (Bool) -> Void) -> (() -> Void)? {
        let id = UUID(); observers[id] = changed; registrations += 1
        return { [weak self] in self?.observers.removeValue(forKey: id) }
    }
    func changed(restarted: Bool = false) { Array(observers.values).forEach { $0(restarted) } }
}

@main
enum AudioPipelineTest {
    static func main() {
        let suite = "RemoteVibe.AudioTests.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        buffers(prefs)
        recovery(prefs)
        routes(prefs)
        scheduling()
        print("PASS: audio writer recovery, bounded retry, listener renewal, route ownership, buffer drain/overflow, menu-mode cleanup and monotonic timing (fake hardware only).")
    }

    private static func buffers(_ prefs: UserDefaults) {
        let hardware = FakeHardware()
        let input = VirtualMicrophone(hardware: hardware, preferences: prefs)
        precondition(input.begin() && !input.begin())
        input.feed([1000, -1000, 3000, -3000], rate: 16000)
        let writer = hardware.writers[0]
        precondition(input.pendingFrames == 12 && input.fedFrames == 12)
        precondition(writer.output(12).allSatisfy { $0 == 0 } && input.pendingFrames == 12)
        input.startDraining()
        let samples = writer.output(12)
        precondition(samples.allSatisfy { $0.isFinite && abs($0) <= 0.98 } && samples.contains { $0 != 0 })
        precondition(input.pendingFrames == 0 && input.renderedFrames == 12)
        precondition(writer.output(12).allSatisfy { $0 == 0 })
        input.end()
        precondition(hardware.current == 1 && writer.stops == 1)
        precondition(input.begin())
        input.feed([1000], rate: 8000)
        precondition(input.pendingFrames == 6)
        input.end()
        precondition(input.begin())
        input.feed([Int16](repeating: 1200, count: 64001), rate: 16000)
        precondition(input.pendingFrames == 192000 && input.bufferDiagnostics["droppedFrames"] == 3)
        precondition(input.bufferDiagnostics["peakBufferedFrames"] == 192000)
        input.stop()
        precondition(input.pendingFrames == 0 && !input.available && hardware.observers.isEmpty)
        precondition(writer.output(16).allSatisfy { $0 == 0 })
    }

    private static func recovery(_ prefs: UserDefaults) {
        let hardware = FakeHardware()
        hardware.startResults = [false, true]
        let mic = VirtualMicrophone(hardware: hardware, preferences: prefs)
        var interruptions = 0
        mic.onUnavailable = { interruptions += 1 }
        precondition(mic.begin())
        precondition(hardware.writers.count == 2 && hardware.writers[0].disposals == 1 && interruptions == 0)
        // Service reset can reuse the exact same numeric device ID.
        let staleCallback = hardware.observers.values.first!
        hardware.changed(restarted: true)
        precondition(interruptions == 1 && mic.available && hardware.current == 1)
        precondition(hardware.writers[1].stops == 1 && hardware.writers[1].disposals == 1)
        precondition(hardware.writers.last!.starts == 0 && hardware.registrations == 2 && hardware.observers.count == 1)
        staleCallback(true)
        precondition(hardware.registrations == 2)
        precondition(mic.begin())
        hardware.ids.removeValue(forKey: 10); hardware.microphoneID = nil; hardware.current = 0
        hardware.changed()
        precondition(interruptions == 2 && !mic.available)
        precondition(prefs.string(forKey: "restoreInputUID") == "physical")
        hardware.ids[20] = "RemoteVibeMic_UID"; hardware.microphoneID = 20; hardware.current = 20
        hardware.changed()
        precondition(mic.available && hardware.current == 1 && hardware.writers.last!.starts == 0)
        precondition(mic.begin())
        mic.stop()
        precondition(hardware.current == 1 && hardware.observers.isEmpty)
        let failed = FakeHardware(); failed.startResults = [false, false, true]
        let unavailable = VirtualMicrophone(hardware: failed, preferences: prefs)
        precondition(!unavailable.begin() && !unavailable.available)
        precondition(failed.writers.count == 2 && failed.writers.allSatisfy { $0.disposals == 1 })
        precondition(failed.current == 1)
        precondition(unavailable.begin()) // Retry budget belongs to each user press.
        unavailable.stop()
        let denied = FakeHardware(); denied.routeAllowed = false
        let noRoute = VirtualMicrophone(hardware: denied, preferences: prefs)
        precondition(!noRoute.begin() && denied.writers.count == 2 && denied.current == 1)
        precondition(denied.writers.allSatisfy { $0.starts == 0 && $0.disposals == 1 })
        noRoute.stop()
    }

    private static func routes(_ prefs: UserDefaults) {
        let hardware = FakeHardware()
        let mic = VirtualMicrophone(hardware: hardware, preferences: prefs)
        precondition(mic.begin())
        hardware.current = 2 // Respect the user's selection during a recording.
        mic.end()
        precondition(hardware.current == 2 && prefs.string(forKey: "restoreInputUID") == nil)
        hardware.current = 1
        precondition(mic.begin())
        hardware.ids.removeValue(forKey: 1)
        mic.end()
        precondition(hardware.current == 10 && prefs.string(forKey: "restoreInputUID") == "physical")
        hardware.ids[3] = "physical" // Same UID, new ID after reconnect.
        hardware.changed()
        precondition(hardware.current == 3 && prefs.string(forKey: "restoreInputUID") == nil)
        mic.stop()
    }

    private static func pumpTracking(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { _ = RunLoop.main.run(mode: .eventTracking, before: deadline) }
    }
    private static func scheduling() {
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        var now: TimeInterval = 10
        let schedule = VoiceSessionSchedule(now: { now })
        var finished = 0, cleaned = false
        schedule.waitForDrain(ready: { true }) { timedOut in
            precondition(!timedOut); finished += 1
            schedule.after(0.001) { cleaned = true }
        }
        pumpTracking(0.15)
        precondition(finished == 1 && cleaned)
        schedule.waitForDrain(ready: { false }) { timedOut in precondition(timedOut); finished += 1 }
        now = 14.1
        pumpTracking(0.15)
        precondition(finished == 2)
        schedule.after(0.001) { preconditionFailure("Cancelled cleanup fired") }
        schedule.waitForDrain(ready: { true }) { _ in preconditionFailure("Cancelled drain fired") }
        schedule.cancel(); pumpTracking(0.08)
        var timing = VoiceSessionTiming()
        timing.begin(at: 10); timing.mark("firstSamples", at: 10.05); timing.mark("firstSamples", at: 11)
        timing.finish(at: 12, cancelled: false); timing.mark("late", at: 13)
        let points = timing.diagnostics["millisecondsFromAudioStart"] as! [String: Int]
        precondition(points == ["firstSamples": 50, "finished": 2000] && timing.outcome == "completed")
        timing.begin(at: 20); timing.finish(at: 20.1, cancelled: true)
        precondition(timing.outcome == "cancelled")
    }
}
