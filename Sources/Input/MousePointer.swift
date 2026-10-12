import AppKit

// Switch only after every physical key is up, so native keyboard mappings cannot
// change between a key-down and its matching key-up. Mode is never persisted.
struct MouseModeState {
    private(set) var active = false
    private(set) var pending: Bool?

    mutating func requestToggle() { if pending == nil { pending = !active } }
    mutating func cancelPending() { pending = nil }
    mutating func applyIfReleased(_ held: Set<UInt8>) -> Bool {
        guard held.isEmpty, let pending else { return false }
        active = pending; self.pending = nil
        return true
    }
    @discardableResult mutating func reset() -> Bool {
        let changed = active
        active = false; pending = nil
        return changed
    }
}

/// One timer while moving, none while idle. Dependencies also allow exercising
/// real press/release/cancellation behavior without posting system input.
final class MousePointer {
    private let position: () -> CGPoint?
    private let screens: () -> [CGRect]
    private let post: (CGEvent) -> Void
    private let clock: () -> TimeInterval
    private var held: [UInt8: ButtonAction.Kind] = [:]
    private var timer: Timer?
    private var allowed: () -> Bool = { false }
    private var startedAt: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var lastClick: (right: Bool, point: CGPoint, at: TimeInterval, count: Int64)?
    var moving: Bool { timer != nil }

    init(position: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location },
         screens: @escaping () -> [CGRect] = {
             NSScreen.screens.compactMap {
                 guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
                 return CGDisplayBounds(id)
             }
         }, post: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.position = position; self.screens = screens; self.post = post; self.clock = clock
    }

    deinit { timer?.invalidate() }

    func press(_ button: UInt8, direction: ButtonAction.Kind, allowed: @escaping () -> Bool) {
        guard ButtonAction(kind: direction).isMouseMovement, allowed() else { return }
        guard held[button] == nil else { return }
        held[button] = direction
        self.allowed = allowed
        guard timer == nil else { return }
        startedAt = clock(); lastTick = startedAt
        move(distance: 3)
        guard !held.isEmpty else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.003
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func release(_ button: UInt8) {
        guard held.removeValue(forKey: button) != nil else { return }
        if held.isEmpty { stop() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        held.removeAll(); allowed = { false }; lastClick = nil
    }

    func tick() {
        guard !held.isEmpty, allowed() else { stop(); return }
        let now = clock()
        let elapsed = min(max(0, now - lastTick), 1.0 / 30)
        lastTick = now
        let speed = 180 + min(max(0, now - startedAt), 0.8) / 0.8 * 720
        move(distance: speed * elapsed)
    }

    private func move(distance: Double) {
        guard let origin = position() else { stop(); return }
        var dx = 0.0, dy = 0.0
        for direction in held.values {
            switch direction {
            case .mouseUp: dy -= 1
            case .mouseDown: dy += 1
            case .mouseLeft: dx -= 1
            case .mouseRight: dx += 1
            default: break
            }
        }
        // Opposite directions cancel and diagonals retain the same speed.
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let proposed = CGPoint(x: origin.x + dx / length * distance, y: origin.y + dy / length * distance)
        guard let point = Self.clamped(proposed, screens: screens()), point != origin,
              let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - origin.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - origin.y).rounded()))
        event.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
        post(event)
    }

    static func clamped(_ point: CGPoint, screens: [CGRect]) -> CGPoint? {
        let candidates = screens.filter { !$0.isEmpty }.map {
            CGPoint(x: min(max(point.x, $0.minX), $0.maxX - 1), y: min(max(point.y, $0.minY), $0.maxY - 1))
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }
    }

    func click(right: Bool) {
        guard let point = position() else { return }
        let now = clock()
        var count: Int64 = 1
        if let lastClick, lastClick.right == right, now - lastClick.at <= NSEvent.doubleClickInterval,
           hypot(point.x - lastClick.point.x, point.y - lastClick.point.y) <= 4 {
            count = lastClick.count == 1 ? 2 : 1
        }
        guard let events = Self.clickEvents(right: right, point: point, count: count) else { return }
        lastClick = (right, point, now, count)
        for event in events { post(event) }
    }

    // Allocate both phases first; clicks never leave a synthetic button held.
    static func clickEvents(right: Bool, point: CGPoint, count: Int64 = 1) -> [CGEvent]? {
        let source = CGEventSource(stateID: .privateState)
        let button: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseDown : .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: button) else { return nil }
        for event in [down, up] {
            event.flags = CGEventSource.flagsState(.combinedSessionState)
            event.setIntegerValueField(.mouseEventClickState, value: count)
            event.setIntegerValueField(.eventSourceUserData, value: 0x524D564B)
        }
        return [down, up]
    }
}
