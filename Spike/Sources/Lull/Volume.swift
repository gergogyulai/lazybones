import AudioToolbox
import CoreAudio
import Foundation

struct VolumeState: Equatable {
    var level: Int  // 0...100
    var muted: Bool
    /// What the volume applies to, e.g. "MacBook Pro Speakers", "LG TV Livingroom", "App volume".
    var target: String
}

/// Sends volume changes to whatever can actually change the loudness of the current output:
/// the device's own volume control if it has one, the paired TV when audio goes out over HDMI
/// (Macs can't do HDMI-CEC, so this goes over the TV's network API), or else the web pages' own
/// media volume.
@MainActor
final class VolumeRouter {
    enum Target {
        case device(AudioDeviceID, String)
        case tv(String)
        case app
    }

    private let tv: TVLink
    private let web: WebPool
    private let useTV: () -> Bool
    private var appLevel = 100
    private var appMuted = false

    init(tv: TVLink, web: WebPool, useTV: @escaping () -> Bool) {
        self.tv = tv
        self.web = web
        self.useTV = useTV
    }

    var target: Target {
        guard let id = AudioOutputs.defaultID() else { return .app }
        let device = AudioOutputs.all().first { $0.id == id }
        if DeviceVolume.supported(id) { return .device(id, device?.name ?? "Output") }
        if useTV(), tv.status == .connected, let device, device.isDisplay { return .tv(tv.name) }
        return .app
    }

    /// Whether macOS itself can act on volume keys for the current output.
    var systemHandlesVolume: Bool {
        if case .device = target { return true }
        return false
    }

    func state() -> VolumeState? {
        switch target {
        case let .device(id, name):
            guard let v = DeviceVolume.get(id) else { return nil }
            return VolumeState(level: Int((v * 100).rounded()), muted: DeviceVolume.muted(id) ?? false, target: name)
        case let .tv(name):
            guard let level = tv.volume else { return nil }
            return VolumeState(level: level, muted: tv.muted ?? false, target: name)
        case .app:
            return VolumeState(level: appLevel, muted: appMuted, target: "App volume")
        }
    }

    /// `percent` is a step on a 0...100 scale; TVs get their own smaller step.
    func change(by percent: Int) {
        switch target {
        case let .device(id, _):
            guard let v = DeviceVolume.get(id) else { return }
            DeviceVolume.set(id, min(1, max(0, v + Float(percent) / 100)))
            if DeviceVolume.muted(id) == true { DeviceVolume.setMuted(id, false) }
        case .tv:
            tv.stepVolume(up: percent > 0)
        case .app:
            appLevel = min(100, max(0, appLevel + percent))
            appMuted = false
            applyApp()
        }
    }

    func toggleMute() {
        switch target {
        case let .device(id, _):
            DeviceVolume.setMuted(id, !(DeviceVolume.muted(id) ?? false))
        case .tv:
            tv.setMuted(!(tv.muted ?? false))
        case .app:
            appMuted.toggle()
            applyApp()
        }
    }

    private func applyApp() {
        web.setMediaVolume(Double(appLevel) / 100, muted: appMuted)
    }
}

/// Volume and mute of a CoreAudio output device, for devices that have them (HDMI usually doesn't).
enum DeviceVolume {
    static func supported(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &addr)
            && AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    static func get(_ id: AudioDeviceID) -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func set(_ id: AudioDeviceID, _ value: Float) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(value)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func muted(_ id: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func setMuted(_ id: AudioDeviceID, _ muted: Bool) {
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(id, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
