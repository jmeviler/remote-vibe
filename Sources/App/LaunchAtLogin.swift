import Foundation
import ServiceManagement

enum LaunchAtLoginState: String, Equatable {
    case enabled
    case notRegistered = "not-registered"
    case requiresApproval = "requires-approval"
    case notFound = "not-found"
}

protocol LaunchAtLoginService {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct SystemLaunchAtLoginService: LaunchAtLoginService {
    var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class LaunchAtLoginController {
    private let service: LaunchAtLoginService

    init(service: LaunchAtLoginService = SystemLaunchAtLoginService()) {
        self.service = service
    }

    var state: LaunchAtLoginState { service.state }

    func toggle() -> String {
        switch service.state {
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
                return L("已关闭登录时自动打开")
            } catch {
                return L("无法更改登录启动项，请在系统设置中检查")
            }
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                if service.state != .requiresApproval {
                    return L("无法开启登录时自动打开，请将应用放入“应用程序”后重试")
                }
            }
            switch service.state {
            case .enabled:
                return L("已开启登录时自动打开")
            case .requiresApproval:
                service.openSystemSettings()
                return L("请在“系统设置 → 通用 → 登录项”中允许 Remote Vibe")
            case .notRegistered, .notFound:
                return L("无法开启登录时自动打开，请将应用放入“应用程序”后重试")
            }
        }
    }
}
