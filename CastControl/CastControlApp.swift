//
//  CastControlApp.swift
//  CastControl
//
//  Created by Yap Han Yang on 14/6/26.
//

import SwiftUI

@main
struct CastControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var displayManager = DisplayManager()
    @StateObject private var desktopVisibility = DesktopVisibilityController()
    @StateObject private var preventSleep = PreventSleepController()

    var body: some Scene {
        MenuBarExtra("CastControl", systemImage: "display.2") {
            ContentView(
                displayManager: displayManager,
                desktopVisibility: desktopVisibility,
                preventSleep: preventSleep
            )
                .onAppear {
                    displayManager.refresh()
                }
        }
        .menuBarExtraStyle(.window)

        Window("About CastControl", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Arrange Displays", id: "arrange") {
            DisplayArrangementView(displayManager: displayManager)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isPrimaryInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let current = NSRunningApplication.current
        guard let bundleIdentifier = current.bundleIdentifier else {
            NSApp.terminate(nil)
            return
        }

        // Use a stable ordering so simultaneous launches do not reject each other.
        let existingInstance = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first { application in
            guard application.processIdentifier != current.processIdentifier,
                  !application.isTerminated else { return false }
            if let otherLaunch = application.launchDate,
               let currentLaunch = current.launchDate,
               otherLaunch != currentLaunch {
                return otherLaunch < currentLaunch
            }
            return application.processIdentifier < current.processIdentifier
        }

        guard existingInstance == nil else {
            NSApp.terminate(nil)
            return
        }
        isPrimaryInstance = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryInstance else { return }
        NSApp.setActivationPolicy(.accessory)
        DesktopVisibilityController.restoreIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isPrimaryInstance else { return }
        DesktopVisibilityController.restoreIfNeeded()
        PreventSleepController.releaseActiveAssertion()
    }
}
