import Foundation

protocol VoiceSessionTimer { func cancel() }
protocol VoiceSessionScheduling {
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> VoiceSessionTimer
}
extension Timer: VoiceSessionTimer { func cancel() { invalidate() } }
struct VoiceSessionScheduler: VoiceSessionScheduling {
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> VoiceSessionTimer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

// Transport-independent voice lifecycle. Timers exist only while opening,
// recording or closing; physical voice keys keep their existing audio path.
final class RemoteAudioSession {
    enum Source { case physical, mappedButton }
    let profile: RemoteProfile
    private(set) var proto: ATVVProtocol
    var ready = false
    var send: (Data) -> Void = { _ in }
    var onBegin: () -> Void = {}
    var onSamples: ([Int16], Int) -> Void = { _, _ in }
    var onEnd: (Bool) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }
    private(set) var source: Source?
    private(set) var streaming = false
    private(set) var frameCount = 0
    private(set) var opening = false
    private var streamID: UInt8 = 0
    private var closingNormally: Bool?
    private var rejectingLateStart = false
    private var responseTimer: VoiceSessionTimer?
    private var firstAudioTimer: VoiceSessionTimer?
    private var keepAlive: VoiceSessionTimer?
    private var limit: VoiceSessionTimer?
    private var closeTimer: VoiceSessionTimer?
    private var rejectionTimer: VoiceSessionTimer?
    private let scheduler: VoiceSessionScheduling
    var busy: Bool { source != nil || rejectingLateStart }

    init(profile: RemoteProfile, scheduler: VoiceSessionScheduling = VoiceSessionScheduler()) {
        self.profile = profile
        self.scheduler = scheduler
        proto = ATVVProtocol(profile: profile)
    }

    func reset() {
        cancel()
        rejectionTimer?.cancel(); rejectionTimer = nil
        rejectingLateStart = false
        ready = false
        proto = ATVVProtocol(profile: profile)
    }

    @discardableResult
    func beginMappedVoice() -> Bool {
        guard profile == .chromecast else { return false }
        return requestOpen(source: .mappedButton)
    }

    private func requestOpen(source: Source) -> Bool {
        guard ready, !busy,
              let command = try? proto.micOpenCommand() else { return false }
        self.source = source; opening = true; streamID = 0
        proto.prepareForAudioStream()
        // Arm before writing so even an immediate response can cancel the timer.
        responseTimer = scheduler.after(1.5) { [weak self] in
            guard let self, self.opening else { return }
            self.cancel()
            self.onStatus("遥控器没有响应开麦，请松开后重试或使用原语音键")
        }
        send(command)
        return true
    }

    func endMappedVoice(normal: Bool) {
        guard source == .mappedButton else { return }
        if !normal || !streaming { cancel(); return }
        guard closingNormally == nil else { return }
        closingNormally = true
        keepAlive?.cancel(); keepAlive = nil
        limit?.cancel(); limit = nil
        firstAudioTimer?.cancel(); firstAudioTimer = nil
        // Keep accepting in-flight audio until AUDIO_STOP, with a bounded fallback.
        closeTimer = scheduler.after(0.4) { [weak self] in
            guard let self, self.closingNormally != nil else { return }
            self.closeStream(self.streamID)
            self.rejectLateStarts()
            self.finish(normal: true)
        }
        closeStream(streamID)
    }

    func cancel() {
        let pending = opening
        let hadMappedVoice = source == .mappedButton
        closingNormally = false
        if pending || streaming { closeStream(streamID) }
        if pending || hadMappedVoice { rejectLateStarts() }
        finish(normal: false)
    }

    func receiveAudio(_ data: Data) {
        guard streaming, let decoded = proto.decodeAudio(data), let codec = proto.codec else { return }
        frameCount += 1
        firstAudioTimer?.cancel(); firstAudioTimer = nil
        onSamples(decoded.samples, codec.sampleRate)
    }

    func receive(_ event: ATVVControlEvent) {
        switch event {
        case .startSearch:
            _ = requestOpen(source: .physical)
        case .audioStart(let reason, let codec, let sid):
            guard ready else { return }
            if rejectingLateStart {
                closeStream(sid)
                return
            }
            // A delayed reply to a cancelled host request must never start Fn.
            if profile == .chromecast, source == nil, reason == 0 {
                closeStream(sid)
                return
            }
            guard !streaming else { return }
            guard profile != .xiaomiRC003 || codec == .adpcm16k else {
                closeStream(sid); finish(normal: false)
                onStatus("小米切换到不支持的音频编码")
                return
            }
            if source == nil { source = .physical }
            opening = false
            responseTimer?.cancel(); responseTimer = nil
            streamID = sid
            proto.beginAudioStream(codec: codec)
            streaming = true; frameCount = 0
            onBegin()
            // The app can refuse a session while audio drains or permission is missing.
            guard streaming, closingNormally == nil else { return }
            if source == .mappedButton {
                firstAudioTimer = scheduler.after(1.5) { [weak self] in
                    guard let self, self.streaming, self.frameCount == 0 else { return }
                    self.cancel()
                    self.onStatus("遥控器没有传回音频，请松开后重试或使用原语音键")
                }
            }
            scheduleKeepAlive()
            limit = scheduler.after(55) { [weak self] in
                guard let self else { return }
                if self.source == .mappedButton { self.endMappedVoice(normal: true) }
                else { self.closeStream(self.streamID); self.finish(normal: true) }
            }
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            proto.applyAudioSync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: stepIndex)
        case .audioStop:
            // A previous physical release can arrive after MIC_OPEN but before its reply.
            if opening && source == .physical { cancel(); return }
            guard streaming else { return }
            finish(normal: closingNormally ?? true)
        case .micOpenError:
            guard busy else { return }
            cancel()
            onStatus("遥控器暂时未能开启麦克风，请松开后重试")
        case .capabilities, .unknown: break
        }
    }

    private func closeStream(_ id: UInt8) {
        if let command = try? proto.micCloseCommand(streamID: id) { send(command) }
    }

    private func scheduleKeepAlive() {
        guard profile == .chromecast, streaming, closingNormally == nil else { return }
        keepAlive = scheduler.after(4) { [weak self] in
            guard let self, self.streaming, self.closingNormally == nil else { return }
            if let command = try? self.proto.keepAliveCommand(streamID: self.streamID) { self.send(command) }
            self.scheduleKeepAlive()
        }
    }

    private func rejectLateStarts() {
        rejectingLateStart = true
        rejectionTimer?.cancel()
        rejectionTimer = scheduler.after(1.5) { [weak self] in
            self?.rejectingLateStart = false
            self?.rejectionTimer = nil
        }
    }

    private func finish(normal: Bool) {
        responseTimer?.cancel(); responseTimer = nil
        firstAudioTimer?.cancel(); firstAudioTimer = nil
        keepAlive?.cancel(); keepAlive = nil
        limit?.cancel(); limit = nil
        closeTimer?.cancel(); closeTimer = nil
        let began = streaming
        streaming = false; opening = false; source = nil; closingNormally = nil; streamID = 0
        proto.endAudioStream()
        if began { onEnd(normal) }
    }
}
