import Foundation
import IOKit.hid
import IOKit.hidsystem

// Suppress only RC003's native F5; the shared voice session emits paired Fn events.
// No raw HID listener and no changes to its other buttons or to other keyboards.
final class XiaomiVoiceKeyOverride {
    typealias Mappings = [[String: UInt64]]
    private struct Snapshot {
        let service: IOHIDServiceClient
        let original: Mappings
    }
    static let src = "HIDKeyboardModifierMappingSrc"
    static let dst = "HIDKeyboardModifierMappingDst"
    static let voiceSource: UInt64 = 0x000000070000003E
    static let neutral: [String: UInt64] = [src: voiceSource, dst: 0]
    private let property = "UserKeyMapping" as CFString
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var snapshots: [UInt64: Snapshot] = [:]
    private(set) var ready = false
    private(set) var status = L("等待小米语音连接")

    static func restoring(_ current: Mappings, original: Mappings) -> Mappings {
        // If another tool changed F5 after us, its value belongs to that tool.
        guard current.contains(neutral) else { return current }
        return current.filter { $0 != neutral } + original.filter { $0[src] == voiceSource }
    }

    func refresh(enabled: Bool) {
        guard enabled else { stop(); return }
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []).filter {
            (IOHIDServiceClientCopyProperty($0, "VendorID" as CFString) as? NSNumber)?.intValue == 0x2717 &&
            (IOHIDServiceClientCopyProperty($0, "ProductID" as CFString) as? NSNumber)?.intValue == 0x32B8
        }
        var present = Set<UInt64>()
        var applied = !services.isEmpty
        for service in services {
            guard let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { applied = false; continue }
            present.insert(id)
            // Do not treat an unreadable or unexpected property as empty.
            let value = IOHIDServiceClientCopyProperty(service, property)
            guard value == nil || value is Mappings else { applied = false; continue }
            var current = value as? Mappings ?? []
            if snapshots[id] == nil {
                let desired = current.filter { $0[Self.src] != Self.voiceSource } + [Self.neutral]
                snapshots[id] = Snapshot(service: service, original: current)
                if current != desired { _ = IOHIDServiceClientSetProperty(service, property, desired as CFArray) }
                current = IOHIDServiceClientCopyProperty(service, property) as? Mappings ?? []
            }
            // Apply once per connection, never fight a later change by another remapper.
            applied = applied && current.contains(Self.neutral)
        }
        snapshots = snapshots.filter { present.contains($0.key) }
        ready = applied
        status = applied ? L("小米语音键已就绪") : L("小米语音键未接管，请退出其他映射工具后重连")
    }

    func stop() {
        for snapshot in snapshots.values {
            guard let current = IOHIDServiceClientCopyProperty(snapshot.service, property) as? Mappings else { continue }
            let restored = Self.restoring(current, original: snapshot.original)
            if current != restored { _ = IOHIDServiceClientSetProperty(snapshot.service, property, restored as CFArray) }
        }
        snapshots.removeAll()
        ready = false
        status = L("等待小米语音连接")
    }
}
