import AudioToolbox
import CoreAudio
import Foundation

/// Mute/unmute the default output device through CoreAudio (public API). Read on demand, never polled.
@MainActor
@Observable
final class VolumeControl {
    private(set) var muted = false
    private(set) var available = false
    /// Output level 0…1 (the virtual main volume), when the device has one.
    private(set) var level: Float = 0
    private(set) var hasLevel = false

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
        var levelAddress = Self.levelAddress
        hasLevel = AudioObjectHasProperty(device, &levelAddress)
        if hasLevel {
            var volume: Float32 = 0
            var volumeSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &levelAddress, 0, nil, &volumeSize, &volume) == noErr { level = volume }
        }
    }

    func setLevel(_ value: Float) {
        guard let device = Self.defaultOutputDevice(), hasLevel else { return }
        var address = Self.levelAddress
        var volume = Float32(min(1, max(0, value)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        level = volume
    }

    private static var levelAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
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
