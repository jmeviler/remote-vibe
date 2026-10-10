import AppKit

/// A short-lived paste transaction. The previous clipboard is restored only while we still own it.
final class TextInput {
    private var restoreWork: DispatchWorkItem?
    private var previous: [NSPasteboardItem]?
    private var ownedChange = -1

    func paste(_ text: String, allowed: @escaping () -> Bool, sendPaste: (pid_t) -> Void) -> String {
        guard previous == nil else { return "上一段文字仍在输入，请稍候" }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请先设置常用文本" }
        guard allowed(), let target = InputFocus.current() else { return "请先将光标放到目标输入框" }
        let held = CGEventSource.flagsState(.combinedSessionState)
        guard held.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty else { return "请先松开键盘修饰键" }

        let board = NSPasteboard.general
        let before = board.changeCount
        let items = board.pasteboardItems
        guard items != nil || (board.types ?? []).isEmpty else { return "无法保留当前剪贴板，未输入文本" }
        var snapshot: [NSPasteboardItem] = []
        var bytes = 0
        // Preserve every representation, including images and file URLs. Never replace a clipboard we cannot save.
        for item in items ?? [] {
            guard !item.types.isEmpty else { return "无法保留当前剪贴板，未输入文本" }
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return "无法保留当前剪贴板，未输入文本" }
                bytes += data.count
                guard bytes <= 32 * 1024 * 1024 else { return "当前剪贴板内容过大，未输入文本" }
                guard copy.setData(data, forType: type) else { return "无法保留当前剪贴板，未输入文本" }
            }
            snapshot.append(copy)
        }
        guard board.changeCount == before, allowed(), target.isCurrent else { return "输入位置或剪贴板已变化，请重试" }
        previous = snapshot
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            ownedChange = board.changeCount; restore(); return "无法准备文本，剪贴板已恢复"
        }
        ownedChange = board.changeCount
        guard allowed(), target.isCurrent else { restore(); return "输入位置已变化，未输入文本" }
        sendPaste(target.pid)
        let work = DispatchWorkItem { [weak self] in self?.restore() }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        return "已发送文本粘贴 · 未按回车"
    }

    func stop() { restore() }

    private func restore() {
        restoreWork?.cancel(); restoreWork = nil
        guard let snapshot = previous else { return }
        previous = nil
        let board = NSPasteboard.general
        guard board.changeCount == ownedChange else { return }
        board.clearContents()
        if !snapshot.isEmpty { board.writeObjects(snapshot) }
    }
}

struct InputFocus {
    let pid: pid_t
    let element: AXUIElement

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func focusedElement(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func current() -> InputFocus? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.apple.loginwindow", let element = focusedElement(app.processIdentifier) else { return nil }
        let focus = InputFocus(pid: app.processIdentifier, element: element)
        return focus.isEditable ? focus : nil
    }

    var isEditable: Bool {
        let role = Self.attribute(element, kAXRoleAttribute) as? String
        let subrole = Self.attribute(element, kAXSubroleAttribute) as? String
        guard subrole != kAXSecureTextFieldSubrole, role != kAXSecureTextFieldSubrole,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? ""),
              (Self.attribute(element, kAXEnabledAttribute) as? Bool) != false,
              (Self.attribute(element, "AXReadOnly") as? Bool) != true else { return false }
        return [kAXValueAttribute, kAXSelectedTextAttribute].contains { name in
            var writable: DarwinBoolean = false
            return AXUIElementIsAttributeSettable(element, name as CFString, &writable) == .success && writable.boolValue
        } || (Self.attribute(element, "AXEditable") as? Bool) == true
    }

    var isCurrent: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid &&
            Self.focusedElement(pid).map { CFEqual($0, element) } == true && isEditable
    }
}
