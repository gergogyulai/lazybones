import Foundation

enum SystemSleep {
    /// Turns the displays off, as the Sleep tile in Control Center does.
    static func displays() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        do { try p.run() } catch { Log.error("could not sleep displays (\(error))") }
    }
}
