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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DesktopVisibilityController.restoreIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopVisibilityController.restoreIfNeeded()
        PreventSleepController.releaseActiveAssertion()
    }
}
