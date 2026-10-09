import Foundation
import ApplicationServices

// Drop only our marked test events after observing them, so they do not reach WeChat.
@main
enum FnRoundTripTest {
static let marker: Int64 = 0x524D5642
static var received: [Bool] = []
static func main() {
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
    options: .defaultTap, eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue,
    callback: { _, type, event, _ in
        if event.getIntegerValueField(.eventSourceUserData) == FnRoundTripTest.marker {
            assert(type == .flagsChanged)
            assert(event.getIntegerValueField(.keyboardEventKeycode) == 63)
            FnRoundTripTest.received.append(event.flags.contains(.maskSecondaryFn))
            return nil
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)
guard let tap else { fatalError("Could not create the Fn test event tap") }
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let fn = FnKey()
assert(fn.down())
assert(fn.down()) // duplicate down must not produce another event
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
fn.up()
fn.up() // duplicate up must not produce another event
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
assert(!fn.held)
CGEvent.tapEnable(tap: tap, enable: false)
CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
CFMachPortInvalidate(tap)
assert(received == [true, false], "Fn down/up was not observed: \(received)")
print("PASS: macOS received matching Fn down/up events, captured before application delivery.")

}
}
