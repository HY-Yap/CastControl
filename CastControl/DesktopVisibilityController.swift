//
//  DesktopVisibilityController.swift
//  CastControl
//

import Combine
import Foundation

final class DesktopVisibilityController: ObservableObject {
    private static let restoreNeededKey = "DesktopVisibilityRestoreNeeded"
    private static let controlledDefaults = [
        DesktopDefault(
            domain: "com.apple.finder",
            key: "CreateDesktop",
            hiddenValue: false,
            visibleValue: true
        ),
        DesktopDefault(
            domain: "com.apple.WindowManager",
            key: "StandardHideWidgets",
            hiddenValue: true,
            visibleValue: false
        ),
        DesktopDefault(
            domain: "com.apple.WindowManager",
            key: "StageManagerHideWidgets",
            hiddenValue: true,
            visibleValue: false
        )
    ]

    @Published private(set) var clutterState: DesktopClutterState = .visible

    var actionTitle: String {
        switch clutterState {
        case .hidden:
            return "Show Desktop Icons & Widgets"
        case .visible, .mixed:
            return "Hide Desktop Icons & Widgets"
        }
    }

    var actionSystemImage: String {
        switch clutterState {
        case .hidden:
            return "eye.slash"
        case .visible, .mixed:
            return "eye"
        }
    }

    init() {
        refresh()
    }

    func refresh() {
        clutterState = Self.currentClutterState()
    }

    func toggleDesktopClutter() {
        refresh()

        switch clutterState {
        case .hidden:
            apply(hidden: false)
        case .visible, .mixed:
            Self.clearSnapshotIfCurrentStateChangedExternally()
            apply(hidden: true)
        }

        refresh()
    }

    func restoreIfNeeded() {
        Self.restoreIfNeeded()
        refresh()
    }

    static func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: restoreNeededKey) else {
            return
        }

        guard currentClutterState() == .hidden else {
            clearSnapshot()
            return
        }

        for desktopDefault in controlledDefaults {
            desktopDefault.restoreSnapshot()
        }

        clearSnapshot()

        restartDesktopServices()
    }

    private func apply(hidden: Bool) {
        Self.apply(hidden: hidden)
    }

    private static func apply(hidden: Bool) {
        if hidden {
            saveSnapshotIfNeeded()
            UserDefaults.standard.set(true, forKey: restoreNeededKey)

            for desktopDefault in controlledDefaults {
                desktopDefault.applyHiddenValue()
            }

            restartDesktopServices()
        } else {
            if UserDefaults.standard.bool(forKey: restoreNeededKey) {
                restoreIfNeeded()
            } else {
                for desktopDefault in controlledDefaults {
                    desktopDefault.applyVisibleValue()
                }

                restartDesktopServices()
            }
        }
    }

    private static func currentClutterState() -> DesktopClutterState {
        let hiddenStates = controlledDefaults.map { $0.isCurrentlyHidden() }

        if hiddenStates.allSatisfy({ $0 }) {
            return .hidden
        }

        if hiddenStates.allSatisfy({ !$0 }) {
            return .visible
        }

        return .mixed
    }

    private static func saveSnapshotIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: restoreNeededKey) else {
            return
        }

        for desktopDefault in controlledDefaults {
            desktopDefault.saveSnapshot()
        }
    }

    private static func clearSnapshotIfCurrentStateChangedExternally() {
        guard UserDefaults.standard.bool(forKey: restoreNeededKey),
              currentClutterState() != .hidden else {
            return
        }

        clearSnapshot()
    }

    private static func clearSnapshot() {
        UserDefaults.standard.set(false, forKey: restoreNeededKey)
        for desktopDefault in controlledDefaults {
            desktopDefault.clearSnapshot()
        }
    }

    private static func restartDesktopServices() {
        Self.run("/usr/bin/killall", arguments: ["Finder"])
        Self.run("/usr/bin/killall", arguments: ["WindowManager"])
    }

    private static func setDefaults(domain: String, key: String, boolValue: Bool) {
        run("/usr/bin/defaults", arguments: ["write", domain, key, "-bool", boolValue ? "true" : "false"])
    }

    private static func deleteDefaults(domain: String, key: String) {
        run("/usr/bin/defaults", arguments: ["delete", domain, key])
    }

    private static func readDefaults(domain: String, key: String) -> Bool? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        process.standardOutput = pipe
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch output {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    @discardableResult
    private static func run(_ launchPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private struct DesktopDefault {
        let domain: String
        let key: String
        let hiddenValue: Bool
        let visibleValue: Bool

        private var snapshotExistsKey: String {
            "DesktopVisibilitySnapshot.\(domain).\(key).exists"
        }

        private var snapshotValueKey: String {
            "DesktopVisibilitySnapshot.\(domain).\(key).value"
        }

        func saveSnapshot() {
            let value = DesktopVisibilityController.readDefaults(domain: domain, key: key)
            UserDefaults.standard.set(value != nil, forKey: snapshotExistsKey)

            if let value {
                UserDefaults.standard.set(value, forKey: snapshotValueKey)
            } else {
                UserDefaults.standard.removeObject(forKey: snapshotValueKey)
            }
        }

        func applyHiddenValue() {
            DesktopVisibilityController.setDefaults(domain: domain, key: key, boolValue: hiddenValue)
        }

        func applyVisibleValue() {
            DesktopVisibilityController.setDefaults(domain: domain, key: key, boolValue: visibleValue)
        }

        func isCurrentlyHidden() -> Bool {
            let currentValue = DesktopVisibilityController.readDefaults(domain: domain, key: key) ?? visibleValue
            return currentValue == hiddenValue
        }

        func restoreSnapshot() {
            if UserDefaults.standard.bool(forKey: snapshotExistsKey) {
                let value = UserDefaults.standard.bool(forKey: snapshotValueKey)
                DesktopVisibilityController.setDefaults(domain: domain, key: key, boolValue: value)
            } else {
                DesktopVisibilityController.deleteDefaults(domain: domain, key: key)
            }
        }

        func clearSnapshot() {
            UserDefaults.standard.removeObject(forKey: snapshotExistsKey)
            UserDefaults.standard.removeObject(forKey: snapshotValueKey)
        }
    }
}
