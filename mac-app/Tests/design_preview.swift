import AppKit

// Preview-only controller: no Bluetooth, keychain access, events or preference writes.
final class ComboUnlock {
    enum Mode { case idle, recording, confirming }
    var mode = Mode.idle
    var locked = false
    var sequenceLength = 0
    var hasPassword = false
    var recorded: [UInt8] = []
    var configured = false
    var validated = false
    var enabled = false
    var canConfirmTest = false
    var permissionsReady = true
    var status = "先录制一段连招，再完成本机验证。"
    var onChange: (() -> Void)?
    func settingsClosed() {}
    func record() {}
    func finishRecording() {}
    func practice() {}
    func cancel() {}
    func savePassword(_ value: String) {}
    func verify() {}
    func setEnabled(_ value: Bool) {}
    func confirmVerification(_ value: Bool) {}
    func clear() {}
}

@main
enum DesignPreview {
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func change(_ control: NSControl) { _ = NSApp.sendAction(control.action!, to: control.target, from: control) }
    static func capture(_ view: NSView, name: String, directory: URL) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus(); StudioTheme.canvas.setFill(); view.bounds.fill()
        NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size).draw(in: view.bounds)
        image.unlockFocus()
        let rendered = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rendered.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    }
    static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let empty = try JSONEncoder().encode(KeyMapping.Bindings())
        UserDefaults.standard.setVolatileDomain(Dictionary(uniqueKeysWithValues: RemoteProfile.allCases.map { ($0.mappingKey, empty) }), forName: UserDefaults.argumentDomain)
        let directory = URL(fileURLWithPath: "build/design/" + (CommandLine.arguments.dropFirst().first ?? "review"), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for profile in RemoteProfile.allCases {
            let mapping = KeyMapping(profile: profile)
            let view = KeyMappingView(mapping: mapping)
            let combo = ComboUnlockView(controller: ComboUnlock(), allowPermissions: {})
            combo.isHidden = true
            let remote = NSPopUpButton()
            remote.addItems(withTitles: RemoteProfile.allCases.map(\.title))
            remote.selectItem(at: profile == .chromecast ? 0 : 1)
            let tabs = NSSegmentedControl(labels: ["按键映射", "连招解锁"], trackingMode: .selectOne, target: nil, action: nil)
            tabs.selectedSegment = 0; tabs.isHidden = profile == .xiaomiRC003
            let shell = StudioShell(mapping: view, unlock: combo, remote: remote,
                discovery: StudioTheme.button("扫描遥控器"), pages: tabs,
                connection: NSTextField(wrappingLabelWithString: "等待遥控器连接"),
                audio: NSTextField(wrappingLabelWithString: "麦克风：Chromecast Mic 已就绪"),
                permission: NSTextField(wrappingLabelWithString: "Fn 按键权限：已允许"),
                permissionsButton: StudioTheme.button("权限设置"),
                message: NSTextField(wrappingLabelWithString: "点击需要输入的文本框，按住遥控器语音键开始说话。"))
            let window = NSWindow(contentRect: shell.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            let scroll = StudioScrollView(frame: shell.bounds)
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
            scroll.backgroundColor = StudioTheme.canvas
            scroll.documentView = shell
            window.contentView = scroll
            func resize(_ width: CGFloat, height: CGFloat = 812) {
                window.setContentSize(NSSize(width: width, height: height))
                scroll.needsLayout = true; scroll.layoutSubtreeIfNeeded()
                precondition(abs(shell.frame.width - scroll.contentSize.width) < 1, "Unexpected horizontal overflow")
            }
            resize(1080)
            try capture(shell, name: profile.rawValue + "-default", directory: directory)
            resize(1280)
            try capture(shell, name: profile.rawValue + "-wide", directory: directory)
            resize(1080)
            let controls = descendants(view)
            let triggers = controls.compactMap { $0 as? NSSegmentedControl }.first!
            let actions = controls.compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString("actionChanged") }!
            func choose(_ title: String) { actions.selectItem(withTitle: title); change(actions) }
            triggers.selectedSegment = 1; change(triggers)
            choose("输入常用文本")
            let text = controls.compactMap { $0 as? NSTextView }.first!
            text.string = "请先梳理实现思路，再逐步完成。\n保留现有行为，补充必要的验证。"
            view.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
            try capture(shell, name: profile.rawValue + "-text", directory: directory)
            resize(900, height: 640)
            try capture(shell, name: profile.rawValue + "-text-narrow", directory: directory)
            resize(1080)
            triggers.selectedSegment = 2; change(triggers)
            choose("自定义按键 / 组合快捷键…")
            try capture(shell, name: profile.rawValue + "-custom", directory: directory)
            resize(900, height: 640)
            try capture(shell, name: profile.rawValue + "-custom-narrow", directory: directory)
            resize(1080)
            choose("打开指定网页…")
            try capture(shell, name: profile.rawValue + "-validation", directory: directory)
            resize(900, height: 640)
            let target = controls.compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.placeholderString == "https://example.com" }!
            precondition(window.makeFirstResponder(target), "URL field must accept keyboard focus")
            try capture(shell, name: profile.rawValue + "-validation-narrow", directory: directory)
            resize(1080)
            let voice = controls.compactMap { $0 as? NSButton }.first { $0.tag == 0 && $0.action == NSSelectorFromString("selectKey:") }!
            change(voice)
            try capture(shell, name: profile.rawValue + "-voice", directory: directory)
            resize(900, height: 640)
            let reset = controls.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("resetKey") }!
            precondition(!reset.isEnabled, "Voice mapping must remain read-only")
            precondition(window.makeFirstResponder(voice), "Remote buttons must accept keyboard focus")
            try capture(shell, name: profile.rawValue + "-voice-narrow", directory: directory)
            resize(1080)
            if profile == .chromecast {
                view.isHidden = true; combo.isHidden = false; tabs.selectedSegment = 1
                try capture(shell, name: "combo", directory: directory)
                resize(900, height: 640)
                let record = descendants(combo).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("recordPressed") }!
                precondition(window.makeFirstResponder(record), "Primary buttons must accept keyboard focus")
                try capture(shell, name: "combo-narrow", directory: directory)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: shell.bounds.height - scroll.contentSize.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                try capture(scroll, name: "combo-narrow-scrolled", directory: directory)
            }
            window.orderOut(nil)
            precondition(mapping.bindings.isEmpty && !mapping.listening)
        }
        print("Rendered 23 isolated interface states in \(directory.path)")
    }
}
