import Foundation

// One selected remote at a time; both models share the existing microphone/Fn pipeline.
final class RemoteController {
    private var device: BluetoothRemote
    var onStatus: (String) -> Void = { _ in }
    var canBegin: (RemoteProfile) -> Bool = { _ in true }
    var onBegin: () -> Void = {}
    var onSamples: ([Int16], Int) -> Void = { _, _ in }
    var onEnd: (Bool) -> Void = { _ in }
    private var closingRejected = false

    init() {
        let saved = UserDefaults.standard.string(forKey: "voiceRemote.v1") ?? ""
        device = BluetoothRemote(profile: RemoteProfile(rawValue: saved) ?? .chromecast)
    }

    var profile: RemoteProfile { device.profile }
    var ready: Bool { device.ready }
    var streaming: Bool { device.streaming }
    var frameCount: Int { device.frameCount }
    var voiceBusy: Bool { device.voiceBusy }
    var mappedVoiceActive: Bool { device.mappedVoiceActive }
    var sourceName: String { profile.title }
    var xiaomiReady: Bool { profile == .xiaomiRC003 && ready }
    var protocolSummary: String { device.protocolSummary }
    var scanning: Bool { device.scanning }
    var connecting: Bool { device.connecting }
    var scanStarts: Int { device.scanStarts }

    func select(_ profile: RemoteProfile) {
        guard profile != device.profile else { return }
        device.shutdown()
        device = BluetoothRemote(profile: profile)
        UserDefaults.standard.set(profile.rawValue, forKey: "voiceRemote.v1")
        start()
    }

    func start() {
        let device = self.device
        device.onStatus = { [weak self, weak device] text in
            guard let self, let device, self.device === device else { return }
            self.onStatus("\(device.profile.title)：\(text)")
        }
        device.onBegin = { [weak self, weak device] in
            guard let self, let device, self.device === device else { return }
            // A second press while the preceding audio drains must not abort that input.
            guard self.canBegin(device.profile) else {
                self.closingRejected = true
                device.cancelVoice()
                self.closingRejected = false
                return
            }
            self.onBegin()
        }
        device.onSamples = { [weak self, weak device] samples, rate in
            guard let self, let device, self.device === device else { return }
            self.onSamples(samples, rate)
        }
        device.onEnd = { [weak self, weak device] normal in
            guard let self, let device, self.device === device, !self.closingRejected else { return }
            self.onEnd(normal)
        }
        device.start()
    }

    func beginMappedVoice() -> Bool {
        guard profile == .chromecast, ready, !voiceBusy, canBegin(profile) else { return false }
        return device.beginMappedVoice()
    }
    func endMappedVoice(normal: Bool) { device.endMappedVoice(normal: normal) }
    func cancelVoice() { device.cancelVoice() }
    func toggleDiscovery() { device.toggleDiscovery() }
    func shutdown() { device.shutdown() }
}
