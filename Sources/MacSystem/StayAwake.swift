import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idling into sleep, the display from turning off and the screen saver from
/// starting, with the same power assertion a video player takes. macOS drops it when the process
/// exits, so a crash can't leave the Mac awake for good. Sleeping on purpose (the Apple menu, the
/// lid, `pmset displaysleepnow`) still works.
@MainActor
public final class StayAwake {
    private var assertion: IOPMAssertionID?

    public init() {}

    public var isOn: Bool {
        get { assertion != nil }
        set { newValue ? hold() : release() }
    }

    private func hold() {
        guard assertion == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Lazybones is showing on the TV" as CFString, &id)
        if result == kIOReturnSuccess { assertion = id }
    }

    private func release() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }
}
