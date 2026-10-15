import Foundation

// Only stable major.minor.patch releases with our ready-to-download app archive count.
struct ReleaseUpdate: Decodable {
    enum Architecture: String, CaseIterable {
        case appleSilicon = "AppleSilicon", intel = "Intel"
        static var current: Architecture {
            #if arch(arm64)
            return .appleSilicon
            #elseif arch(x86_64)
            return .intel
            #else
            #error("Unsupported Mac architecture")
            #endif
        }
    }
    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    static let releasesURL = URL(string: "https://github.com/jmeviler/remote-vibe/releases")!

    static func version(_ text: String) -> [Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }

    func message(installed: String, architecture: Architecture = .current) -> String {
        guard !draft, !prerelease, let latest = Self.version(tag_name), let current = Self.version(installed) else {
            return L("发布版本无法识别，请打开发布页")
        }
        guard current.lexicographicallyPrecedes(latest) else {
            return current == latest ? L("已是最新版本 %@", installed) : L("当前 %@ 比正式版 %@ 更新", installed, tag_name)
        }
        let version = tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        let name = "Remote-Vibe-\(version)-App-\(architecture.rawValue).zip"
        guard assets.contains(where: { $0.name == name && $0.state == "uploaded" && $0.size > 0 }) else {
            return L("发现 %@，下载包尚未就绪", tag_name)
        }
        return L("可下载新版本 %@ · 打开发布页", tag_name)
    }
}
