import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of a CoreAudio output device, for devices that have them (HDMI usually doesn't).
public enum DeviceVolume {
    public static func supported(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &addr)
            && AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    public static func get(_ id: AudioDeviceID) -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    public static func set(_ id: AudioDeviceID, _ value: Float) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(value)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    public static func muted(_ id: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    public static func setMuted(_ id: AudioDeviceID, _ muted: Bool) {
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
