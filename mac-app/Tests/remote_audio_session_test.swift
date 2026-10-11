import Foundation

private final class Clock {
    final class Task {
        let deadline: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(_ deadline: TimeInterval, _ action: @escaping () -> Void) { self.deadline = deadline; self.action = action }
        func cancel() { cancelled = true }
    }
    var now: TimeInterval = 0
    var tasks: [Task] = []
    var pending: Int { tasks.filter { !$0.cancelled }.count }
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> RemoteAudioSession.Cancel {
        let task = Task(now + delay, action); tasks.append(task); return { task.cancel() }
    }
    func advance(_ duration: TimeInterval) {
        let end = now + duration
        while let next = tasks.filter({ !$0.cancelled && $0.deadline <= end }).min(by: { $0.deadline < $1.deadline }) {
            now = next.deadline; next.cancel(); next.action()
        }
        now = end
    }
}

private final class Rig {
    let clock = Clock()
    let session: RemoteAudioSession
    var commands: [Data] = []
    var begins = 0
    var ends: [Bool] = []
    var samples = 0
    var statuses: [String] = []
    var disconnections = 0
    init(_ profile: RemoteProfile = .chromecast, version: ATVVVersion = .v10) throws {
        let clock = self.clock
        session = RemoteAudioSession(profile: profile, schedule: clock.after, now: { clock.now })
        try session.proto.acceptCapabilities(.init(version: version, codecs: 2, interactionModel: 3,
                                                  frameSize: profile == .chromecast ? 160 : 120))
        session.ready = true
        session.send = { [weak self] in self?.commands.append($0) }
        session.onBegin = { [weak self] in self?.begins += 1 }
        session.onEnd = { [weak self] in self?.ends.append($0) }
        session.onSamples = { [weak self] values, _ in self?.samples += values.count }
        session.onStatus = { [weak self] in self?.statuses.append($0) }
        session.onDisconnect = { [weak self] in self?.disconnections += 1 }
    }
    func start(_ id: UInt8 = 0, reason: UInt8 = 0) { session.receive(.audioStart(reason: reason, codec: .adpcm16k, streamID: id)) }
    func audio(_ count: Int = 160) { session.receiveAudio(Data(repeating: 0x12, count: count)) }
    func stop(_ reason: UInt8 = 0) { session.receive(.audioStop(reason: reason)) }
    func count(_ bytes: [UInt8]) -> Int { commands.filter { $0 == Data(bytes) }.count }
}

@main
enum RemoteAudioSessionTest {
    static func main() throws {
        try directOpenAndTail()
        try quickReleaseAndLateReply()
        try physicalFallbackAfterCancellation()
        try failedRequests()
        try preservePhysicalVoice()
        try cancellationAndLimit()
        try protocolVariants()
        print("PASS: software open, release/tail, stale responses, timeout, cancellation, keepalive, Google/Xiaomi physical voice; no Bluetooth or audio devices used.")
    }

    static func directOpenAndTail() throws {
        let r = try Rig()
        precondition(r.clock.pending == 0)
        precondition(r.session.beginMappedVoice())
        precondition(r.begins == 0 && r.session.opening && r.count([0x0c, 0]) == 1)
        precondition(!r.session.beginMappedVoice()) // another mapped key cannot interrupt
        r.session.receive(.audioStop(reason: 2)) // old physical release before grant
        precondition(r.session.opening)
        r.start(); r.audio()
        precondition(r.begins == 1 && r.samples == 320)
        r.clock.advance(4)
        precondition(r.count([0x0e, 0]) == 1)
        r.session.endMappedVoice(normal: true)
        precondition(r.count([0x0d, 0]) == 1 && r.ends.isEmpty)
        r.audio() // final in-flight packet must reach the same session
        precondition(r.samples == 640)
        r.stop()
        precondition(r.ends == [true] && !r.session.busy && r.clock.pending == 0)
        r.audio(); r.clock.advance(100)
        precondition(r.samples == 640 && r.ends == [true])
        precondition(r.session.beginMappedVoice())
    }

    static func quickReleaseAndLateReply() throws {
        let r = try Rig()
        precondition(r.session.beginMappedVoice())
        r.session.endMappedVoice(normal: true)
        precondition(r.begins == 0 && r.ends.isEmpty && r.count([0x0d, 0]) == 1)
        precondition(r.clock.pending == 0) // no cooldown timer or global input block
        precondition(!r.session.beginMappedVoice()) // only mapped requests are throttled
        r.stop()
        r.start(); r.audio() // delayed v1 host reply, not a physical HTT press
        precondition(r.count([0x0d, 0]) == 2 && r.begins == 0 && r.samples == 0)
        r.stop(); r.clock.advance(1.6)
        precondition(r.clock.pending == 0 && !r.session.busy)
        precondition(r.session.beginMappedVoice())
        r.start(); r.audio()
        precondition(r.begins == 1)
    }

