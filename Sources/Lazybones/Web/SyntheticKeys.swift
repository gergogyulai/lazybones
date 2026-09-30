import AppKit

/// Key presses sent through a window like real ones, so pages see trusted keydown events.
@MainActor
enum SyntheticKeys {
    enum Key {
        case up, down, left, right, select, back

        fileprivate var code: UInt16 {
            switch self {
            case .up: 126
            case .down: 125
            case .left: 123
            case .right: 124
            case .select: 36
            case .back: 53
            }
        }

        fileprivate var character: Character {
            switch self {
            case .up: "\u{F700}"
            case .down: "\u{F701}"
            case .left: "\u{F702}"
            case .right: "\u{F703}"
            case .select: "\r"
            case .back: "\u{1B}"
            }
        }

        fileprivate var isArrow: Bool { code >= 123 && code <= 126 }
    }

    static func press(_ key: Key, in window: NSWindow) {
        let chars = String(key.character)
        let flags: NSEvent.ModifierFlags = key.isArrow ? [.function, .numericPad] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: key.code
            ) else { continue }
            window.sendEvent(event)
        }
    }
}
