import CoreAudio
import Foundation

/// Output devices from CoreAudio. Web views play through the system default output,
/// so switching the default is how Lull's audio gets routed.
public enum AudioOutputs {
    public struct Device: Identifiable, Equatable, Sendable {
        public let id: AudioDeviceID
        public let name: String
        let transport: UInt32

        /// HDMI or DisplayPort: audio going to a TV or monitor.
        public var isDisplay: Bool {
            transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        }

        public var symbol: String {
            if name.localizedCaseInsensitiveContains("airpods") { return "airpods" }
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeUSB: return "cable.connector"
            case kAudioDeviceTransportTypeBuiltIn: return "hifispeaker.fill"
            default: return "speaker.wave.2.fill"
            }
        }
    }

    public static func all() -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0,
                  get(id, kAudioDevicePropertyIsHidden, as: UInt32.self) != 1,
                  let name = name(of: id) else { return nil }
            return Device(id: id, name: name, transport: get(id, kAudioDevicePropertyTransportType, as: UInt32.self) ?? 0)
        }
    }

    public static func defaultID() -> AudioDeviceID? {
        get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioDeviceID.self)
    }

    public static func setDefault(_ id: AudioDeviceID) {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, as _: T.Type) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