    static func physicalFallbackAfterCancellation() throws {
        let r = try Rig()
        precondition(r.session.beginMappedVoice())
        r.session.endMappedVoice(normal: true)
        r.clock.advance(0.1)
        r.start(42, reason: 3); r.audio()
        precondition(r.begins == 1 && r.samples == 320 && r.count([0x0d, 42]) == 0)
        // Late host reply and its close ACK must not interrupt the physical key.
        r.start(); r.stop()
        precondition(r.session.streaming && r.ends.isEmpty)
        r.stop(2)
        precondition(r.ends == [true] && r.clock.pending == 0)

        let search = try Rig()
        precondition(search.session.beginMappedVoice())
        search.session.cancel()
        search.session.receive(.startSearch)
        search.start(); search.audio(); search.stop()
        precondition(search.begins == 1 && search.ends == [true])

        let original = try Rig()
        original.start(42, reason: 3); original.audio(); original.stop()
        precondition(original.ends == [true]) // no host request: do not change old STOP handling
    }

    static func failedRequests() throws {
        let noResponse = try Rig()
        precondition(noResponse.session.beginMappedVoice())
        noResponse.clock.advance(1.6)
        precondition(noResponse.begins == 0 && !noResponse.session.opening && noResponse.statuses.count == 1)
        noResponse.start(); noResponse.audio(); noResponse.stop()
        precondition(noResponse.begins == 0 && noResponse.samples == 0)
        noResponse.clock.advance(2)
        precondition(noResponse.clock.pending == 0)

        let noAudio = try Rig()
        precondition(noAudio.session.beginMappedVoice())
        noAudio.start(); noAudio.clock.advance(1.6)
        precondition(noAudio.begins == 1 && noAudio.ends == [false] && !noAudio.session.streaming)
        precondition(noAudio.statuses.count == 1)
        noAudio.clock.advance(5)
        precondition(noAudio.count([0x0e, 0]) == 0 && noAudio.clock.pending == 0)

        let rejected = try Rig()
        precondition(rejected.session.beginMappedVoice())
        rejected.session.receive(.micOpenError(0x0f80))
        precondition(!rejected.session.opening && rejected.statuses.count == 1)
        rejected.clock.advance(3)
        precondition(rejected.clock.pending == 0)

        let noStop = try Rig()
        precondition(noStop.session.beginMappedVoice())
        noStop.start(23, reason: 3); noStop.audio()
        noStop.session.endMappedVoice(normal: true)
        noStop.clock.advance(0.5)
        precondition(noStop.count([0x0d, 23]) == 2 && noStop.ends.isEmpty)
        noStop.audio() // the remote has not stopped sending
        noStop.clock.advance(0.4)
        precondition(noStop.ends == [false] && noStop.disconnections == 1)
        precondition(noStop.session.busy && !noStop.session.ready && !noStop.session.streaming)
        noStop.session.cancel() // explicit Stop still targets the retained stream id
        precondition(noStop.count([0x0d, 23]) == 3 && noStop.ends == [false])
        noStop.audio(); noStop.stop(); noStop.clock.advance(2)
        precondition(noStop.samples == 640 && noStop.clock.pending == 0)
        precondition(!noStop.session.beginMappedVoice())
        noStop.session.reset() // only disconnect/reset clears the failed transport
        precondition(!noStop.session.busy)

        let tailOnly = try Rig()
        precondition(tailOnly.session.beginMappedVoice())
        tailOnly.start(); tailOnly.session.endMappedVoice(normal: true)
        tailOnly.audio() // first packet arriving during close must not cancel the close timeout
        tailOnly.clock.advance(0.9)
        precondition(tailOnly.disconnections == 1 && tailOnly.ends == [false])

        let delayedStop = try Rig()
        precondition(delayedStop.session.beginMappedVoice())
        delayedStop.start(9, reason: 3); delayedStop.audio()
        delayedStop.session.endMappedVoice(normal: true)
        delayedStop.clock.advance(0.5); delayedStop.stop()
        delayedStop.clock.advance(1)
        precondition(delayedStop.count([0x0d, 9]) == 2 && delayedStop.ends == [true])
        precondition(delayedStop.disconnections == 0 && delayedStop.clock.pending == 0)
    }

