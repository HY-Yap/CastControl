//
//  PreventSleepController.swift
//  CastControl
//

import Combine
import Foundation
import IOKit.pwr_mgt

final class PreventSleepController: ObservableObject {
    private static var activeAssertionID: IOPMAssertionID?
    private static let assertionName = "CastControl Prevent Sleep"
    private static let assertionType = kIOPMAssertionTypeNoDisplaySleep as CFString

    @Published private(set) var isPreventingSleep = false

    var actionSystemImage: String {
        isPreventingSleep ? "moon.zzz.fill" : "moon.zzz"
    }

    init() {
        refresh()
    }

    func refresh() {
        isPreventingSleep = Self.hasActiveAssertion
    }

    func togglePreventSleep() {
        refresh()

        if Self.hasActiveAssertion {
            Self.releaseActiveAssertion()
            refresh()
            return
        }

        Self.createAssertionIfNeeded()
        refresh()
    }

    func releaseActiveAssertion() {
        Self.releaseActiveAssertion()
        refresh()
    }

    static func releaseActiveAssertion() {
        guard let assertionID = activeAssertionID else {
            return
        }

        let status = IOPMAssertionRelease(assertionID)
        debugLog("released sleep assertion type=\(assertionType) id=\(assertionID) status=\(status)")
        activeAssertionID = nil
    }

    private static var hasActiveAssertion: Bool {
        activeAssertionID != nil
    }

    private static func createAssertionIfNeeded() {
        guard activeAssertionID == nil else {
            debugLog("prevent sleep assertion already active type=\(assertionType) id=\(activeAssertionID ?? 0)")
            return
        }

        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName as CFString,
            &assertionID
        )

        debugLog("created sleep assertion type=\(assertionType) id=\(assertionID) status=\(status)")

        if status == kIOReturnSuccess {
            activeAssertionID = assertionID
        }
    }

    private static func debugLog(_ message: String) {
        print("[CastControl] \(message)")
    }
}
