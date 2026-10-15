import Foundation
import CoreAudio

enum AudioDevices {
    static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
    static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static func defaultInput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }
    static func setDefaultInput(_ input: AudioDeviceID) -> Bool {
        var id = input
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr
    }
    static func mic() -> AudioDeviceID? {
        devices().first { string($0, kAudioDevicePropertyDeviceUID) == "RemoteVibeMic_UID" }
    }
}

// Hardware access stays outside the buffer/session logic so recovery can be tested
// without installing a driver, changing input devices or restarting coreaudiod.
protocol MicrophoneWriter: AnyObject {
    func start() -> Bool
    func stop()
    func dispose()
}

protocol MicrophoneHardware {
    func microphone() -> AudioDeviceID?
    func alive(_ device: AudioDeviceID) -> Bool
    func defaultInput() -> AudioDeviceID
    func uid(_ device: AudioDeviceID) -> String?
    func device(uid: String) -> AudioDeviceID?
    func setDefaultInput(_ device: AudioDeviceID) -> Bool
    func writer(_ device: AudioDeviceID, render: @escaping (UnsafeMutablePointer<AudioBufferList>) -> Void) -> MicrophoneWriter?
    func observe(_ changed: @escaping (_ serviceRestarted: Bool) -> Void) -> (() -> Void)?
}

private final class CoreAudioWriter: MicrophoneWriter {
    let device: AudioDeviceID
    private var proc: AudioDeviceIOProcID?
    init?(device: AudioDeviceID, render: @escaping (UnsafeMutablePointer<AudioBufferList>) -> Void) {
        self.device = device
        guard AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil, { _, _, _, output, _ in render(output) }) == noErr,
              let proc else { return nil }
        // Only write audio. WeChat owns the input stream.
        var usage = AudioHardwareIOProcStreamUsage(mIOProc: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), mNumberStreams: 1, mStreamIsOn: 0)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<AudioHardwareIOProcStreamUsage>.size), &usage) == noErr else {
            dispose(); return nil
        }
    }
    func start() -> Bool { proc.map { AudioDeviceStart(device, $0) == noErr } ?? false }
    func stop() { if let proc { AudioDeviceStop(device, proc) } }
    func dispose() { if let proc { AudioDeviceDestroyIOProcID(device, proc) }; proc = nil }
}

struct CoreMicrophoneHardware: MicrophoneHardware {
    func microphone() -> AudioDeviceID? { AudioDevices.mic() }
    func uid(_ device: AudioDeviceID) -> String? { AudioDevices.string(device, kAudioDevicePropertyDeviceUID) }
    func device(uid: String) -> AudioDeviceID? { AudioDevices.devices().first { self.uid($0) == uid } }
    func defaultInput() -> AudioDeviceID { AudioDevices.defaultInput() }
    func setDefaultInput(_ device: AudioDeviceID) -> Bool { AudioDevices.setDefaultInput(device) }
    func alive(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0 && uid(device) == "RemoteVibeMic_UID"
    }
    func writer(_ device: AudioDeviceID, render: @escaping (UnsafeMutablePointer<AudioBufferList>) -> Void) -> MicrophoneWriter? {
        CoreAudioWriter(device: device, render: render)
    }
    func observe(_ changed: @escaping (Bool) -> Void) -> (() -> Void)? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { count, addresses in
            changed((0..<Int(count)).contains { addresses[$0].mSelector == kAudioHardwarePropertyServiceRestarted })
        }
        var registered: [AudioObjectPropertyAddress] = []
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyServiceRestarted] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr { registered.append(address) }
        }
        guard !registered.isEmpty else { return nil }
        return { for var address in registered { AudioObjectRemovePropertyListenerBlock(system, &address, .main, block) } }
    }
}

