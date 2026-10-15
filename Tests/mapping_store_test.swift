import Foundation

enum MappingStoreTests {
    static func run() throws {
        let suite = "RemoteVibe.MappingTests.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = MappingStore(preferences: prefs)
        let original: KeyMapping.Bindings = ["7": .init(singleClick: .init(kind: .key, usage: 0x28)),
                                             "8": .init(singleClick: .init(kind: .text, text: "你好\n🙂"))]
        let changed: KeyMapping.Bindings = ["7": .init(singleClick: .init(kind: .disabled)),
                                            "8": .init(singleClick: .init(kind: .key, usage: 0x52))]
        for profile in RemoteProfile.allCases {
            precondition(store.load(profile).bindings.isEmpty && !store.load(profile).recovered)
            // Use keys shared by both models for the stored maps.
            let valid = profile == .chromecast ? original : ["7": original["7"]!]
            try store.save(valid, profile: profile, mouse: false)
            precondition(store.load(profile).bindings == valid)
            precondition(store.backup(profile, mouse: false) == valid)
        }
        try store.save(changed, profile: .chromecast, mouse: false)
        precondition(store.backup(.chromecast, mouse: false) == original)
        let mouse: KeyMapping.Bindings = ["7": .init(singleClick: .init(kind: .mouseRightClick))]
        try store.save(mouse, profile: .chromecast, mouse: true)
        // One future action and one valid entry: recover only the damaged button.
        let validEntry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed["8"]!))
        let damaged = try JSONSerialization.data(withJSONObject: ["7": ["kind": "futureAction"], "8": validEntry, "999": ["kind": "original"]])
        prefs.set(damaged, forKey: RemoteProfile.chromecast.mappingKey)
        let recovered = store.load(.chromecast)
        precondition(recovered.recovered && recovered.bindings["7"] == original["7"] && recovered.bindings["8"] == changed["8"])
        precondition(recovered.bindings["999"] == nil)
        precondition(store.load(.chromecast, mouse: true).bindings == mouse)
        precondition(store.load(.xiaomiRC003).bindings == ["7": original["7"]!])
        // Reading, including UI previews, must not write preferences.
        precondition(prefs.data(forKey: RemoteProfile.chromecast.mappingKey) == damaged)
        precondition(prefs.data(forKey: RemoteProfile.chromecast.mappingKey + ".recovery.v1") == nil)
        try store.save(recovered.bindings, profile: .chromecast, mouse: false)
        precondition(prefs.data(forKey: RemoteProfile.chromecast.mappingKey + ".recovery.v1") == damaged)
        precondition(store.backup(.chromecast, mouse: false) == original)
        precondition(!store.load(.chromecast).recovered)
        try store.save(changed, profile: .chromecast, mouse: false)
        precondition(prefs.data(forKey: RemoteProfile.chromecast.mappingKey + ".recovery.v1") == damaged)
        prefs.set(Data("broken json".utf8), forKey: RemoteProfile.chromecast.mappingKey)
        precondition(store.load(.chromecast).bindings == recovered.bindings && store.load(.chromecast).recovered)
        prefs.removeObject(forKey: RemoteProfile.chromecast.mappingKey + ".backup.v1")
        let disabled = store.load(.chromecast)
        precondition(disabled.recovered && disabled.bindings.count == MappedButton.chromecast.count)
        precondition(disabled.bindings.values.allSatisfy { $0.singleClick.kind == .disabled })
        prefs.set(try JSONSerialization.data(withJSONObject: ["7": ["kind": "futureAction"], "8": validEntry]), forKey: RemoteProfile.chromecast.mappingKey)
        precondition(store.load(.chromecast).bindings["7"]?.singleClick.kind == .disabled)
        precondition(store.load(.chromecast).bindings["8"] == changed["8"])

        let archive = MappingArchive(profile: .chromecast, normal: original, mouse: mouse)
        let data = try archive.data()
        let decoded = try MappingArchive.read(data, for: .chromecast)
        precondition(decoded.normal == original && decoded.mouse == mouse)
        func refuses(_ data: Data, profile: RemoteProfile = .chromecast) {
            do { _ = try MappingArchive.read(data, for: profile); preconditionFailure("Invalid archive accepted") }
            catch {}
        }
        refuses(data, profile: .xiaomiRC003)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["version"] = 2
        refuses(try JSONSerialization.data(withJSONObject: json))
        json["version"] = 1; json["normal"] = ["7": ["kind": "futureAction"]]
        refuses(try JSONSerialization.data(withJSONObject: json))
        json["normal"] = ["999": ["kind": "disabled", "usage": 40, "modifiers": 0]]
        refuses(try JSONSerialization.data(withJSONObject: json))
        refuses(Data(repeating: 32, count: MappingArchive.maximumBytes + 1))
        let invalidMouse = MappingArchive(profile: .chromecast, normal: original,
                                          mouse: ["7": .init(singleClick: .init(kind: .toggleMouseMode))])
        do { _ = try invalidMouse.data(); preconditionFailure("Invalid mouse archive exported") } catch {}
        print("PASS: per-button recovery, raw-data preservation, valid backups, model/mode isolation and validated configuration import/export (isolated preferences).")
    }
}
