import Foundation

private final class FakeLaunchService: LaunchAtLoginService {
    var state: LaunchAtLoginState = .notRegistered
    var nextRegisterState: LaunchAtLoginState = .enabled
    var failRegister = false
    var failUnregister = false
    var openedSettings = 0

    func register() throws {
        if failRegister {
            struct RegisterError: Error {}
            throw RegisterError()
        }
        state = nextRegisterState
    }

    func unregister() throws {
        if failUnregister {
            struct UnregisterError: Error {}
            throw UnregisterError()
        }
        state = .notRegistered
    }

    func openSystemSettings() { openedSettings += 1 }
}

@main
enum AppSupportTest {
    static func main() throws {
        try checkReleases()
        try checkStatusWriter()
        checkLaunchAtLogin()
        checkRemoteProfileMatching()
        print("PASS: stable release comparison, async status writer, launch-at-login states and Bluetooth model matching (no network or system changes).")
    }

    private static func checkReleases() throws {
        func release(_ version: String, asset: Bool = true, draft: Bool = false, prerelease: Bool = false,
                     architecture: ReleaseUpdate.Architecture = .current, state: String = "uploaded", size: Int = 1024) throws -> ReleaseUpdate {
            let number = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let json: [String: Any] = ["tag_name": version, "draft": draft, "prerelease": prerelease,
                "assets": asset ? [["name": "Remote-Vibe-\(number)-App-\(architecture.rawValue).zip", "state": state, "size": size]] : []]
            return try JSONDecoder().decode(ReleaseUpdate.self, from: JSONSerialization.data(withJSONObject: json))
        }
        // Real release boundaries: numeric ordering, development versions and incomplete uploads.
        let newer = try release("v0.4.10")
        precondition(newer.message(installed: "0.4.9") == L("可下载新版本 %@ · 打开发布页", "v0.4.10"))
        precondition(newer.message(installed: "0.4.10") == L("已是最新版本 %@", "0.4.10"))
        precondition(newer.message(installed: "0.5.0") == L("当前 %@ 比正式版 %@ 更新", "0.5.0", "v0.4.10"))
        let incomplete = try release("v0.4.10", asset: false)
        precondition(incomplete.message(installed: "0.4.9") == L("发现 %@，下载包尚未就绪", "v0.4.10"))
        for architecture in ReleaseUpdate.Architecture.allCases {
            let matching = try release("v0.4.10", architecture: architecture)
            let other: ReleaseUpdate.Architecture = architecture == .intel ? .appleSilicon : .intel
            precondition(matching.message(installed: "0.4.9", architecture: architecture) == L("可下载新版本 %@ · 打开发布页", "v0.4.10"))
            precondition(matching.message(installed: "0.4.9", architecture: other) == L("发现 %@，下载包尚未就绪", "v0.4.10"))
            for pending in [try release("v0.4.10", architecture: architecture, state: "new"),
                            try release("v0.4.10", architecture: architecture, size: 0)] {
                precondition(pending.message(installed: "0.4.9", architecture: architecture) == L("发现 %@，下载包尚未就绪", "v0.4.10"))
            }
        }
        for hidden in [try release("v0.4.10", draft: true), try release("v0.4.10", prerelease: true)] {
            precondition(hidden.message(installed: "0.4.9") == L("发布版本无法识别，请打开发布页"))
        }
        for invalid in ["", "1.2", "1.2.3-beta", "1.2.3.4", "-1.2.3", "1.2.x", "1..3", " 1.2.3", "99999999999999999999.1.2"] {
            precondition(ReleaseUpdate.version(invalid) == nil)
        }
    }

    private static func checkStatusWriter() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteVibeStatusTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("status.json")
        let writer = StatusWriter(url: file, debounceInterval: 0.04)
        for step in 1...5 {
            writer.schedule(["step": step, "active": true])
        }
        writer.flushSync()
        let firstData = try Data(contentsOf: file)
        let firstJSON = try JSONSerialization.jsonObject(with: firstData) as! [String: Any]
        precondition(firstJSON["step"] as? Int == 5)
        let firstStamp = firstJSON["updated"] as? String
        precondition(firstStamp != nil)

        Thread.sleep(forTimeInterval: 0.02)
        writer.flushSync(["step": 5, "active": true]) // Identical snapshot must not rewrite file.
        let unchangedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(unchangedJSON["updated"] as? String == firstStamp)

        writer.flushSync(["step": 6, "active": false])
        let updatedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(updatedJSON["step"] as? Int == 6 && updatedJSON["active"] as? Bool == false)
    }

    private static func checkLaunchAtLogin() {
        let service = FakeLaunchService()
        let controller = LaunchAtLoginController(service: service)
        precondition(controller.state == .notRegistered)
        precondition(controller.toggle() == L("已开启登录时自动打开") && controller.state == .enabled)
        precondition(controller.toggle() == L("已关闭登录时自动打开") && controller.state == .notRegistered)

        service.nextRegisterState = .requiresApproval
        precondition(controller.toggle() == L("请在“系统设置 → 通用 → 登录项”中允许 Remote Vibe"))
        precondition(controller.state == .requiresApproval && service.openedSettings == 1)
        precondition(controller.toggle() == L("已关闭登录时自动打开") && controller.state == .notRegistered)

        service.failRegister = true
        precondition(controller.toggle() == L("无法开启登录时自动打开，请将应用放入“应用程序”后重试"))
    }

    private static func checkRemoteProfileMatching() {
        let google = RemoteProfile.chromecast
        let xiaomi = RemoteProfile.xiaomiRC003
        for name in ["Chromecast Remote", "Google TV Remote", "Google TV Streamer Remote", "Chromecast HD Remote"] {
            precondition(google.accepts(name: name) && !xiaomi.accepts(name: name))
            precondition(google.evaluateATVVDevice(name: name) == .accepted)
        }
        for name in ["小米蓝牙语音遥控器", "Mi RC", "Xiaomi Bluetooth Remote 2 Pro"] {
            precondition(xiaomi.accepts(name: name) && !google.accepts(name: name))
            precondition(google.evaluateATVVDevice(name: name) == .rejectedWrongProfile)
        }
        // Renamed remote in macOS Bluetooth settings: allowed to connect & verify via 0x180A.
        precondition(google.evaluateATVVDevice(name: "Living Room Remote") == .needsVerification)
        let googlePnP = Data([0x02, 0xD1, 0x18, 0x50, 0x94, 0x01, 0x00])
        let xiaomiPnP = Data([0x02, 0x17, 0x27, 0xB8, 0x32, 0x01, 0x00])
        precondition(RemoteProfile.parsePnPVendorID(googlePnP) == 0x18D1)
        precondition(RemoteProfile.parsePnPVendorID(xiaomiPnP) == 0x2717)
        precondition(RemoteProfile.parsePnPVendorID(Data([0x00, 0xD1, 0x18])) == nil)
        precondition(RemoteProfile.parsePnPVendorID(Data([0x02, 0xD1])) == nil)
        precondition(google.evaluateATVVDevice(name: "Living Room Remote", vendorID: 0x18D1) == .accepted)
        precondition(google.evaluateATVVDevice(name: "Living Room Remote", vendorID: 0x2717) == .rejectedWrongProfile)
        precondition(google.evaluateATVVDevice(name: "Living Room Remote", modelNumber: "RC003\n") == .rejectedWrongProfile)
    }
}
