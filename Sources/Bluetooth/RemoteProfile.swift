import Foundation

enum RemoteMatchDecision: Equatable {
    case accepted
    case rejectedWrongProfile
    case needsVerification
}

enum RemoteProfile: String, CaseIterable {
    case chromecast
    case xiaomiRC003

    var title: String { self == .chromecast ? "Google" : L("小米 RC003") }
    var vendorID: Int { self == .chromecast ? 0x18D1 : 0x2717 }
    var productID: Int { self == .chromecast ? 0x9450 : 0x32B8 }
    var mappingKey: String { self == .chromecast ? "keyMappings.v1" : "keyMappings.xiaomiRC003.v1" }

    var mouseMappingKey: String { mappingKey + ".mouse" }

    private static func isKnownXiaomiName(_ normalized: String) -> Bool {
        ["小米蓝牙语音遥控器", "mi rc", "xiaomi bluetooth remote 2 pro"].contains(normalized)
    }

    func accepts(name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        switch self {
        case .chromecast:
            guard !Self.isKnownXiaomiName(normalized) else { return false }
            return normalized == "chromecast remote" ||
                normalized == "google tv remote" ||
                normalized == "google tv streamer remote" ||
                normalized.contains("chromecast") ||
                normalized.contains("google tv")
        case .xiaomiRC003:
            return Self.isKnownXiaomiName(normalized)
        }
    }

    static func parsePnPVendorID(_ data: Data) -> UInt16? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == 1 || bytes[0] == 2 else { return nil }
        return UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
    }

    func evaluateATVVDevice(name: String?, vendorID: UInt16? = nil, modelNumber: String? = nil) -> RemoteMatchDecision {
        let trimmedModel = modelNumber?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch self {
        case .chromecast:
            if vendorID == UInt16(RemoteProfile.xiaomiRC003.vendorID) ||
               trimmedModel == "RC003" ||
               RemoteProfile.xiaomiRC003.accepts(name: name) {
                return .rejectedWrongProfile
            }
            if vendorID == UInt16(self.vendorID) || accepts(name: name) {
                return .accepted
            }
            return .needsVerification
        case .xiaomiRC003:
            if trimmedModel == "RC003" { return .accepted }
            if trimmedModel != nil { return .rejectedWrongProfile }
            return accepts(name: name) ? .needsVerification : .rejectedWrongProfile
        }
    }
}