    static func preservePhysicalVoice() throws {
        for profile in RemoteProfile.allCases {
            let r = try Rig(profile)
            r.start(42, reason: 3)
            precondition(!r.session.beginMappedVoice())
            r.session.endMappedVoice(normal: false) // mapped release cannot close a physical session
            precondition(r.session.streaming && r.commands.isEmpty)
            r.audio(profile == .chromecast ? 160 : 60)
            if profile == .xiaomiRC003 {
                precondition(r.samples == 0) // RC003 partial-frame accumulation is preserved
                r.audio(60)
                precondition(r.samples == 240)
            }
            r.clock.advance(4)
            precondition(r.count([0x0e, 42]) == (profile == .chromecast ? 1 : 0))
            r.stop(2)
            precondition(r.begins == 1 && r.ends == [true] && r.clock.pending == 0)
            precondition(r.count([0x0c, 0]) == 0)
        }
        let xiaomi = try Rig(.xiaomiRC003)
        precondition(!xiaomi.session.beginMappedVoice() && xiaomi.commands.isEmpty)
        xiaomi.session.receive(.startSearch)
        precondition(xiaomi.count([0x0c, 0]) == 1)
        xiaomi.start(); xiaomi.audio(120); xiaomi.stop()
        precondition(xiaomi.begins == 1 && xiaomi.ends == [true] && xiaomi.samples == 240)

        let googleSearch = try Rig()
        googleSearch.session.receive(.startSearch)
        googleSearch.start(); googleSearch.audio(); googleSearch.stop()
        precondition(googleSearch.begins == 1 && googleSearch.ends == [true])

        let releasedBeforeGrant = try Rig()
        releasedBeforeGrant.session.receive(.startSearch)
        releasedBeforeGrant.stop(); releasedBeforeGrant.start(); releasedBeforeGrant.audio(); releasedBeforeGrant.stop()
        precondition(releasedBeforeGrant.begins == 0 && releasedBeforeGrant.samples == 0)
        releasedBeforeGrant.clock.advance(2)
        precondition(!releasedBeforeGrant.session.busy && releasedBeforeGrant.clock.pending == 0)

        let searchTimeout = try Rig(.xiaomiRC003)
        searchTimeout.session.receive(.startSearch)
        searchTimeout.clock.advance(3.1)
        precondition(!searchTimeout.session.busy && searchTimeout.begins == 0)
        searchTimeout.session.receive(.startSearch)
        searchTimeout.start(); searchTimeout.audio(120); searchTimeout.stop()
        precondition(searchTimeout.begins == 1 && searchTimeout.samples == 240)
    }

    static func cancellationAndLimit() throws {
        for beforeStart in [true, false] {
            let r = try Rig()
            precondition(r.session.beginMappedVoice())
            if !beforeStart { r.start(); r.audio() }
            r.session.endMappedVoice(normal: false) // save / listener loss / sleep / explicit stop
            precondition(!r.session.streaming && r.ends == (beforeStart ? [] : [false]))
            r.clock.advance(60)
            precondition(r.clock.pending == 0)
        }
        let disconnected = try Rig()
        precondition(disconnected.session.beginMappedVoice())
        disconnected.start(); disconnected.audio()
        disconnected.session.reset()
        disconnected.start(); disconnected.audio()
        precondition(disconnected.begins == 1 && disconnected.ends == [false])
        precondition(!disconnected.session.ready && disconnected.clock.pending == 0)

        let declined = try Rig()
        declined.session.onBegin = { declined.session.cancel() }
        precondition(declined.session.beginMappedVoice())
        declined.start(); declined.audio()
        declined.clock.advance(60)
        precondition(declined.samples == 0 && declined.clock.pending == 0)

        let limit = try Rig()
        precondition(limit.session.beginMappedVoice())
        limit.start(); limit.audio(); limit.clock.advance(55); limit.stop()
        precondition(limit.ends == [true] && !limit.session.streaming)
        limit.clock.advance(2)
        precondition(limit.clock.pending == 0)
    }

    static func protocolVariants() throws {
        let legacy = try Rig(version: .v04)
        precondition(!legacy.session.beginMappedVoice()) // software open is validated only for v1
        legacy.session.receive(legacy.session.proto.parseControl(Data([0x04])))
        legacy.audio()
        precondition(legacy.begins == 1 && legacy.samples > 0 && legacy.commands.isEmpty)
        legacy.stop()
        precondition(legacy.ends == [true] && legacy.clock.pending == 0)
        legacy.session.receive(.startSearch)
        precondition(legacy.count([0x0c, 0, 2]) == 1)
        legacy.start(); legacy.audio(); legacy.stop()
        precondition(legacy.begins == 2 && legacy.ends == [true, true])

        let sync = try Rig()
        precondition(sync.session.beginMappedVoice())
        sync.session.receive(.audioSync(codec: .adpcm16k, sequence: 7, predictor: 1200, stepIndex: 0))
        sync.start()
        var first: Int16?
        sync.session.onSamples = { first = $0.first; precondition($1 == 16000) }
        sync.session.receiveAudio(Data([0]))
        precondition(first == 1200) // AUDIO_START must not erase a preceding sync
    }
}
