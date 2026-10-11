import AppKit

struct ActionPreset {
    let group: String
    let title: String
    let binding: KeyBinding?
}

enum ActionCatalog {
    private static func key(_ group: String, _ title: String, _ usage: UInt64, _ flags: CGEventFlags = []) -> ActionPreset {
        .init(group: group, title: title, binding: .init(kind: .key, usage: usage, modifiers: flags.rawValue))
    }
    private static func action(_ group: String, _ title: String, _ kind: KeyBinding.Kind) -> ActionPreset {
        .init(group: group, title: title, binding: .init(kind: kind))
    }

    static let presets: [ActionPreset] = [
        action("基本按键", "原按键功能", .original), action("基本按键", "不执行", .disabled),
        key("基本按键", "Fn（按住 / 松开）", MappingKey.fnUsage),
        key("基本按键", "Enter 回车 / 确认", 0x28), key("基本按键", "Backspace 退格删除", 0x2A),
        key("基本按键", "Escape 取消", 0x29), key("基本按键", "Space 空格", 0x2C),
        key("基本按键", "Tab 下一项", 0x2B), key("基本按键", "Shift + Tab 上一项", 0x2B, .maskShift),
        key("基本按键", "Shift + Enter 换行", 0x28, .maskShift),
        key("基本按键", "↑ 方向上", 0x52), key("基本按键", "↓ 方向下", 0x51),
        key("基本按键", "← 方向左", 0x50), key("基本按键", "→ 方向右", 0x4F),
        key("基本按键", "Delete 向后删除", 0x4C),

        key("剪贴板与编辑", "复制 · ⌘C", 0x06, .maskCommand),
        key("剪贴板与编辑", "粘贴 · ⌘V", 0x19, .maskCommand),
        key("剪贴板与编辑", "剪切 · ⌘X", 0x1B, .maskCommand),
        key("剪贴板与编辑", "全选 · ⌘A", 0x04, .maskCommand),
        key("剪贴板与编辑", "粘贴并匹配样式 · ⌥⇧⌘V", 0x19, [.maskAlternate, .maskShift, .maskCommand]),
        key("剪贴板与编辑", "撤销 · ⌘Z", 0x1D, .maskCommand),
        key("剪贴板与编辑", "重做 · ⇧⌘Z", 0x1D, [.maskShift, .maskCommand]),
        key("剪贴板与编辑", "保存 · ⌘S", 0x16, .maskCommand),
        key("剪贴板与编辑", "另存为 · ⇧⌘S", 0x16, [.maskShift, .maskCommand]),
        key("剪贴板与编辑", "删除前一个词 · ⌥⌫", 0x2A, .maskAlternate),
        key("剪贴板与编辑", "删除到行首 · ⌘⌫", 0x2A, .maskCommand),
        action("剪贴板与编辑", "输入常用文本", .text),

        key("搜索", "查找 · ⌘F", 0x09, .maskCommand),
        key("搜索", "查找下一个 · ⌘G", 0x0A, .maskCommand),
        key("搜索", "查找上一个 · ⇧⌘G", 0x0A, [.maskShift, .maskCommand]),
        key("搜索", "Spotlight 搜索 · ⌘Space", 0x2C, .maskCommand),

        key("应用与窗口", "Command + Tab 切换应用", 0x2B, .maskCommand),
        key("应用与窗口", "Command + Shift + Tab 反向切换应用", 0x2B, [.maskCommand, .maskShift]),
        key("应用与窗口", "切换当前应用窗口 · ⌘`", 0x35, .maskCommand),
        action("应用与窗口", "切换当前屏幕窗口", .nextWindow),
        action("应用与窗口", "切换屏幕", .nextDisplay),
        key("应用与窗口", "新建窗口 / 文档 · ⌘N", 0x11, .maskCommand),
        key("应用与窗口", "关闭当前标签 / 窗口 · ⌘W", 0x1A, .maskCommand),
        key("应用与窗口", "最小化窗口 · ⌘M", 0x10, .maskCommand),
        key("应用与窗口", "隐藏当前应用 · ⌘H", 0x0B, .maskCommand),
        key("应用与窗口", "进入 / 退出全屏 · ⌃⌘F", 0x09, [.maskControl, .maskCommand]),
        key("应用与窗口", "打开应用设置 · ⌘,", 0x36, .maskCommand),
        key("应用与窗口", "Mission Control · ⌃↑", 0x52, .maskControl),
        key("应用与窗口", "当前应用所有窗口 · ⌃↓", 0x51, .maskControl),
        key("应用与窗口", "上一个桌面空间 · ⌃←", 0x50, .maskControl),
        key("应用与窗口", "下一个桌面空间 · ⌃→", 0x4F, .maskControl),
        action("应用与窗口", "打开指定应用…", .openApp),

        key("网页与标签", "新建标签 · ⌘T", 0x17, .maskCommand),
        key("网页与标签", "恢复关闭的标签 · ⇧⌘T", 0x17, [.maskShift, .maskCommand]),
        key("网页与标签", "Control + Tab", 0x2B, .maskControl),
        key("网页与标签", "Control + Shift + Tab", 0x2B, [.maskControl, .maskShift]),
        key("网页与标签", "地址栏 / 打开位置 · ⌘L", 0x0F, .maskCommand),
        key("网页与标签", "刷新 · ⌘R", 0x15, .maskCommand),
        key("网页与标签", "后退 · ⌘[", 0x2F, .maskCommand),
        key("网页与标签", "前进 · ⌘]", 0x30, .maskCommand),
        key("网页与标签", "放大 · ⌘+", 0x2E, [.maskCommand, .maskShift]),
        key("网页与标签", "缩小 · ⌘−", 0x2D, .maskCommand),
        key("网页与标签", "恢复缩放 · ⌘0", 0x27, .maskCommand),
        action("网页与标签", "打开指定网页…", .openURL),

        action("滚动与光标", "向上滚动", .scrollUp), action("滚动与光标", "向下滚动", .scrollDown),
        action("滚动与光标", "向左滚动", .scrollLeft), action("滚动与光标", "向右滚动", .scrollRight),
        key("滚动与光标", "向上翻页 · Page Up", 0x4B), key("滚动与光标", "向下翻页 · Page Down", 0x4E),
        key("滚动与光标", "到文档开头 · ⌘↑", 0x52, .maskCommand),
        key("滚动与光标", "到文档结尾 · ⌘↓", 0x51, .maskCommand),
        key("滚动与光标", "到行首 · ⌘←", 0x50, .maskCommand),
        key("滚动与光标", "到行尾 · ⌘→", 0x4F, .maskCommand),
        key("滚动与光标", "前一个词 · ⌥←", 0x50, .maskAlternate),
        key("滚动与光标", "后一个词 · ⌥→", 0x4F, .maskAlternate),
        key("滚动与光标", "向左选择 · ⇧←", 0x50, .maskShift),
        key("滚动与光标", "向右选择 · ⇧→", 0x4F, .maskShift),
        key("滚动与光标", "选择到行首 · ⇧⌘←", 0x50, [.maskShift, .maskCommand]),
        key("滚动与光标", "选择到行尾 · ⇧⌘→", 0x4F, [.maskShift, .maskCommand]),

        key("截屏与系统", "截取整个屏幕 · ⇧⌘3", 0x20, [.maskShift, .maskCommand]),
        key("截屏与系统", "截取选定区域 · ⇧⌘4", 0x21, [.maskShift, .maskCommand]),
        key("截屏与系统", "截屏 / 录屏工具栏 · ⇧⌘5", 0x22, [.maskShift, .maskCommand]),
        key("截屏与系统", "区域截屏到剪贴板 · ⌃⇧⌘4", 0x21, [.maskControl, .maskShift, .maskCommand]),
        key("截屏与系统", "表情与符号 · ⌃⌘Space", 0x2C, [.maskControl, .maskCommand]),
        key("截屏与系统", "切换输入法 · ⌃Space", 0x2C, .maskControl),
        key("截屏与系统", "锁定屏幕 · ⌃⌘Q", 0x14, [.maskControl, .maskCommand])
    ] + SystemControl.allCases.map {
        .init(group: "音量、亮度与媒体", title: $0.title, binding: .init(kind: .systemKey, usage: $0.rawValue))
    } + [.init(group: "自定义", title: "自定义按键 / 组合快捷键…", binding: nil)]

