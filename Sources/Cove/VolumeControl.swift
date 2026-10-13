import CoreAudio
import Foundation

/// Mute/unmute the default output device through CoreAudio (public API). Read on demand, never polled.
@MainActor
@Observable
final class VolumeControl {
    private(set) var muted = false
    private(set) var available = false

    init() { refresh() }

    func refresh() {
        guard let device = Self.defaultOutputDevice() else { available = false; return }
        var address = Self.muteAddress
        available = AudioObjectHasProperty(device, &address)
        guard available else { return }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
            muted = value != 0
        }
    }

    func toggleMute() {
        guard let device = Self.defaultOutputDevice() else { return }
        var address = Self.muteAddress
        var value: UInt32 = muted ? 0 : 1
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        refresh()
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
