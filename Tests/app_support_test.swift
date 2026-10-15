import Foundation

@main
enum AppSupportTest {
    static func main() throws {
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
        print("PASS: stable release comparison and architecture-specific download readiness (no network).")
    }
}
