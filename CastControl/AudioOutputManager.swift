//
//  AudioOutputManager.swift
//  CastControl
//

import CoreAudio
import Foundation

extension DisplayManager {
    func audioOutput(for display: ManagedDisplay) -> AudioOutputDevice? {
        guard !display.isBuiltin else {
            return nil
        }

        let displayNames = display.aliases
            .filter { !Self.isGenericDisplayName($0) }
            .map(Self.normalizedAudioMatchName)
            .filter { !$0.isEmpty }

        if let exactMatch = audioOutputDevices.first(where: { device in
            displayNames.contains(device.normalizedName)
        }) {
            Self.debugLog("audio match display=\(display.id) aliases=\(display.aliases) matched=\(exactMatch.name) method=exact")
            return exactMatch
        }

        if let containedMatch = audioOutputDevices.first(where: { device in
            displayNames.contains { displayName in
                device.normalizedName.contains(displayName) || displayName.contains(device.normalizedName)
            }
        }) {
            Self.debugLog("audio match display=\(display.id) aliases=\(display.aliases) matched=\(containedMatch.name) method=contained")
            return containedMatch
        }

        let genericDisplayOutputs = audioOutputDevices.filter { device in
            Self.isGenericDisplayAudioName(device.normalizedName)
        }

        if genericDisplayOutputs.count == 1, externalDisplays.count == 1 {
            Self.debugLog("audio match display=\(display.id) aliases=\(display.aliases) matched=\(genericDisplayOutputs[0].name) method=single-generic-output")
            return genericDisplayOutputs[0]
        }

        Self.debugLog("audio match display=\(display.id) aliases=\(display.aliases) matched=nil")
        return nil
    }

    func isUsingAudioOutput(_ audioOutput: AudioOutputDevice) -> Bool {
        defaultAudioOutputDeviceID == audioOutput.id
    }

    func toggleAudioOutput(_ audioOutput: AudioOutputDevice) {
        refreshAudioOutputs()

        if defaultAudioOutputDeviceID == audioOutput.id {
            restorePreviousAudioOutput()
            return
        }

        if let defaultAudioOutputDeviceID, defaultAudioOutputDeviceID != audioOutput.id {
            previousAudioOutputDeviceID = defaultAudioOutputDeviceID
        }

        setDefaultAudioOutputDevice(audioOutput.id)
    }

    func refreshAudioOutputs() {
        audioOutputDevices = Self.outputAudioDevices()
        defaultAudioOutputDeviceID = Self.defaultAudioOutputDeviceID()
        Self.debugLog(
            "audio outputs detected=\(audioOutputDevices.map { "\($0.id):\($0.name)" }) default=\(defaultAudioOutputDeviceID.map(String.init) ?? "nil")"
        )

        if
            let previousAudioOutputDeviceID,
            !audioOutputDevices.contains(where: { $0.id == previousAudioOutputDeviceID })
        {
            self.previousAudioOutputDeviceID = nil
        }
    }

    func restorePreviousAudioOutput() {
        refreshAudioOutputs()

        if
            let previousAudioOutputDeviceID,
            audioOutputDevices.contains(where: { $0.id == previousAudioOutputDeviceID }),
            previousAudioOutputDeviceID != defaultAudioOutputDeviceID
        {
            setDefaultAudioOutputDevice(previousAudioOutputDeviceID)
            self.previousAudioOutputDeviceID = nil
            return
        }

        if let macSpeakers = audioOutputDevices.first(where: { Self.isMacSpeakerName($0.normalizedName) }) {
            setDefaultAudioOutputDevice(macSpeakers.id)
        }
    }

    func setDefaultAudioOutputDevice(_ deviceID: AudioDeviceID) {
        guard Self.setDefaultAudioOutputDevice(deviceID) else {
            refreshAudioOutputs()
            return
        }

        refreshAudioOutputs()
    }

    private static func outputAudioDevices() -> [AudioOutputDevice] {
        audioDeviceIDs().compactMap { deviceID in
            guard audioDeviceHasOutputStreams(deviceID), let name = audioDeviceName(deviceID) else {
                return nil
            }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                return nil
            }

            return AudioOutputDevice(
                id: deviceID,
                name: trimmedName,
                normalizedName: normalizedAudioMatchName(trimmedName)
            )
        }
    }

    private static func audioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else {
            return []
        }

        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        let result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices)
        guard result == noErr else {
            return []
        }

        return devices
    }

    private static func audioDeviceHasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        return dataSize >= MemoryLayout<AudioStreamID>.size
    }

    private static func audioDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        namePointer.initialize(to: nil)
        defer {
            namePointer.deinitialize(count: 1)
            namePointer.deallocate()
        }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, namePointer) == noErr else {
            return nil
        }

        return namePointer.pointee as String?
    }

    private static func defaultAudioOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }

        guard deviceID != kAudioObjectUnknown else {
            return nil
        }

        return deviceID
    }

    private static func setDefaultAudioOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &targetDeviceID
        ) == noErr
    }

    nonisolated private static func normalizedAudioMatchName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isGenericDisplayAudioName(_ normalizedName: String) -> Bool {
        normalizedName == "hdmi"
            || normalizedName.contains("hdmi")
            || normalizedName.contains("displayport")
            || normalizedName.contains("display port")
            || normalizedName.contains("usb c display")
    }

    nonisolated private static func isMacSpeakerName(_ normalizedName: String) -> Bool {
        normalizedName.contains("macbook") && normalizedName.contains("speaker")
            || normalizedName.contains("built in output")
            || normalizedName.contains("internal speaker")
    }

}
