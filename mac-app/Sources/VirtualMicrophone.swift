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

final class VirtualMicrophone {
    private var device: AudioDeviceID?
    private var ioProc: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 48000 * 4)
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var draining = false
    private var enabled = false
    private var rendered = 0
    private var fed = 0
    private var priorUID: String?
    private var dcX: Float = 0
    private var dcY: Float = 0
    private var previousSample: Float = 0
    var available: Bool { device != nil }

    func connect() -> Bool {
        if device != nil { return true }
        guard let id = AudioDevices.mic() else { return false }
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, id, nil) { [weak self] _, _, _, output, _ in self?.render(output) }
        guard status == noErr, let proc else { return false }
        // This app only writes audio. WeChat is the microphone reader.
        var inputUsage = AudioHardwareIOProcStreamUsage(mIOProc: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), mNumberStreams: 1, mStreamIsOn: 0)
        var usageAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        let usageStatus = AudioObjectSetPropertyData(id, &usageAddress, 0, nil, UInt32(MemoryLayout<AudioHardwareIOProcStreamUsage>.size), &inputUsage)
        guard usageStatus == noErr else { AudioDeviceDestroyIOProcID(id, proc); return false }
        guard AudioDeviceStart(id, proc) == noErr else { AudioDeviceDestroyIOProcID(id, proc); return false }
        device = id
        ioProc = proc
        recoverInput()
        return true
    }

    func begin() -> Bool {
        guard connect(), let device else { return false }
        let original = AudioDevices.defaultInput()
        priorUID = original != device ? AudioDevices.string(original, kAudioDevicePropertyDeviceUID) : nil
        if let priorUID { UserDefaults.standard.set(priorUID, forKey: "restoreInputUID") }
        guard AudioDevices.setDefaultInput(device) else { return false }
        lock.lock()
        readIndex = 0; writeIndex = 0; count = 0
        rendered = 0; fed = 0
        draining = false; enabled = true
        dcX = 0; dcY = 0; previousSample = 0
        lock.unlock()
        return true
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
                if count == ring.count { readIndex = (readIndex + 1) % ring.count; count -= 1 }
                ring[writeIndex] = point
                writeIndex = (writeIndex + 1) % ring.count
                count += 1; fed += 1
            }
            previousSample = value
        }
    }

    func startDraining() { lock.lock(); draining = true; lock.unlock() }
    var pendingFrames: Int { lock.lock(); defer { lock.unlock() }; return count }
    var renderedFrames: Int { lock.lock(); defer { lock.unlock() }; return rendered }
    var fedFrames: Int { lock.lock(); defer { lock.unlock() }; return fed }

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
        recoverInput()
    }

    private func recoverInput() {
        guard let device else { return }
        let uid = priorUID ?? UserDefaults.standard.string(forKey: "restoreInputUID")
        if AudioDevices.defaultInput() == device, let uid,
           let original = AudioDevices.devices().first(where: { AudioDevices.string($0, kAudioDevicePropertyDeviceUID) == uid }) {
            if AudioDevices.setDefaultInput(original) { UserDefaults.standard.removeObject(forKey: "restoreInputUID") }
        } else if AudioDevices.defaultInput() != device {
            UserDefaults.standard.removeObject(forKey: "restoreInputUID")
        }
        priorUID = nil
    }

    func stop() {
        end()
        if let device, let ioProc { AudioDeviceStop(device, ioProc); AudioDeviceDestroyIOProcID(device, ioProc) }
        ioProc = nil; device = nil
    }
}
