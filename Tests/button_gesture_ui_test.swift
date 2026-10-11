import AppKit

// Offscreen AppKit checks. Never saves preferences, opens HID devices or posts keys.
@main
enum ButtonGestureUITest {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let empty = try JSONEncoder().encode(KeyMapping.Bindings())
        UserDefaults.standard.setVolatileDomain(Dictionary(uniqueKeysWithValues:
            RemoteProfile.allCases.map { ($0.mappingKey, empty) }), forName: UserDefaults.argumentDomain)
        for profile in RemoteProfile.allCases { try check(profile) }
        print("PASS: both settings layouts, per-trigger drafts, text, Fn, validation, reset and fixed voice button (no HID or preference writes).")
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
        let trigger = all.compactMap { $0 as? NSSegmentedControl }.first!
        let action = all.compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString("actionChanged") }!
        let editor = all.compactMap { $0 as? NSTextView }.first!
        let save = all.compactMap { $0 as? NSButton }.first { $0.title == "保存并生效" }!
        let reset = all.compactMap { $0 as? NSButton }.first { $0.title == "恢复此键默认" }!
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
        precondition(action.titleOfSelectedItem == "未设置")
        precondition(action.itemArray.first { $0.title.hasPrefix("Fn（") }?.isEnabled == false)
        choose("输入常用文本")
        editor.string = "双击输入\nHello 🙂"
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        selectTrigger(2)
        choose("Fn（长按后保持，松开释放）")
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == "Enter 回车 / 确认")
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == "输入常用文本" && editor.string == "双击输入\nHello 🙂")
        selectButton(profile == .chromecast ? 14 : 19)
        precondition(action.titleOfSelectedItem == "未设置")
        selectButton(profile == .chromecast ? 8 : 7)
        precondition(editor.string == "双击输入\nHello 🙂")
        precondition(save.isEnabled)

        selectTrigger(0)
        choose("原按键功能")
        precondition(!save.isEnabled)
        choose("Fn（按住 / 松开）")
        precondition(!save.isEnabled)
        choose("Enter 回车 / 确认")
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
        precondition(action.titleOfSelectedItem == "未设置")
        selectTrigger(2)
        precondition(action.titleOfSelectedItem == "未设置")
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == "Enter 回车 / 确认")
        // New actions remain independent across gestures, including editable URLs.
        choose("复制 · ⌘C")
        selectTrigger(1)
        choose("打开指定网页…")
        let address = all.compactMap { $0 as? NSTextField }.first { $0.delegate === view }!
        precondition(address.isEditable && !address.isHidden && !save.isEnabled)
        address.stringValue = "https://example.com/search?q=hello"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: address))
        precondition(save.isEnabled)
        selectTrigger(2)
        choose("播放 / 暂停")
        selectTrigger(0)
        precondition(action.titleOfSelectedItem == "复制 · ⌘C")
        selectTrigger(1)
        precondition(action.titleOfSelectedItem == "打开指定网页…" && address.stringValue == "https://example.com/search?q=hello")
        address.stringValue = "javascript:alert(1)"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: address))
        precondition(!save.isEnabled)
        choose("打开指定应用…")
        precondition(!address.isEditable && !save.isEnabled)
        let chooser = all.compactMap { $0 as? NSButton }.first { $0.title == "选择应用…" }!
        precondition(!chooser.isHidden && chooser.isEnabled)
        change(reset)
        selectTrigger(0)
        let voiceIndex = ActionCatalog.presets.firstIndex { $0.binding?.kind == .remoteVoice }!
        let voiceItem = action.itemArray.first { $0.tag == voiceIndex && !$0.isSectionHeader }!
        precondition(voiceItem.isHidden == (profile == .xiaomiRC003))
        if profile == .chromecast {
            choose("遥控器语音（按住说话）")
            precondition(save.isEnabled)
            selectTrigger(2)
            choose("遥控器语音（长按后开麦）")
            precondition(!save.isEnabled) // immediate hold cannot also wait for gestures
            selectTrigger(0)
            choose("Enter 回车 / 确认")
            precondition(save.isEnabled)
            selectTrigger(1)
            precondition(!voiceItem.isEnabled)
            selectTrigger(2)
            precondition(voiceItem.isEnabled && action.titleOfSelectedItem == "遥控器语音（长按后开麦）")
        }
        change(reset)
        selectButton(0)
        precondition(!trigger.isEnabled && !action.isEnabled && !reset.isEnabled)
        precondition(mapping.bindings.isEmpty && !mapping.listening)
        window.orderOut(nil)
    }
}
