//
//  DisplayManager.swift
//  CastControl
//

import AppKit
import Combine
import CoreAudio
import CoreGraphics
import IOKit
import IOKit.graphics

final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [ManagedDisplay] = []
    @Published var audioOutputDevices: [AudioOutputDevice] = []
    @Published var defaultAudioOutputDeviceID: AudioDeviceID?

    private var reconfigurationCallbackRegistered = false
    private var displayNameCache: [String: String] = [:]
    var previousAudioOutputDeviceID: AudioDeviceID?

    var externalDisplays: [ManagedDisplay] {
        displays.filter { !$0.isBuiltin }
    }

    var hasSidecarDisplay: Bool {
        externalDisplays.contains(where: \.isSidecar)
    }

    var mainDisplayID: CGDirectDisplayID {
        builtinDisplayID ?? CGMainDisplayID()
    }

    private var builtinDisplayID: CGDirectDisplayID? {
        displays.first(where: \.isBuiltin)?.id
    }

    init() {
        refresh()
        registerForDisplayChanges()
    }

    deinit {
        if reconfigurationCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    func refresh() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            displays = []
            refreshAudioOutputs()
            return
        }

        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &onlineDisplays, &count) == .success else {
            displays = []
            refreshAudioOutputs()
            return
        }

        let screenNames = Self.localizedScreenNamesByDisplayID()
        displays = onlineDisplays
            .map { displayID in
                let identity = Self.displayIdentity(for: displayID)
                let localizedName = screenNames[displayID]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let ioName = Self.ioDisplayName(for: displayID)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName = Self.fallbackName(for: displayID)
                let cachedName = displayNameCache[identity.cacheKey]
                let displayName = resolvedDisplayName(
                    localizedName: localizedName,
                    ioName: ioName,
                    cachedName: cachedName,
                    fallbackName: fallbackName
                )
                let aliases = Self.displayAliases(
                    displayName: displayName,
                    localizedName: localizedName,
                    ioName: ioName,
                    cachedName: cachedName,
                    fallbackName: fallbackName
                )

                if !Self.isGenericDisplayName(displayName) {
                    displayNameCache[identity.cacheKey] = displayName
                }

                Self.debugLog(
                    """
                    display id=\(displayID) vendor=\(identity.vendorID) model=\(identity.modelID) serial=\(identity.serialNumber) \
                    localized=\(Self.debugValue(localizedName)) io=\(Self.debugValue(ioName)) cached=\(Self.debugValue(cachedName)) final=\(displayName)
                    """
                )

                let isSidecar = aliases.contains(where: Self.isSidecarName)

                return ManagedDisplay(
                    id: displayID,
                    identity: identity,
                    name: displayName,
                    aliases: aliases,
                    isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
                    mirrorsDisplayID: CGDisplayMirrorsDisplay(displayID),
                    isInMirrorSet: CGDisplayIsInMirrorSet(displayID) != 0,
                    isSidecar: isSidecar
                )
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltin != rhs.isBuiltin {
                    return lhs.isBuiltin
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        refreshAudioOutputs()
        logAudioMatchesForDisplays()
    }

    func mirrorToMainDisplay(_ display: ManagedDisplay, optimization: MirrorOptimization) {
        configureDisplays { configuration in
            switch optimization {
            case .fitExternal:
                CGConfigureDisplayMirrorOfDisplay(configuration, mainDisplayID, display.id)
            case .matchMac:
                CGConfigureDisplayMirrorOfDisplay(configuration, display.id, mainDisplayID)
            }
        }
    }

    func extendDisplay(_ display: ManagedDisplay) {
        configureDisplays { configuration in
            CGConfigureDisplayMirrorOfDisplay(configuration, display.id, kCGNullDirectDisplay)
            CGConfigureDisplayMirrorOfDisplay(configuration, mainDisplayID, kCGNullDirectDisplay)
        }
    }

    func arrangementDisplays() -> [ArrangementDisplay] {
        displays.map { display in
            let bounds = CGDisplayBounds(display.id)
            return ArrangementDisplay(
                id: display.id,
                name: display.name,
                isBuiltin: display.isBuiltin,
                isSidecar: display.isSidecar,
                pixelBounds: bounds,
                originalOrigin: bounds.origin,
                gridPosition: ArrangementGridPosition(row: 0, column: 0)
            )
        }
    }

    func extendAllDisplays() {
        configureDisplays { configuration in
            for display in externalDisplays {
                CGConfigureDisplayMirrorOfDisplay(configuration, display.id, kCGNullDirectDisplay)
            }
            CGConfigureDisplayMirrorOfDisplay(configuration, mainDisplayID, kCGNullDirectDisplay)
        }
    }

    func applyArrangement(_ layout: DisplayArrangementLayout) {
        let origins = layout.proposedOrigins(anchoredTo: mainDisplayID)
        configureDisplays { configuration in
            for display in layout.displays {
                guard let origin = origins[display.id] else {
                    continue
                }

                CGConfigureDisplayOrigin(
                    configuration,
                    display.id,
                    Int32(origin.x.rounded()),
                    Int32(origin.y.rounded())
                )
            }
        }
    }

    private func configureDisplays(_ changes: (CGDisplayConfigRef?) -> Void) {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success else {
            refresh()
            return
        }

        changes(configuration)

        let result = CGCompleteDisplayConfiguration(configuration, .permanently)
        if result != .success {
            CGCancelDisplayConfiguration(configuration)
        }

        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    private func logAudioMatchesForDisplays() {
        for display in externalDisplays {
            _ = audioOutput(for: display)
        }
    }

    private func registerForDisplayChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context) == .success {
            reconfigurationCallbackRegistered = true
        }
    }

    private static func localizedScreenNamesByDisplayID() -> [CGDirectDisplayID: String] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            let localizedName = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !localizedName.isEmpty else {
                return nil
            }

            return (displayID, localizedName)
        })
    }

    private func resolvedDisplayName(
        localizedName: String?,
        ioName: String?,
        cachedName: String?,
        fallbackName: String
    ) -> String {
        if let localizedName, !Self.isGenericDisplayName(localizedName) {
            return localizedName
        }

        if let ioName, !Self.isGenericDisplayName(ioName) {
            return ioName
        }

        if let cachedName, !Self.isGenericDisplayName(cachedName) {
            return cachedName
        }

        if let localizedName, !localizedName.isEmpty {
            return localizedName
        }

        if let ioName, !ioName.isEmpty {
            return ioName
        }

        return fallbackName
    }

    private static func displayIdentity(for displayID: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(
            vendorID: CGDisplayVendorNumber(displayID),
            modelID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            fallbackDisplayID: displayID
        )
    }

    private static func displayAliases(
        displayName: String,
        localizedName: String?,
        ioName: String?,
        cachedName: String?,
        fallbackName: String
    ) -> [String] {
        var seenAliases = Set<String>()
        let aliases: [String?] = [displayName, localizedName, ioName, cachedName, fallbackName]
        return aliases
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { alias in
                seenAliases.insert(alias).inserted
            }
    }

    private static func fallbackName(for displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Mac Display"
        }

        return "Display \(displayID)"
    }

    nonisolated static func isGenericDisplayName(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else {
            return true
        }

        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedName.range(of: #"^display( \d+)?$"#, options: .regularExpression) != nil
    }

    private static func ioDisplayName(for displayID: CGDirectDisplayID) -> String? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        guard result == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { service = IOIteratorNext(iterator) }
            defer { IOObjectRelease(service) }

            guard
                let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any],
                let serviceVendorID = info[kDisplayVendorID as String] as? UInt32,
                let serviceProductID = info[kDisplayProductID as String] as? UInt32
            else {
                continue
            }

            let serviceSerialNumber = info[kDisplaySerialNumber as String] as? UInt32
            let serialMatches = serialNumber == 0 || serviceSerialNumber == nil || serviceSerialNumber == serialNumber
            guard serviceVendorID == vendorID, serviceProductID == productID, serialMatches else {
                continue
            }

            guard let productNames = info[kDisplayProductName as String] as? [String: String] else {
                return nil
            }

            let preferredLanguage = Locale.preferredLanguages.first
            if let preferredLanguage, let localizedName = productNames[preferredLanguage] {
                return localizedName
            }

            if let englishName = productNames["en_US"] ?? productNames["en"] {
                return englishName
            }

            return productNames.values.first
        }

        return nil
    }

    static func debugLog(_ message: String) {
        print("[CastControl] \(message)")
    }

    static func debugValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "nil"
        }

        return "\"\(value)\""
    }

    nonisolated private static func isSidecarName(_ name: String) -> Bool {
        let normalizedName = name.localizedLowercase
        return normalizedName.contains("sidecar") || normalizedName.contains("airplay")
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, userInfo in
    guard let userInfo else {
        return
    }

    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.refresh()
    }
}
