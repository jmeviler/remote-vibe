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
    func driverBuildVersion() -> Int?
}

extension MicrophoneHardware {
    func driverBuildVersion() -> Int? { VirtualMicrophone.expectedDriverBuild }
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
    func driverBuildVersion() -> Int? {
        guard let dict = NSDictionary(contentsOfFile: VirtualMicrophone.driverInfoPlistPath),
              let raw = dict["CFBundleVersion"] as? String else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

final class VirtualMicrophone {
    static let expectedDriverBuild = 1
    static let driverInfoPlistPath = "/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver/Contents/Info.plist"
    private var device: AudioDeviceID?
    private var writer: MicrophoneWriter?
    private let hardware: MicrophoneHardware
    private let preferences: UserDefaults
    private var stopObserving: (() -> Void)?
    private var observationID = UUID()
    var onUnavailable: () -> Void = {}
    var onAvailabilityChange: () -> Void = {}
    private var running = false
    private let ring: UnsafeMutablePointer<RVAudioRing>
    private let producerLock = NSLock()
    private var scratch: [Float] = []
    private var priorUID: String?
    private var dcX: Float = 0
    private var dcY: Float = 0
    private var historyPrev: Float = 0
    private var previousSample: Float = 0
    var available: Bool { device != nil }
    var driverNeedsUpdate: Bool {
        available && (hardware.driverBuildVersion() ?? Self.expectedDriverBuild) < Self.expectedDriverBuild
    }

    init(hardware: MicrophoneHardware = CoreMicrophoneHardware(), preferences: UserDefaults = .standard) {
        guard let allocated = RVAudioRingCreate() else { fatalError("Unable to allocate audio ring buffer") }
        self.ring = allocated
        self.hardware = hardware; self.preferences = preferences
        scratch.reserveCapacity(1536)
    }

    deinit {
        RVAudioRingDestroy(ring)
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

    func begin(switchDefaultInput: Bool = true) -> Bool {
        guard !running else { return false }
        // A stale IOProc can fail even while its device ID still resolves. Retry once
        // with a fresh writer; never replay an interrupted recording automatically.
        for _ in 0..<2 {
            guard connect(), let device, let writer else { return false }
            if switchDefaultInput {
                let original = hardware.defaultInput()
                priorUID = original != device ? hardware.uid(original) : nil
                if let priorUID { preferences.set(priorUID, forKey: "restoreInputUID") }
                guard hardware.setDefaultInput(device) else { invalidateConnection(); continue }
            } else {
                priorUID = nil
            }
            prepareBuffer()
            if writer.start() { running = true; return true }
            invalidateConnection()
        }
        return false
    }

    private func prepareBuffer() {
        producerLock.lock()
        dcX = 0; dcY = 0; historyPrev = 0; previousSample = 0
        scratch.removeAll(keepingCapacity: true)
        RVAudioRingPrepare(ring)
        producerLock.unlock()
    }

    func feed(_ samples: [Int16], rate: Int) {
        guard rate == 16000 || rate == 8000, !samples.isEmpty else { return }
        producerLock.lock()
        defer { producerLock.unlock() }
        let ratio = 48000 / rate
        scratch.removeAll(keepingCapacity: true)
        for sample in samples {
            let x = Float(sample) / 32768
            let filtered = x - dcX + 0.995 * dcY
            dcX = x; dcY = filtered
            let value = 0.98 * tanhf((filtered * 2) / 0.98)
            let p0 = previousSample
            let p1 = value
            let m0 = 0.5 * (p1 - historyPrev)
            let m1 = p1 - p0
            for step in 1...ratio {
                let t = Float(step) / Float(ratio)
                let t2 = t * t
                let t3 = t2 * t
                let cubic = (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1
                scratch.append(max(-0.98, min(0.98, cubic)))
                if scratch.count >= 1536 {
                    scratch.withUnsafeBufferPointer { buffer in
                        if let base = buffer.baseAddress { RVAudioRingWrite(ring, base, UInt32(buffer.count)) }
                    }
                    scratch.removeAll(keepingCapacity: true)
                }
            }
            historyPrev = p0
            previousSample = p1
        }
        if !scratch.isEmpty {
            scratch.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress { RVAudioRingWrite(ring, base, UInt32(buffer.count)) }
            }
            scratch.removeAll(keepingCapacity: true)
        }
    }

    func startDraining() { RVAudioRingStartDraining(ring) }
    var pendingFrames: Int { Int(RVAudioRingPendingFrames(ring)) }
    var renderedFrames: Int { Int(RVAudioRingRenderedFrames(ring)) }
    var fedFrames: Int { Int(RVAudioRingFedFrames(ring)) }
    var bufferDiagnostics: [String: Int] {
        ["peakBufferedFrames": Int(RVAudioRingPeakBuffered(ring)), "droppedFrames": Int(RVAudioRingDroppedFrames(ring))]
    }

    private func render(_ output: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        for buffer in buffers { if let p = buffer.mData { memset(p, 0, Int(buffer.mDataByteSize)) } }
        guard let first = buffers.first, let data = first.mData else { return }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frames > 0 else { return }
        let values = data.assumingMemoryBound(to: Float.self)
        _ = RVAudioRingRender(ring, values, UInt32(frames))
    }

    func end() {
        RVAudioRingStop(ring)
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
