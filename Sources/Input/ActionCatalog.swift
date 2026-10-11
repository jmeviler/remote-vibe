import AppKit

struct ActionPreset {
    let group: String
    let title: String
    let binding: ButtonAction?
}

enum ActionCatalog {
    private static func key(_ group: String, _ title: String, _ usage: UInt64, _ flags: CGEventFlags = []) -> ActionPreset {
        .init(group: group, title: title, binding: .init(kind: .key, usage: usage, modifiers: flags.rawValue))
    }
    private static func action(_ group: String, _ title: String, _ kind: ButtonAction.Kind) -> ActionPreset {
        .init(group: group, title: title, binding: .init(kind: kind))
    }

    static let presets: [ActionPreset] = [
        action(L("基本按键与选项选择"), L("原按键功能"), .original), action(L("基本按键与选项选择"), L("不执行"), .disabled),
        key(L("基本按键与选项选择"), L("Fn 按键（按住 / 松开）"), MappingKey.fnUsage),
        action(L("基本按键与选项选择"), L("遥控器麦克风（按住说话）"), .remoteVoice),
        key(L("基本按键与选项选择"), L("Enter 回车 / 确认"), 0x28), key(L("基本按键与选项选择"), L("Backspace 退格删除"), 0x2A),
        key(L("基本按键与选项选择"), L("Escape 取消"), 0x29), key(L("基本按键与选项选择"), L("Space 空格"), 0x2C),
        key(L("基本按键与选项选择"), L("Tab 下一项"), 0x2B), key(L("基本按键与选项选择"), L("Shift + Tab 上一项"), 0x2B, .maskShift),
        key(L("基本按键与选项选择"), L("Shift + Enter 换行"), 0x28, .maskShift),
        key(L("基本按键与选项选择"), L("↑ 方向上"), 0x52), key(L("基本按键与选项选择"), L("↓ 方向下"), 0x51),
        key(L("基本按键与选项选择"), L("← 方向左"), 0x50), key(L("基本按键与选项选择"), L("→ 方向右"), 0x4F),
        key(L("基本按键与选项选择"), L("Delete 向后删除"), 0x4C),

        key(L("终端 / Codex CLI"), L("中断 / 退出 · ⌃C"), 0x06, .maskControl),
        key(L("终端 / Codex CLI"), L("编辑提示词 · ⌃G"), 0x0A, .maskControl),
        key(L("终端 / Codex CLI"), L("复制 Codex 上次输出 · ⌃O"), 0x12, .maskControl),
        key(L("终端 / Codex CLI"), L("搜索输入历史 · ⌃R"), 0x15, .maskControl),
        key(L("终端 / Codex CLI"), "Shift + ←", 0x50, .maskShift),
        key(L("终端 / Codex CLI"), L("数字 1"), 0x1E),
        key(L("终端 / Codex CLI"), L("数字 2"), 0x1F),
        key(L("终端 / Codex CLI"), L("数字 3"), 0x20),
        key(L("终端 / Codex CLI"), L("数字 4"), 0x21),
        key(L("终端 / Codex CLI"), L("数字 5"), 0x22),
        key(L("终端 / Codex CLI"), L("数字 6"), 0x23),
        key(L("终端 / Codex CLI"), L("数字 7"), 0x24),
        key(L("终端 / Codex CLI"), L("数字 8"), 0x25),
        key(L("终端 / Codex CLI"), L("数字 9"), 0x26),

        key(L("剪贴板与编辑"), L("复制 · ⌘C"), 0x06, .maskCommand),
        key(L("剪贴板与编辑"), L("粘贴 · ⌘V"), 0x19, .maskCommand),
        key(L("剪贴板与编辑"), L("剪切 · ⌘X"), 0x1B, .maskCommand),
        key(L("剪贴板与编辑"), L("全选 · ⌘A"), 0x04, .maskCommand),
        key(L("剪贴板与编辑"), L("粘贴并匹配样式 · ⌥⇧⌘V"), 0x19, [.maskAlternate, .maskShift, .maskCommand]),
        key(L("剪贴板与编辑"), L("撤销 · ⌘Z"), 0x1D, .maskCommand),
        key(L("剪贴板与编辑"), L("重做 · ⇧⌘Z"), 0x1D, [.maskShift, .maskCommand]),
        key(L("剪贴板与编辑"), L("保存 · ⌘S"), 0x16, .maskCommand),
        key(L("剪贴板与编辑"), L("另存为 · ⇧⌘S"), 0x16, [.maskShift, .maskCommand]),
        key(L("剪贴板与编辑"), L("删除前一个词 · ⌥⌫"), 0x2A, .maskAlternate),
        key(L("剪贴板与编辑"), L("删除到行首 · ⌘⌫"), 0x2A, .maskCommand),
        action(L("剪贴板与编辑"), L("输入常用文本"), .text),

        key(L("搜索"), L("查找 · ⌘F"), 0x09, .maskCommand),
        key(L("搜索"), L("查找下一个 · ⌘G"), 0x0A, .maskCommand),
        key(L("搜索"), L("查找上一个 · ⇧⌘G"), 0x0A, [.maskShift, .maskCommand]),
        key(L("搜索"), L("Spotlight 搜索 · ⌘Space"), 0x2C, .maskCommand),

        key(L("应用与窗口"), L("Command + Tab 切换应用"), 0x2B, .maskCommand),
        key(L("应用与窗口"), L("Command + Shift + Tab 反向切换应用"), 0x2B, [.maskCommand, .maskShift]),
        key(L("应用与窗口"), L("切换当前应用窗口 · ⌘`"), 0x35, .maskCommand),
        action(L("应用与窗口"), L("切换当前屏幕窗口"), .nextWindow),
        action(L("应用与窗口"), L("切换屏幕"), .nextDisplay),
        key(L("应用与窗口"), L("新建窗口 / 文档 · ⌘N"), 0x11, .maskCommand),
        key(L("应用与窗口"), L("关闭当前标签 / 窗口 · ⌘W"), 0x1A, .maskCommand),
        key(L("应用与窗口"), L("最小化窗口 · ⌘M"), 0x10, .maskCommand),
        key(L("应用与窗口"), L("隐藏当前应用 · ⌘H"), 0x0B, .maskCommand),
        key(L("应用与窗口"), L("进入 / 退出全屏 · ⌃⌘F"), 0x09, [.maskControl, .maskCommand]),
        key(L("应用与窗口"), L("打开应用设置 · ⌘,"), 0x36, .maskCommand),
        key(L("应用与窗口"), "Mission Control · ⌃↑", 0x52, .maskControl),
        key(L("应用与窗口"), L("当前应用所有窗口 · ⌃↓"), 0x51, .maskControl),
        key(L("应用与窗口"), L("上一个桌面空间 · ⌃←"), 0x50, .maskControl),
        key(L("应用与窗口"), L("下一个桌面空间 · ⌃→"), 0x4F, .maskControl),
        action(L("应用与窗口"), L("打开指定应用…"), .openApp),

        key(L("网页与标签"), L("新建标签 · ⌘T"), 0x17, .maskCommand),
        key(L("网页与标签"), L("恢复关闭的标签 · ⇧⌘T"), 0x17, [.maskShift, .maskCommand]),
        key(L("网页与标签"), "Control + Tab", 0x2B, .maskControl),
        key(L("网页与标签"), "Control + Shift + Tab", 0x2B, [.maskControl, .maskShift]),
        key(L("网页与标签"), L("地址栏 / 打开位置 · ⌘L"), 0x0F, .maskCommand),
        key(L("网页与标签"), L("刷新 · ⌘R"), 0x15, .maskCommand),
        key(L("网页与标签"), L("后退 · ⌘["), 0x2F, .maskCommand),
        key(L("网页与标签"), L("前进 · ⌘]"), 0x30, .maskCommand),
        key(L("网页与标签"), L("放大 · ⌘+"), 0x2E, [.maskCommand, .maskShift]),
        key(L("网页与标签"), L("缩小 · ⌘−"), 0x2D, .maskCommand),
        key(L("网页与标签"), L("恢复缩放 · ⌘0"), 0x27, .maskCommand),
        action(L("网页与标签"), L("打开指定网页…"), .openURL),

        action(L("滚动与光标"), L("向上滚动"), .scrollUp), action(L("滚动与光标"), L("向下滚动"), .scrollDown),
        action(L("滚动与光标"), L("向左滚动"), .scrollLeft), action(L("滚动与光标"), L("向右滚动"), .scrollRight),
        key(L("滚动与光标"), L("向上翻页 · Page Up"), 0x4B), key(L("滚动与光标"), L("向下翻页 · Page Down"), 0x4E),
        key(L("滚动与光标"), L("到文档开头 · ⌘↑"), 0x52, .maskCommand),
        key(L("滚动与光标"), L("到文档结尾 · ⌘↓"), 0x51, .maskCommand),
        key(L("滚动与光标"), L("到行首 · ⌘←"), 0x50, .maskCommand),
        key(L("滚动与光标"), L("到行尾 · ⌘→"), 0x4F, .maskCommand),
        key(L("滚动与光标"), L("前一个词 · ⌥←"), 0x50, .maskAlternate),
        key(L("滚动与光标"), L("后一个词 · ⌥→"), 0x4F, .maskAlternate),
        key(L("滚动与光标"), L("向左选择 · ⇧←"), 0x50, .maskShift),
        key(L("滚动与光标"), L("向右选择 · ⇧→"), 0x4F, .maskShift),
        key(L("滚动与光标"), L("选择到行首 · ⇧⌘←"), 0x50, [.maskShift, .maskCommand]),
        key(L("滚动与光标"), L("选择到行尾 · ⇧⌘→"), 0x4F, [.maskShift, .maskCommand]),

        key(L("截屏与系统"), L("截取整个屏幕 · ⇧⌘3"), 0x20, [.maskShift, .maskCommand]),
        key(L("截屏与系统"), L("截取选定区域 · ⇧⌘4"), 0x21, [.maskShift, .maskCommand]),
        key(L("截屏与系统"), L("截屏 / 录屏工具栏 · ⇧⌘5"), 0x22, [.maskShift, .maskCommand]),
        key(L("截屏与系统"), L("区域截屏到剪贴板 · ⌃⇧⌘4"), 0x21, [.maskControl, .maskShift, .maskCommand]),
        key(L("截屏与系统"), L("表情与符号 · ⌃⌘Space"), 0x2C, [.maskControl, .maskCommand]),
        key(L("截屏与系统"), L("切换输入法 · ⌃Space"), 0x2C, .maskControl),
        key(L("截屏与系统"), L("锁定屏幕 · ⌃⌘Q"), 0x14, [.maskControl, .maskCommand])
    ] + SystemControl.allCases.map {
        .init(group: L("音量、亮度与媒体"), title: $0.title, binding: .init(kind: .systemKey, usage: $0.rawValue))
    } + [.init(group: L("自定义"), title: L("自定义按键 / 组合快捷键…"), binding: nil)]

    static func index(for binding: ButtonAction) -> Int {
        presets.firstIndex {
            $0.binding == binding || ([.text, .openApp, .openURL].contains(binding.kind) && $0.binding?.kind == binding.kind)
        } ?? presets.count - 1
    }

    static func displayName(_ binding: ButtonAction) -> String {
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
        case .volumeUp: return L("提高音量")
        case .volumeDown: return L("降低音量")
        case .brightnessUp: return L("提高屏幕亮度")
        case .brightnessDown: return L("降低屏幕亮度")
        case .mute: return L("静音 / 取消静音")
        case .playPause: return L("播放 / 暂停")
        case .nextTrack: return L("下一首")
        case .previousTrack: return L("上一首")
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