    static func index(for binding: KeyBinding) -> Int {
        presets.firstIndex {
            $0.binding == binding || ([.text, .openApp, .openURL].contains(binding.kind) && $0.binding?.kind == binding.kind)
        } ?? presets.count - 1
    }

    static func displayName(_ binding: KeyBinding) -> String {
        if [.openApp, .openURL].contains(binding.kind) { return binding.title }
        return presets[index(for: binding)].binding == nil ? binding.title : presets[index(for: binding)].title
    }
}

// macOS auxiliary key types from IOKit/hidsystem/ev_keymap.h.
enum SystemControl: UInt64, CaseIterable {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case playPause = 16, nextTrack = 17, previousTrack = 18

    var title: String {
        switch self {
        case .volumeUp: return "提高音量"
        case .volumeDown: return "降低音量"
        case .brightnessUp: return "提高屏幕亮度"
        case .brightnessDown: return "降低屏幕亮度"
        case .mute: return "静音 / 取消静音"
        case .playPause: return "播放 / 暂停"
        case .nextTrack: return "下一首"
        case .previousTrack: return "上一首"
        }
    }

    // Construct both phases before posting, so allocation failure cannot leave a key down.
    func events() -> [CGEvent]? {
        var events: [CGEvent] = []
        for phase in [0xA, 0xB] {
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(phase << 8)), timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8,
                data1: (Int(rawValue) << 16) | (phase << 8), data2: -1)?.cgEvent else { return nil }
            events.append(event)
        }
        return events
    }
}
