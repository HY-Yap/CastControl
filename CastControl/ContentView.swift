//
//  ContentView.swift
//  CastControl
//

import AppKit
import CoreGraphics
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var desktopVisibility: DesktopVisibilityController
    @ObservedObject var preventSleep: PreventSleepController
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CastControl")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            PanelDivider()

            VStack(spacing: 0) {
                QuickActionRow(
                    title: desktopVisibility.actionTitle,
                    systemImage: desktopVisibility.actionSystemImage,
                    isSelected: desktopVisibility.clutterState == .hidden
                ) {
                    desktopVisibility.toggleDesktopClutter()
                }

                QuickActionRow(
                    title: "Prevent Sleep",
                    systemImage: preventSleep.actionSystemImage,
                    isSelected: preventSleep.isPreventingSleep
                ) {
                    preventSleep.togglePreventSleep()
                }
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Displays")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)

                if displayManager.externalDisplays.isEmpty {
                    EmptyDisplaysRow()
                } else {
                    ForEach(displayManager.externalDisplays) { display in
                        DisplayRow(
                            display: display,
                            displayManager: displayManager,
                            isExpanded: expandedDisplayIDs.contains(display.id),
                            toggleExpanded: {
                                toggleExpanded(display.id)
                            }
                        )
                    }
                }
            }

            PanelDivider()

            VStack(spacing: 2) {
                PanelActionRow(title: "Arrange Displays", systemImage: "rectangle.3.group") {
                    openWindow(id: "arrange")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .leadingIconHidden()
                
                PanelActionRow(title: "Display Settings...", systemImage: "gearshape") {
                    SystemSettings.openDisplays()
                }
                .leadingIconHidden()

                PanelActionRow(title: "About CastControl", systemImage: "info.circle") {
                    openWindow(id: "about")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .leadingIconHidden()

                PanelActionRow(title: "Quit CastControl", systemImage: "power") {
                    desktopVisibility.restoreIfNeeded()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
                .leadingIconHidden()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 318)
        .background(.regularMaterial)
        .onAppear {
            desktopVisibility.refresh()
            preventSleep.refresh()
        }
    }

    private func toggleExpanded(_ displayID: CGDirectDisplayID) {
        if expandedDisplayIDs.contains(displayID) {
            expandedDisplayIDs.remove(displayID)
        } else {
            expandedDisplayIDs.insert(displayID)
        }
    }
}

private struct QuickActionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(iconBackground, in: Circle())

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(QuickActionButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
    }

    private var iconBackground: Color {
        if isSelected {
            return Color(nsColor: .systemBlue)
        }

        return Color.primary.opacity(0.06)
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(rowBackground(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }

    private func rowBackground(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.11)
        }

        if isHovered {
            return Color.primary.opacity(0.07)
        }

        return .clear
    }
}

private struct DisplayRow: View {
    let display: ManagedDisplay
    @ObservedObject var displayManager: DisplayManager
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 11) {
                    Image(systemName: display.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(display.modeDescriptionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .controlCentreRowHover()

            if isExpanded {
                PanelDivider()
                    .padding(.leading, 49)
                    .padding(.trailing, 8)

                VStack(spacing: 2) {
                    DisplayActionRow(
                        title: "Mirror - Fit External Display",
                        systemImage: "rectangle.on.rectangle",
                        isSelected: display.isMirrorMaster,
                        action: {
                            displayManager.mirrorToMainDisplay(display, optimization: .fitExternal)
                        }
                    )

                    DisplayActionRow(
                        title: "Mirror - Match Mac Display",
                        systemImage: "macbook.and.iphone",
                        isSelected: display.isMirroring(displayManager.mainDisplayID),
                        action: {
                            displayManager.mirrorToMainDisplay(display, optimization: .matchMac)
                        }
                    )

                    DisplayActionRow(
                        title: "Extend",
                        systemImage: "rectangle.connected.to.line.below",
                        isSelected: display.isExtended,
                        action: {
                            displayManager.extendDisplay(display)
                        }
                    )

                    if let audioOutput = displayManager.audioOutput(for: display) {
                        DisplayActionRow(
                            title: displayManager.isUsingAudioOutput(audioOutput) ? "Using as Sound Output" : "Use as Sound Output",
                            systemImage: "speaker.wave.2",
                            isSelected: displayManager.isUsingAudioOutput(audioOutput),
                            action: {
                                displayManager.toggleAudioOutput(audioOutput)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct DisplayActionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PanelActionRow(title: title, systemImage: systemImage, inset: 8, action: action) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct PanelActionRow<Trailing: View>: View {
    @Environment(\.leadingIconHidden) private var leadingIconHidden

    let title: String
    let systemImage: String
    var inset = 0.0
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovered = false

    init(
        title: String,
        systemImage: String,
        inset: Double = 0,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.inset = inset
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !leadingIconHidden {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                trailing()
                    .frame(width: 18, alignment: .trailing)
            }
            .padding(.leading, 8 + inset)
            .padding(.trailing, 9)
            .padding(.vertical, 7)
            .background(isHovered ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct LeadingIconHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var leadingIconHidden: Bool {
        get { self[LeadingIconHiddenKey.self] }
        set { self[LeadingIconHiddenKey.self] = newValue }
    }
}

private extension View {
    func leadingIconHidden() -> some View {
        environment(\.leadingIconHidden, true)
    }
}

private extension PanelActionRow where Trailing == EmptyView {
    init(title: String, systemImage: String, inset: Double = 0, action: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, inset: inset, action: action) {
            EmptyView()
        }
    }
}

private struct EmptyDisplaysRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text("No external displays connected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct ControlCentreRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func controlCentreRowHover() -> some View {
        modifier(ControlCentreRowHover())
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(height: 1)
    }
}
