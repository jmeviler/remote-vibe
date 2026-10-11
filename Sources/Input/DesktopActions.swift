import AppKit
import ApplicationServices

/// Window queries run on demand, away from the audio and HID run loop.
final class DesktopActions {
    private struct Screen: Equatable {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }
    private struct Window {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let bounds: CGRect
    }
    private struct Selection {
        let window: Window
        let screen: Screen
        let origin: AXUIElement?
    }
    private enum SelectionError: Error {
        case unavailable(String)
    }
    private let queue = DispatchQueue(label: "RemoteVibe.desktop", qos: .userInitiated)
    private var order: [CGDirectDisplayID: [CGWindowID]] = [:] // Worker queue only.
    private var busy = false // Main queue only.
    private var generation = 0

    func cancel() { generation += 1 }

    func perform(nextDisplay: Bool, allowed: @escaping () -> Bool, completion: @escaping (String) -> Void) {
        guard !busy, allowed(), AXIsProcessTrusted() else { return }
        let screens = Self.screens()
        guard !screens.isEmpty else { completion(L("没有可用的显示器")); return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = Set(NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
        }.map { $0.processIdentifier })
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let token = generation
        busy = true
        queue.async { [self] in
            let result = Result { try select(nextDisplay: nextDisplay, screens: screens, front: front, pids: pids, pointer: pointer) }
            DispatchQueue.main.async { [self] in
                guard token == generation, allowed(), AXIsProcessTrusted(),
                      screens == Self.screens(), NSWorkspace.shared.frontmostApplication?.processIdentifier == front else {
                    busy = false
                    return
                }
                switch result {
                case .failure(let error):
                    busy = false
                    if case SelectionError.unavailable(let message) = error { completion(message) }
                case .success(let selection):
                    if let front, let origin = selection.origin {
                        guard let current = Self.focusedWindow(front), CFEqual(origin, current) else {
                            busy = false
                            return
                        }
                    }
                    activate(selection, token: token, allowed: allowed, completion: completion)
                }
            }
        }
    }

    private static func screens() -> [Screen] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            return Screen(id: id, bounds: CGDisplayBounds(id))
        }.sorted {
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            return $0.id < $1.id
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func appElement(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return app
    }

    private static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        guard let value = attribute(appElement(pid), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent), extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func sameBounds(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 &&
        abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    private static func screen(for bounds: CGRect, in screens: [Screen]) -> Screen? {
        screens.map { screen -> (Screen, CGFloat) in
            let overlap = screen.bounds.intersection(bounds)
            return (screen, overlap.isNull ? 0 : overlap.width * overlap.height)
        }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    private static func visibleWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
    }

    private func select(nextDisplay: Bool, screens: [Screen], front: pid_t?, pids: Set<pid_t>, pointer: CGPoint) throws -> Selection {
        let origin = front.flatMap { Self.focusedWindow($0) }
        let current = origin.flatMap { Self.bounds($0) }.flatMap { Self.screen(for: $0, in: screens) }
            ?? screens.first { $0.bounds.contains(pointer) } ?? screens[0]
        let destination: Screen
        if nextDisplay {
            guard screens.count > 1 else { throw SelectionError.unavailable(L("只有一块显示器，无需切换")) }
            destination = screens[(screens.firstIndex(of: current)! + 1) % screens.count]
        } else { destination = current }

        let rows = Self.visibleWindows()
        var windows: [Window] = []
        var queried = Set<pid_t>()
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        // Match public AX windows to on-screen CG bounds. No window titles, private APIs or screen capture.
        for row in rows {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(pid), queried.insert(pid).inserted else { continue }
            let elements = Self.attribute(Self.appElement(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
            var candidates: [(AXUIElement, CGRect)] = []
            for element in elements {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                AXUIElementSetMessagingTimeout(element, 0.15)
                guard Self.attribute(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      Self.attribute(element, kAXMinimizedAttribute) as? Bool == false,
                      let bounds = Self.bounds(element) else { continue }
                candidates.append((element, bounds))
            }
            for row in rows where (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid {
                guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      let raw = row[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: raw),
                      Self.screen(for: bounds, in: screens)?.id == destination.id else { continue }
                let matches = candidates.filter { Self.sameBounds($0.1, bounds) }
                // Ambiguous windows (e.g. identical geometry on another Space) must not cause a Space switch.
                guard matches.count == 1 else { continue }
                let sameGeometry = rows.filter { other in
                    guard (other[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                          let raw = other[kCGWindowBounds as String] as? NSDictionary,
                          let otherBounds = CGRect(dictionaryRepresentation: raw) else { return false }
                    return Self.sameBounds(otherBounds, bounds)
                }
                guard sameGeometry.count == 1 else { continue }
                windows.append(Window(id: id, pid: pid, element: matches[0].0, bounds: bounds))
            }
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            throw SelectionError.unavailable(L("读取窗口超时，请重试"))
        }
        let zOrder = rows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        windows.sort { (zOrder.firstIndex(of: $0.id) ?? 0) < (zOrder.firstIndex(of: $1.id) ?? 0) }
        guard !windows.isEmpty else {
            throw SelectionError.unavailable(nextDisplay ? L("目标屏幕没有可切换的窗口") : L("当前屏幕没有可切换的窗口"))
        }
        order = order.filter { id, _ in screens.contains { $0.id == id } }
        let ids = windows.map { $0.id }
        var ring = (order[destination.id] ?? []).filter { ids.contains($0) }
        ring.append(contentsOf: ids.filter { !ring.contains($0) })
        order[destination.id] = ring
        let target: Window
        if nextDisplay { target = windows[0] }
        else {
            guard ring.count > 1 else { throw SelectionError.unavailable(L("当前屏幕只有一个可切换的窗口")) }
            let focused = windows.first { window in window.pid == front && origin.map { CFEqual($0, window.element) } == true }
            let index = focused.flatMap { ring.firstIndex(of: $0.id) }.map { ($0 + 1) % ring.count } ?? 0
            target = windows.first { $0.id == ring[index] }!
        }
        return Selection(window: target, screen: destination, origin: origin)
    }

    private func activate(_ selection: Selection, token: Int, allowed: @escaping () -> Bool, completion: @escaping (String) -> Void) {
        let target = selection.window
        // Revalidate visibility before touching focus; the window may have moved or closed during the query.
        guard Self.visibleWindows().contains(where: { row in
            guard (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target.id,
                  let raw = row[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return Self.sameBounds(bounds, target.bounds)
        }), let app = NSRunningApplication(processIdentifier: target.pid), !app.isHidden,
        AXUIElementPerformAction(target.element, kAXRaiseAction as CFString) == .success else {
            busy = false; completion(L("窗口已变化或无法激活，请重试")); return
        }
        // Raising alone does not select a background application's intended window.
        _ = AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard app.activate(options: []) else {
            busy = false; completion(L("窗口未能激活，请重试")); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            defer { busy = false }
            guard token == generation, allowed(), Self.screens().contains(selection.screen) else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                  let focused = Self.focusedWindow(target.pid), CFEqual(focused, target.element) else {
                completion(L("窗口未获得焦点，请重试")); return
            }
            let area = target.bounds.intersection(selection.screen.bounds)
            CGWarpMouseCursorPosition(CGPoint(x: area.midX, y: area.midY))
            completion(L("已切换窗口"))
        }
    }
}
