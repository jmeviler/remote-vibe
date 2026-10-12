import Foundation

enum RemoteProfile: String, CaseIterable {
    case chromecast
    case xiaomiRC003

    var title: String { self == .chromecast ? "Google" : L("小米 RC003") }
    var vendorID: Int { self == .chromecast ? 0x18D1 : 0x2717 }
    var productID: Int { self == .chromecast ? 0x9450 : 0x32B8 }
    var mappingKey: String { self == .chromecast ? "keyMappings.v1" : "keyMappings.xiaomiRC003.v1" }

    var mouseMappingKey: String { mappingKey + ".mouse" }

    func accepts(name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .chromecast: return normalized == "chromecast remote"
        case .xiaomiRC003:
            return ["小米蓝牙语音遥控器", "mi rc", "xiaomi bluetooth remote 2 pro"].contains(normalized)
        }
    }
}
