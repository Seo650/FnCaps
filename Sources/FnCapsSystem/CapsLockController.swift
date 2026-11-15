import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem

/// Caps Lock state via IOHIDSystem, plus a synthetic Caps flagsChanged event for experiment E4.
public final class CapsLockController {
    private var conn: io_connect_t = 0

    public init() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        var c: io_connect_t = 0
        if IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &c) == KERN_SUCCESS {
            conn = c
        }
        IOObjectRelease(service)
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    public func isOn() -> Bool? {
        guard conn != 0 else { return nil }
        var state = false
        let r = IOHIDGetModifierLockState(conn, Int32(kIOHIDCapsLockState), &state)
        return r == KERN_SUCCESS ? state : nil
    }

    /// Do not read back immediately: the state can still show the old value.
    @discardableResult
    public func set(_ on: Bool) -> Bool {
        guard conn != 0 else { return false }
        return IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on) == KERN_SUCCESS
    }

    /// Posts flagsChanged keyCode 57 with then without maskAlphaShift (E4 comparison).
    public func postSyntheticCapsEvent() {
        SyntheticKeys.postFlagsChanged(keyCode: 57, flags: .maskAlphaShift)
        SyntheticKeys.postFlagsChanged(keyCode: 57, flags: [])
    }
}
