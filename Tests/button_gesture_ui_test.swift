import AppKit

// Offscreen AppKit checks. Never saves preferences, opens HID devices or posts keys.
@main
enum ButtonGestureUITest {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let empty = try JSONEncoder().encode(KeyMapping.Bindings())
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for profile in RemoteProfile.allCases { arguments[profile.mappingKey] = empty; arguments[profile.mouseMappingKey] = empty }
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        for profile in RemoteProfile.allCases { try check(profile) }
        print("PASS [\(Bundle.main.preferredLocalizations.joined(separator: ","))]: both settings layouts, per-trigger drafts, text, Fn, validation, reset and fixed voice button (no HID or preference writes).")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    private static func change(_ control: NSControl) {
        precondition(NSApp.sendAction(control.action!, to: control.target, from: control))
    }
    private static func check(_ profile: RemoteProfile) throws {
        let mapping = KeyMapping(profile: profile)
        let view = KeyMappingView(mapping: mapping)
        view.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let all = descendants(view)
        let trigger = all.compactMap { $0 as? NSSegmentedControl }.first { $0.action == NSSelectorFromString("triggerChanged") }!
        let action = all.compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString("actionChanged") }!
        let editor = all.compactMap { $0 as? NSTextView }.first!
        let save = all.compactMap { $0 as? NSButton }.first { $0.title == L("保存并生效") }!
        let reset = all.compactMap { $0 as? NSButton }.first { $0.title == L("恢复此键默认") }!
        func choose(_ title: String) {
            precondition(action.itemTitles.contains(title))
            action.selectItem(withTitle: title); change(action)
        }
        func selectTrigger(_ index: Int) { trigger.selectedSegment = index; change(trigger) }
        func selectButton(_ code: Int) {
            let button = all.compactMap { $0 as? NSButton }.first {
                $0.tag == code && $0.action == NSSelectorFromString("selectKey:")
            }!
            change(button)
        }
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == L("未设置"))
        precondition(action.itemArray.first { $0.tag == 2 && !$0.isSectionHeader }?.isEnabled == false)
        choose(L("输入常用文本"))
        editor.string = "双击输入\nHello 🙂"
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        selectTrigger(2)
        choose(L("Fn 按键（长按后保持）"))
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == L("Enter 回车 / 确认"))
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == L("输入常用文本") && editor.string == "双击输入\nHello 🙂")
        selectButton(profile == .chromecast ? 14 : 19)
        precondition(action.titleOfSelectedItem == L("未设置"))
        selectButton(profile == .chromecast ? 8 : 7)
        precondition(editor.string == "双击输入\nHello 🙂")
        precondition(save.isEnabled)

        selectTrigger(0)
        choose(L("原按键功能"))
        precondition(!save.isEnabled)
        choose(L("Fn 按键（按住 / 松开）"))
        precondition(!save.isEnabled)
        choose(L("Enter 回车 / 确认"))
        precondition(save.isEnabled)
        selectTrigger(profile == .chromecast ? 1 : 2)
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // NSView caching omits the window background; composite it for a readable preview.
        let preview = NSImage(size: view.bounds.size)
        preview.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        view.bounds.fill()
        NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: view.bounds)
        preview.unlockFocus()
        let opaque = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        try opaque.representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: "build/tests/gestures-\(profile.rawValue).png"))

        change(reset)
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == L("未设置"))
        selectTrigger(2)
        precondition(action.titleOfSelectedItem == L("未设置"))
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == L("Enter 回车 / 确认"))
        // New actions remain independent across gestures, including editable URLs.
        choose(L("复制 · ⌘C"))
        selectTrigger(1)
        choose(L("打开指定网页…"))
        let address = all.compactMap { $0 as? NSTextField }.first { $0.delegate === view }!
        precondition(address.isEditable && !address.isHidden && !save.isEnabled)
        address.stringValue = "https://example.com/search?q=hello"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: address))
        precondition(save.isEnabled)
        selectTrigger(2)
        choose(L("播放 / 暂停"))
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == L("复制 · ⌘C"))
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == L("打开指定网页…") && address.stringValue == "https://example.com/search?q=hello")
        address.stringValue = "javascript:alert(1)"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: address))
        precondition(!save.isEnabled)
        choose(L("打开指定应用…"))
        precondition(!address.isEditable && !save.isEnabled)
        let chooser = all.compactMap { $0 as? NSButton }.first { $0.title == L("选择应用…") }!
        precondition(!chooser.isHidden && chooser.isEnabled)
        change(reset)
        selectTrigger(0)
        let voiceIndex = ActionCatalog.presets.firstIndex { $0.binding?.kind == .remoteVoice }!
        let voiceItem = action.itemArray.first { $0.tag == voiceIndex && !$0.isSectionHeader }!
        precondition(voiceItem.isHidden == (profile == .xiaomiRC003))
        if profile == .chromecast {
            choose(L("遥控器麦克风（按住说话）"))
            precondition(save.isEnabled)
            selectTrigger(2)
            choose(L("遥控器麦克风（长按后开麦）"))
            precondition(!save.isEnabled) // immediate hold cannot also wait for gestures
            selectTrigger(0)
            choose(L("Enter 回车 / 确认"))
            precondition(save.isEnabled)
            selectTrigger(1)
            precondition(!voiceItem.isEnabled)
            selectTrigger(2)
            precondition(voiceItem.isEnabled && action.titleOfSelectedItem == L("遥控器麦克风（长按后开麦）"))
        }
        change(reset)
        selectTrigger(0)
        selectButton(10)
        choose(L("切换鼠标模式"))
        let modes = all.compactMap { $0 as? NSSegmentedControl }.first { $0.action == NSSelectorFromString("modeChanged") }!
        func selectMode(_ mouse: Bool) { modes.selectedSegment = mouse ? 1 : 0; change(modes) }
        selectMode(true)
        precondition(action.titleOfSelectedItem == L("切换鼠标模式") && !action.isEnabled && !reset.isEnabled)
        selectButton(3)
        precondition(action.titleOfSelectedItem == L("鼠标向上移动") && action.isEnabled)
        choose(L("鼠标向右移动"))
        selectButton(7)
        precondition(action.titleOfSelectedItem == L("鼠标左键点击"))
        choose(L("鼠标右键点击"))
        selectButton(11)
        precondition(action.titleOfSelectedItem == L("鼠标右键点击"))
        selectMode(false)
        selectButton(3)
        precondition(action.titleOfSelectedItem != L("鼠标向右移动"))
        selectMode(true)
        precondition(action.titleOfSelectedItem == L("鼠标向右移动"))
        selectButton(7)
        precondition(action.titleOfSelectedItem == L("鼠标右键点击"))
        change(reset)
        precondition(action.titleOfSelectedItem == L("鼠标左键点击"))
        selectButton(3)
        selectTrigger(1)
        choose(L("鼠标左键点击"))
        precondition(!save.isEnabled) // Continuous single-press movement cannot wait for a double click.
        selectTrigger(0)
        choose(L("不执行"))
        precondition(save.isEnabled)
        selectMode(false)
        selectButton(10)
        change(reset)
        selectMode(true)
        precondition(action.isEnabled && !action.titleOfSelectedItem!.contains(L("切换鼠标模式")))
        for width: CGFloat in [852, 1024, 1224] {
            view.setFrameSize(NSSize(width: width, height: 574))
            view.layoutSubtreeIfNeeded()
            precondition(modes.frame.maxX <= modes.superview!.bounds.width)
            for segment in 0..<modes.segmentCount {
                let textWidth = (modes.label(forSegment: segment)! as NSString).size(withAttributes: [.font: modes.font!]).width
                precondition(textWidth + 20 < modes.bounds.width / 2)
            }
        }
        selectButton(0)
        precondition(!trigger.isEnabled && !action.isEnabled && !reset.isEnabled)
        precondition(mapping.bindings.isEmpty && !mapping.listening)
        window.orderOut(nil)
    }
}
