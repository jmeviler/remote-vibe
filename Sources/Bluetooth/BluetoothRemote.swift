import Foundation
import CoreBluetooth

final class BluetoothRemote: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let profile: RemoteProfile
    var onStatus: (String) -> Void = { _ in }
    var onBegin: () -> Void = {}
    var onSamples: ([Int16], Int) -> Void = { _, _ in }
    var onEnd: (Bool) -> Void = { _ in }
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var subscribed = Set<String>()
    private var handshakeSent = false
    private var stopping = false
    private let audio: RemoteAudioSession
    private var proto: ATVVProtocol { audio.proto }
    private var modelConfirmed = false
    private var reconnect: Timer?
    private var scanTimeout: Timer?
    private var connectionTimeout: Timer?
    private var retryCount = 0
    private var rememberedKey: String { "voicePeripheral.\(profile.rawValue).v1" }
    var scanning: Bool { central?.isScanning == true }
    var connecting: Bool { peripheral != nil && !ready }
    private(set) var scanStarts = 0
    var ready: Bool { audio.ready }
    var streaming: Bool { audio.streaming }
    var frameCount: Int { audio.frameCount }
    var voiceBusy: Bool { audio.busy }
    var mappedVoiceActive: Bool { audio.source == .mappedButton }

    var protocolSummary: String {
        guard let caps = proto.capabilities, let codec = proto.codec else { return "等待协商" }
        return "ATVV \(caps.version) · \(codec.sampleRate) Hz · \(caps.frameSize) bytes"
    }

    init(profile: RemoteProfile = .chromecast) {
        self.profile = profile
        audio = RemoteAudioSession(profile: profile)
        super.init()
        audio.send = { [weak self] in self?.write($0) }
        audio.onBegin = { [weak self] in self?.onBegin() }
        audio.onSamples = { [weak self] in self?.onSamples($0, $1) }
        audio.onEnd = { [weak self] in self?.onEnd($0) }
        audio.onStatus = { [weak self] in self?.onStatus($0) }
        audio.onDisconnect = { [weak self] in
            guard let self, let peripheral = self.peripheral else { return }
            self.central?.cancelPeripheralConnection(peripheral)
        }
    }

    func start() { central = CBCentralManager(delegate: self, queue: .main) }

    func shutdown() {
        stopping = true
        audio.reset()
        reconnect?.invalidate()
        connectionTimeout?.invalidate()
        stopScanning()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    func cancelVoice() { audio.cancel() }
    func beginMappedVoice() -> Bool { ready && audio.beginMappedVoice() }
    func endMappedVoice(normal: Bool) { audio.endMappedVoice(normal: normal) }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopping else { return }
        if central.state == .poweredOn { retryCount = 0; findKnown() }
        else {
            reconnect?.invalidate()
            stopScanning()
            audio.reset()
            command = nil
            peripheral = nil
            connectionTimeout?.invalidate()
            onStatus(central.state == .unauthorized ? "请允许蓝牙访问" : "等待蓝牙开启")
        }
    }

    // Retrieving known/system-connected devices does not start discovery scanning.
    private func findKnown() {
        guard !stopping, central.state == .poweredOn, peripheral == nil else { return }
        if let value = UserDefaults.standard.string(forKey: rememberedKey), let id = UUID(uuidString: value),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known); return
        }
        if connectSystemDevice() { return }
        onStatus("尚未连接，请先在系统蓝牙配对；需要时手动扫描")
    }

    private func connectSystemDevice() -> Bool {
        let matches = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: ATVVProtocol.serviceUUID), CBUUID(string: "1812")])
            .filter { profile.accepts(name: $0.name) }
        if matches.count == 1 { connect(matches[0]); return true }
        if matches.count > 1 { onStatus("发现多个遥控器，请只连接要使用的那一个"); return true }
        return false
    }

    // Called only by the user's button. Cancelling a pending connection permits a new scan.
    func toggleDiscovery() {
        guard !stopping, !ready, !streaming else { return }
        reconnect?.invalidate()
        retryCount = 0
        if scanning {
            stopScanning()
            onStatus("扫描已停止，需要时可再次手动扫描")
            return
        }
        if let p = peripheral {
            peripheral = nil
            command = nil
            connectionTimeout?.invalidate()
            central.cancelPeripheralConnection(p)
            onStatus("连接等待已取消，可手动扫描遥控器")
            return
        }
        guard central?.state == .poweredOn else {
            onStatus(central?.state == .unauthorized ? "请允许蓝牙访问" : "请先开启蓝牙")
            return
        }
        if connectSystemDevice() { return }
        central.scanForPeripherals(withServices: [CBUUID(string: ATVVProtocol.serviceUUID)])
        scanStarts += 1
        onStatus("正在扫描所选型号（最多 20 秒），请唤醒遥控器")
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stopScanning()
            self.onStatus("未找到遥控器，扫描已停止；请检查配对后手动重试")
        }
    }

    private func stopScanning() {
        scanTimeout?.invalidate()
        scanTimeout = nil
        if scanning { central.stopScan() }
    }

    private func connect(_ p: CBPeripheral) {
        stopScanning()
        reconnect?.invalidate()
        peripheral = p
        p.delegate = self
        onStatus("正在等待遥控器连接，按键可唤醒")
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !stopping, scanning, peripheral == nil else { return }
        if profile.accepts(name: p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String) { connect(p) }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p === peripheral, !stopping else { return }
        // Let CoreBluetooth wait for a sleeping known remote without an App polling loop.
        // Only the connected device's ATVV initialization has a timeout.
        connectionTimeout?.invalidate()
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, !self.ready, let p = self.peripheral else { return }
            self.central.cancelPeripheralConnection(p)
        }
        onStatus("正在初始化遥控器语音")
        audio.reset()
        subscribed.removeAll()
        handshakeSent = false
        modelConfirmed = profile == .chromecast
        p.discoverServices([CBUUID(string: ATVVProtocol.serviceUUID)] + (profile == .xiaomiRC003 ? [CBUUID(string: "180A")] : []))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { if p === peripheral { disconnected() } }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { if p === peripheral { disconnected() } }

    private func disconnected() {
        command = nil
        peripheral = nil
        connectionTimeout?.invalidate()
        audio.reset()
        guard !stopping, central.state == .poweredOn else { return }
        reconnect?.invalidate()
        guard UserDefaults.standard.string(forKey: rememberedKey) != nil, retryCount < 3 else {
            onStatus("连接未就绪，请检查配对后手动重试")
            return
        }
        let delay: TimeInterval = [2, 10, 30][retryCount]
        retryCount += 1
        onStatus("遥控器已断开，等待已记住的设备重连")
        reconnect = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.findKnown() }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, let service = p.services?.first(where: { $0.uuid == CBUUID(string: ATVVProtocol.serviceUUID) }) else { onStatus("读取语音服务失败"); return }
        p.discoverCharacteristics(nil, for: service)
        if profile == .xiaomiRC003, let info = p.services?.first(where: { $0.uuid == CBUUID(string: "180A") }) {
            p.discoverCharacteristics([CBUUID(string: "2A24")], for: info)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil else { onStatus("读取语音通道失败"); return }
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString.uppercased() {
            case ATVVProtocol.txUUID: command = c
            case ATVVProtocol.rxUUID, ATVVProtocol.controlUUID: p.setNotifyValue(true, for: c)
            case "2A24": p.readValue(for: c)
            default: break
            }
        }
        negotiate()
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, c.isNotifying else { onStatus("订阅遥控器语音失败"); return }
        subscribed.insert(c.uuid.uuidString.uppercased())
        negotiate()
    }

    private func negotiate() {
        guard command != nil, subscribed.count == 2, modelConfirmed, !handshakeSent else { return }
        handshakeSent = true
        write(proto.getCapabilitiesCommand)
    }

    private func write(_ data: Data) {
        guard let peripheral, let command else { return }
        peripheral.writeValue(data, for: command, type: command.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard p === peripheral, !stopping, error == nil, let data = c.value else { return }
        if c.uuid == CBUUID(string: "2A24") {
            modelConfirmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "RC003"
            if modelConfirmed { negotiate() } else { onStatus("这款小米型号暂未适配，仅支持 RC003") }
            return
        }
        if c.uuid.uuidString.uppercased() == ATVVProtocol.rxUUID {
            audio.receiveAudio(data)
            return
        }
        let event = proto.parseControl(data)
        switch event {
        case .capabilities(let capabilities):
            guard handshakeSent, !ready else { return }
            do {
                try proto.acceptCapabilities(capabilities)
                audio.ready = true
                retryCount = 0
                UserDefaults.standard.set(p.identifier.uuidString, forKey: rememberedKey)
                connectionTimeout?.invalidate()
                if profile == .chromecast, let close = try? proto.micCloseCommand(streamID: 0) { write(close) }
                onStatus("遥控器已连接")
            } catch { onStatus(error.localizedDescription) }
        default: audio.receive(event)
        }
    }
}
