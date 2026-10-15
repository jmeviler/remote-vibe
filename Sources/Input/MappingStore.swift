import Foundation

// Keep the existing preference keys and JSON format. A bad entry must not discard
// every other button, and a subsequent save must preserve the original bytes.
struct MappingStore {
    let preferences: UserDefaults
    init(preferences: UserDefaults = .standard) { self.preferences = preferences }
    struct Loaded {
        var bindings: KeyMapping.Bindings
        var recovered: Bool
    }
    private func key(_ profile: RemoteProfile, _ mouse: Bool) -> String { mouse ? profile.mouseMappingKey : profile.mappingKey }

    static func decode(_ data: Data, profile: RemoteProfile, mouse: Bool) -> Loaded? {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let codes = Set(MappedButton.buttons(for: profile).map { String($0.code) })
        var result = Loaded(bindings: [:], recovered: false)
        for (code, value) in entries {
            guard codes.contains(code) else { result.recovered = true; continue }
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
                  let binding = try? JSONDecoder().decode(ButtonBinding.self, from: data),
                  binding.validationMessage(for: profile) == nil, !mouse || !binding.togglesMouseMode else {
                result.recovered = true
                // Suppress damaged keys until the user repairs them or a backup is found.
                result.bindings[code] = .init(singleClick: .init(kind: .disabled))
                continue
            }
            result.bindings[code] = binding
        }
        return result
    }

    func backup(_ profile: RemoteProfile, mouse: Bool) -> KeyMapping.Bindings? {
        guard let data = preferences.data(forKey: key(profile, mouse) + ".backup.v1"),
              let loaded = Self.decode(data, profile: profile, mouse: mouse), !loaded.recovered else { return nil }
        return loaded.bindings
    }

    func load(_ profile: RemoteProfile, mouse: Bool = false) -> Loaded {
        guard let data = preferences.data(forKey: key(profile, mouse)) else { return .init(bindings: [:], recovered: false) }
        let fallback = backup(profile, mouse: mouse)
        guard var result = Self.decode(data, profile: profile, mouse: mouse) else {
            // With no readable map or backup, disable the keys rather than silently
            // replacing user-defined disabled keys with their native actions.
            let disabled = Dictionary(uniqueKeysWithValues: MappedButton.buttons(for: profile).map {
                (String($0.code), ButtonBinding(singleClick: .init(kind: .disabled)))
            })
            return .init(bindings: fallback ?? disabled, recovered: true)
        }
        if result.recovered, let fallback,
           let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (code, value) in entries where result.bindings[code] != nil {
                let single = try? JSONSerialization.data(withJSONObject: [code: value])
                if let single, Self.decode(single, profile: profile, mouse: mouse)?.recovered == true, let saved = fallback[code] {
                    result.bindings[code] = saved
                }
            }
        }
        return result
    }

    func save(_ bindings: KeyMapping.Bindings, profile: RemoteProfile, mouse: Bool) throws {
        let data = try JSONEncoder().encode(bindings)
        guard let decoded = Self.decode(data, profile: profile, mouse: mouse), !decoded.recovered else { throw MappingArchive.Failure.invalid }
        let name = key(profile, mouse)
        if let old = preferences.data(forKey: name) {
            if let decoded = Self.decode(old, profile: profile, mouse: mouse), !decoded.recovered {
                preferences.set(old, forKey: name + ".backup.v1")
            } else {
                preferences.set(old, forKey: name + ".recovery.v1")
            }
        }
        if preferences.data(forKey: name + ".backup.v1") == nil { preferences.set(data, forKey: name + ".backup.v1") }
        preferences.set(data, forKey: name)
    }
}

struct MappingArchive: Codable {
    static let maximumBytes = 1024 * 1024
    let version: Int
    let profile: String
    let normal: KeyMapping.Bindings
    let mouse: KeyMapping.Bindings

    enum Failure: LocalizedError {
        case invalid, wrongProfile, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: return L("配置文件无效或版本不支持，未修改当前键位")
            case .wrongProfile: return L("配置文件的遥控器型号不匹配，请先切换型号")
            case .tooLarge: return L("配置文件超过 1 MB，未导入或导出")
            }
        }
    }
    init(profile: RemoteProfile, normal: KeyMapping.Bindings, mouse: KeyMapping.Bindings) {
        version = 1; self.profile = profile.rawValue; self.normal = normal; self.mouse = mouse
    }
    private func validate(for profile: RemoteProfile) throws {
        guard version == 1 else { throw Failure.invalid }
        guard self.profile == profile.rawValue else { throw Failure.wrongProfile }
        for (values, isMouse) in [(normal, false), (mouse, true)] {
            let data = try JSONEncoder().encode(values)
            guard let decoded = MappingStore.decode(data, profile: profile, mouse: isMouse), !decoded.recovered else { throw Failure.invalid }
        }
    }
    static func read(_ data: Data, for profile: RemoteProfile) throws -> MappingArchive {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard let archive = try? JSONDecoder().decode(Self.self, from: data) else { throw Failure.invalid }
        try archive.validate(for: profile)
        return archive
    }
    func data() throws -> Data {
        guard let profile = RemoteProfile(rawValue: profile) else { throw Failure.invalid }
        try validate(for: profile)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        return data
    }
}