final class VirtualMicrophone {
    private var device: AudioDeviceID?
    private var writer: MicrophoneWriter?
    private let hardware: MicrophoneHardware
    private let preferences: UserDefaults
    private var stopObserving: (() -> Void)?
    private var observationID = UUID()
    var onUnavailable: () -> Void = {}
    var onAvailabilityChange: () -> Void = {}
    private var running = false
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 48000 * 4)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var draining = false
    private var enabled = false
    private var rendered = 0
    private var fed = 0
    private var dropped = 0
    private var peakBuffered = 0
    private var priorUID: String?
    private var dcX: Float = 0
    private var dcY: Float = 0
    private var previousSample: Float = 0
    var available: Bool { device != nil }

    init(hardware: MicrophoneHardware = CoreMicrophoneHardware(), preferences: UserDefaults = .standard) {
        self.hardware = hardware; self.preferences = preferences
    }

    private func observe() {
        guard stopObserving == nil else { return }
        let id = observationID
        stopObserving = hardware.observe { [weak self] restarted in
            guard let self, self.observationID == id else { return }
            if restarted {
                // HAL resets invalidate listeners as well as IOProcs, even if IDs are reused.
                self.stopObserving?(); self.stopObserving = nil; self.observationID = UUID()
            }
            if let device = self.device, restarted || !self.hardware.alive(device) || self.hardware.microphone() != device {
                self.invalidateConnection()
            }
            _ = self.connect()
            if !self.running { self.recoverInput() }
            self.onAvailabilityChange()
        }
    }

    func connect() -> Bool {
        observe()
        if let device {
            if hardware.alive(device) { return true }
            invalidateConnection()
        }
        guard let id = hardware.microphone(), hardware.alive(id),
              let writer = hardware.writer(id, render: { [weak self] in self?.render($0) }) else { return false }
        device = id
        self.writer = writer
        recoverInput()
        return true
    }

    func begin() -> Bool {
        guard !running else { return false }
        // A stale IOProc can fail even while its device ID still resolves. Retry once
        // with a fresh writer; never replay an interrupted recording automatically.
        for _ in 0..<2 {
            guard connect(), let device, let writer else { return false }
            let original = hardware.defaultInput()
            priorUID = original != device ? hardware.uid(original) : nil
            if let priorUID { preferences.set(priorUID, forKey: "restoreInputUID") }
            guard hardware.setDefaultInput(device) else { invalidateConnection(); continue }
            prepareBuffer()
            if writer.start() { running = true; return true }
            invalidateConnection()
        }
        return false
    }

    private func prepareBuffer() {
        lock.lock()
        readIndex = 0; writeIndex = 0; count = 0
        rendered = 0; fed = 0; dropped = 0; peakBuffered = 0
        draining = false; enabled = true
        dcX = 0; dcY = 0; previousSample = 0
        lock.unlock()
    }

    func feed(_ samples: [Int16], rate: Int) {
        guard rate == 16000 || rate == 8000 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        let ratio = 48000 / rate
        for sample in samples {
            let x = Float(sample) / 32768
            let filtered = x - dcX + 0.995 * dcY
            dcX = x; dcY = filtered
            let value = max(-0.98, min(0.98, filtered * 2))
            for step in 1...ratio {
                let point = previousSample + (value - previousSample) * Float(step) / Float(ratio)
                if count == ring.count { readIndex = (readIndex + 1) % ring.count; count -= 1; dropped += 1 }
                ring[writeIndex] = point
                writeIndex = (writeIndex + 1) % ring.count
                count += 1; fed += 1
            }
            previousSample = value
        }
        peakBuffered = max(peakBuffered, count)
    }

    func startDraining() { lock.lock(); draining = true; lock.unlock() }
    var pendingFrames: Int { lock.lock(); defer { lock.unlock() }; return count }
    var renderedFrames: Int { lock.lock(); defer { lock.unlock() }; return rendered }
    var fedFrames: Int { lock.lock(); defer { lock.unlock() }; return fed }
    var bufferDiagnostics: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["peakBufferedFrames": peakBuffered, "droppedFrames": dropped]
    }

    private func render(_ output: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        for buffer in buffers { if let p = buffer.mData { memset(p, 0, Int(buffer.mDataByteSize)) } }
        guard lock.try() else { return }
        defer { lock.unlock() }
        guard enabled, draining, let first = buffers.first, let data = first.mData else { return }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let values = data.assumingMemoryBound(to: Float.self)
        let take = min(frames, count)
        for i in 0..<take {
            values[i] = ring[readIndex]
            readIndex = (readIndex + 1) % ring.count
        }
        count -= take
        rendered += take
    }

    func end() {
        lock.lock(); enabled = false; draining = false; count = 0; lock.unlock()
        if running { writer?.stop() }
        running = false
        recoverInput()
    }

    private func recoverInput() {
        let uid = priorUID ?? preferences.string(forKey: "restoreInputUID")
        let current = hardware.defaultInput(), currentUID = hardware.uid(current)
        if currentUID == "RemoteVibeMic_UID", let uid, let original = hardware.device(uid: uid) {
            if hardware.setDefaultInput(original) { preferences.removeObject(forKey: "restoreInputUID") }
        } else if current != 0, let currentUID, currentUID != "RemoteVibeMic_UID" {
            preferences.removeObject(forKey: "restoreInputUID")
        }
        priorUID = nil
    }

    func stop() {
        stopObserving?(); stopObserving = nil; observationID = UUID()
        disposeConnection()
    }

    private func disposeConnection() {
        end()
        writer?.dispose()
        writer = nil; device = nil
    }

    private func invalidateConnection() {
        let interrupted = running
        disposeConnection()
        if interrupted { onUnavailable() }
    }
}
