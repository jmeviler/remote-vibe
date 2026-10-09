import Foundation
import CoreBluetooth

final class Remote: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
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
    private var proto = ATVVProtocol()
    private var streamID: UInt8 = 0
    private var keepAlive: Timer?
    private var limit: Timer?
    private var reconnect: Timer?
    private var connectionTimeout: Timer?
    private(set) var ready = false
    private(set) var streaming = false
    private(set) var frameCount = 0

    func start() { central = CBCentralManager(delegate: self, queue: .main) }

    func shutdown() {
        stopping = true
        close()
        reconnect?.invalidate()
        connectionTimeout?.invalidate()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
    }

    func close() {
        if streaming, let data = try? proto.micCloseCommand(streamID: streamID) { write(data) }
        finish(normal: false)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { find() }
        else {
            ready = false
            finish(normal: false)
            onStatus(central.state == .unauthorized ? "请允许蓝牙访问" : "等待蓝牙开启")
        }
    }

    private func find() {
        guard !stopping, central.state == .poweredOn, peripheral == nil else { return }
        let matches = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: ATVVProtocol.serviceUUID)])
            .filter { $0.name == "Chromecast Remote" }
        if matches.count == 1 { connect(matches[0]); return }
        if matches.count > 1 { onStatus("发现多个遥控器，请只连接要使用的那一个"); return }
        onStatus("寻找 Chromecast Remote；按一下遥控器可唤醒")
        central.scanForPeripherals(withServices: [CBUUID(string: ATVVProtocol.serviceUUID)])
        reconnect?.invalidate()
        reconnect = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.find() }
    }

    private func connect(_ p: CBPeripheral) {
        central.stopScan()
        reconnect?.invalidate()
        peripheral = p
        p.delegate = self
        onStatus("正在连接遥控器")
        central.connect(p)
        connectionTimeout?.invalidate()
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, !self.ready else { return }
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if p.name == "Chromecast Remote", peripheral == nil { connect(p) }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        proto = ATVVProtocol()
        subscribed.removeAll()
        handshakeSent = false
        p.discoverServices([CBUUID(string: ATVVProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { disconnected() }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { disconnected() }

    private func disconnected() {
        ready = false
        command = nil
        peripheral = nil
        connectionTimeout?.invalidate()
        finish(normal: false)
        onStatus("遥控器已断开，正在重连")
        guard !stopping else { return }
        reconnect?.invalidate()
        reconnect = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.find() }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = p.services?.first else { onStatus("读取语音服务失败"); return }
        p.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { onStatus("读取语音通道失败"); return }
        for c in service.characteristics ?? [] {
            switch c.uuid.uuidString.uppercased() {
            case ATVVProtocol.txUUID: command = c
            case ATVVProtocol.rxUUID, ATVVProtocol.controlUUID: p.setNotifyValue(true, for: c)
            default: break
            }
        }
        negotiate()
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard error == nil, c.isNotifying else { onStatus("订阅遥控器语音失败"); return }
        subscribed.insert(c.uuid.uuidString.uppercased())
        negotiate()
    }

    private func negotiate() {
        guard command != nil, subscribed.count == 2, !handshakeSent else { return }
        handshakeSent = true
        write(proto.getCapabilitiesCommand)
    }

    private func write(_ data: Data) {
        guard let peripheral, let command else { return }
        peripheral.writeValue(data, for: command, type: command.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let data = c.value else { return }
        if c.uuid.uuidString.uppercased() == ATVVProtocol.rxUUID {
            guard streaming, let decoded = proto.decodeAudio(data), let codec = proto.codec else { return }
            frameCount += 1
            onSamples(decoded.samples, codec.sampleRate)
            return
        }
        switch proto.parseControl(data) {
        case .capabilities(let capabilities):
            do {
                try proto.acceptCapabilities(capabilities)
                ready = true
                connectionTimeout?.invalidate()
                if let close = try? proto.micCloseCommand(streamID: 0) { write(close) }
                onStatus("遥控器已连接")
            } catch { onStatus(error.localizedDescription) }
        case .startSearch:
            if !streaming, ready {
                proto.prepareForAudioStream()
                if let data = try? proto.micOpenCommand() { write(data) }
            }
        case .audioStart(_, let codec, let sid):
            proto.beginAudioStream(codec: codec)
            streamID = sid
            if !streaming {
                streaming = true
                frameCount = 0
                onBegin()
                // onBegin can decline the session if recognition is unavailable.
                guard streaming else { return }
                keepAlive?.invalidate()
                keepAlive = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                    guard let self, self.streaming, let data = try? self.proto.keepAliveCommand(streamID: self.streamID) else { return }
                    self.write(data)
                }
                limit?.invalidate()
                limit = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    if let data = try? self.proto.micCloseCommand(streamID: self.streamID) { self.write(data) }
                    self.finish(normal: true)
                }
            }
        case .audioSync(let codec, let sequence, let predictor, let stepIndex):
            proto.applyAudioSync(codec: codec, sequence: sequence, predictor: predictor, stepIndex: stepIndex)
        case .audioStop:
            finish(normal: true)
        case .micOpenError:
            onStatus("遥控器暂时未能开启麦克风，请再按一次")
            finish(normal: false)
        case .unknown: break
        }
    }

    private func finish(normal: Bool) {
        keepAlive?.invalidate()
        limit?.invalidate()
        proto.endAudioStream()
        guard streaming else { return }
        streaming = false
        onEnd(normal)
    }
}
