//
//  ContentView.swift
//  CastControl
//
//  Created by Yap Han Yang on 14/6/26.
//

import CoreGraphics
import AppKit
import Combine
import CoreAudio
import IOKit
import IOKit.graphics
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var desktopVisibility: DesktopVisibilityController
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CastControl")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            PanelDivider()

            PanelActionRow(
                title: desktopVisibility.isHidden ? "Show Desktop Icons & Widgets" : "Hide Desktop Icons & Widgets",
                systemImage: desktopVisibility.isHidden ? "eye.slash" : "eye"
            ) {
                desktopVisibility.isHidden.toggle()
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
    }

    private func toggleExpanded(_ displayID: CGDirectDisplayID) {
        if expandedDisplayIDs.contains(displayID) {
            expandedDisplayIDs.remove(displayID)
        } else {
            expandedDisplayIDs.insert(displayID)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CastControl")
                        .font(.title3.weight(.semibold))

                    Text("v0.1.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("A tiny menu bar utility for switching display modes\nand hiding desktop clutter before presenting.")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Developer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Yap Han Yang")
                    .font(.system(size: 13))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 190)
        .background(.regularMaterial)
        .background(AboutWindowConfigurator())
    }
}

struct DisplayArrangementView: View {
    @ObservedObject var displayManager: DisplayManager
    @State private var layout = DisplayArrangementLayout(displays: [])
    @State private var layoutMode: ArrangementLayoutMode = .horizontal
    @State private var activeDisplayID: CGDirectDisplayID?
    @State private var highlightedCell: ArrangementGridPosition?
    @State private var didApply = false
    @State private var hasChanges = false
    @State private var arrangedDisplayIDs: Set<CGDirectDisplayID> = []
    @State private var baselineLayout = DisplayArrangementLayout(displays: [])
    @State private var baselineLayoutMode: ArrangementLayoutMode = .horizontal

    private let canvasSize = CGSize(width: 680, height: 420)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arrange Displays")
                        .font(.title3.weight(.semibold))

                    Text("Choose a horizontal or vertical screen arrangement.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reset") {
                    restoreBaselineLayout()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    guard canApplyArrangement else {
                        return
                    }

                    displayManager.applyArrangement(layout)
                    baselineLayout = layout
                    baselineLayoutMode = layoutMode
                    didApply = true
                    hasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApplyArrangement)
            }

            arrangementCanvas
                .frame(width: canvasSize.width, height: canvasSize.height)

            HStack(spacing: 10) {
                Picker("Layout", selection: $layoutMode) {
                    ForEach(ArrangementLayoutMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 248)
                .onChange(of: layoutMode) { _, newMode in
                    guard newMode != layout.mode else {
                        return
                    }

                    setLayout(mode: newMode, useSystemArrangement: false, markChanged: true, updateBaseline: false)
                }

                Spacer()

                Text("Arrangement affects where your cursor moves between screens.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 720)
        .background(.regularMaterial)
        .background(ArrangementWindowConfigurator())
        .onAppear {
            loadSystemLayoutAsBaseline()
        }
        .onReceive(displayManager.$displays) { displays in
            let displayIDs = Set(displays.map(\.id))
            guard displayIDs != arrangedDisplayIDs else {
                return
            }

            loadSystemLayoutAsBaseline()
        }
    }

    @ViewBuilder
    private var arrangementCanvas: some View {
        if layout.displays.count <= 1 {
            ZStack {
                ArrangementCanvasBackground()
                ForEach(layout.displays) { display in
                    ArrangementTile(
                        display: display,
                        isMain: display.id == displayManager.mainDisplayID,
                        isDragging: false
                    )
                    .frame(width: 160, height: 96)
                    .position(x: canvasSize.width / 2, y: canvasSize.height / 2 - 28)
                }

                VStack(spacing: 8) {
                    Spacer()
                    Text("Connect another display to arrange screens.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 28)
                }
            }
        } else if !canArrange {
            ZStack {
                ArrangementCanvasBackground()
                VStack(spacing: 12) {
                    Text("Arrangement is available when displays are extended.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Button("Switch to Extend") {
                        displayManager.extendAllDisplays()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ZStack(alignment: .topLeading) {
                ArrangementCanvasBackground()

                ArrangementSlotGrid(
                    slots: layout.slots(in: canvasSize),
                    highlightedCell: highlightedCell
                )

                ForEach(layout.displays) { display in
                    let slotFrame = layout.frame(for: display.id, in: canvasSize)

                    ArrangementTile(
                        display: display,
                        isMain: display.id == displayManager.mainDisplayID,
                        isDragging: activeDisplayID == display.id
                    )
                    .frame(width: slotFrame.width, height: slotFrame.height)
                    .position(x: slotFrame.midX, y: slotFrame.midY)
                    .zIndex(activeDisplayID == display.id ? 10 : 0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.84), value: slotFrame)
                    .gesture(
                        DragGesture(coordinateSpace: .named("arrangementCanvas"))
                            .onChanged { value in
                                activeDisplayID = display.id
                                guard let targetCell = layout.nearestCell(to: value.location, in: canvasSize) else {
                                    highlightedCell = nil
                                    return
                                }

                                highlightedCell = targetCell
                                if layout.moveDisplay(id: display.id, to: targetCell) {
                                    hasChanges = true
                                    didApply = false
                                }
                            }
                            .onEnded { value in
                                if let targetCell = layout.nearestCell(to: value.location, in: canvasSize) {
                                    if layout.moveDisplay(id: display.id, to: targetCell) {
                                        hasChanges = true
                                        didApply = false
                                    }
                                }

                                activeDisplayID = nil
                                highlightedCell = nil
                            }
                    )
                }
            }
            .coordinateSpace(name: "arrangementCanvas")
        }
    }

    private var canArrange: Bool {
        layout.displays.count > 1 && displayManager.externalDisplays.allSatisfy(\.isExtended)
    }

    private var canApplyArrangement: Bool {
        hasChanges && canArrange
    }

    private func loadSystemLayoutAsBaseline() {
        let displays = displayManager.arrangementDisplays()
        let mode = DisplayArrangementLayout.inferredMode(for: displays)
        layout = DisplayArrangementLayout(
            displays: displays,
            mode: mode,
            mainDisplayID: displayManager.mainDisplayID,
            useSystemArrangement: true
        )
        layoutMode = mode
        baselineLayout = layout
        baselineLayoutMode = mode
        arrangedDisplayIDs = Set(layout.displays.map(\.id))
        didApply = false
        hasChanges = false
    }

    private func restoreBaselineLayout() {
        layout = baselineLayout
        layoutMode = baselineLayoutMode
        arrangedDisplayIDs = Set(layout.displays.map(\.id))
        didApply = false
        hasChanges = false
    }

    private func setLayout(
        mode: ArrangementLayoutMode,
        useSystemArrangement: Bool,
        markChanged: Bool,
        updateBaseline: Bool
    ) {
        layoutMode = mode
        layout = DisplayArrangementLayout(
            displays: displayManager.arrangementDisplays(),
            mode: mode,
            mainDisplayID: displayManager.mainDisplayID,
            useSystemArrangement: useSystemArrangement
        )
        arrangedDisplayIDs = Set(layout.displays.map(\.id))

        if updateBaseline {
            baselineLayout = layout
            baselineLayoutMode = mode
        }

        didApply = false
        hasChanges = markChanged
    }
}

private struct ArrangementTile: View {
    let display: ArrangementDisplay
    let isMain: Bool
    let isDragging: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isMain ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isMain ? Color.accentColor.opacity(0.72) : Color.primary.opacity(0.16), lineWidth: isMain ? 1.5 : 1)
                }
                .shadow(color: .black.opacity(isDragging ? 0.18 : 0.10), radius: isDragging ? 16 : 10, x: 0, y: isDragging ? 8 : 5)

            VStack(spacing: 5) {
                Image(systemName: display.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isMain ? Color.accentColor : Color.secondary)

                Text(display.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if isMain {
                    Text("Main")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .scaleEffect(isDragging ? 1.03 : 1)
        .help("\(display.name) - \(Int(display.pixelBounds.width)) x \(Int(display.pixelBounds.height))")
    }
}

private struct ArrangementCanvasBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

private struct ArrangementSlotGrid: View {
    let slots: [ArrangementSlot]
    let highlightedCell: ArrangementGridPosition?

    var body: some View {
        ZStack {
            ForEach(slots) { slot in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(slot.position == highlightedCell ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                slot.position == highlightedCell ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    }
                    .frame(width: slot.frame.width, height: slot.frame.height)
                    .position(x: slot.frame.midX, y: slot.frame.midY)
            }
        }
        .animation(.easeOut(duration: 0.12), value: highlightedCell)
    }
}

private struct ArrangementWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
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

private struct AboutWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
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

struct ManagedDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let mirrorsDisplayID: CGDirectDisplayID
    let isInMirrorSet: Bool
    let isSidecar: Bool

    var symbolName: String {
        if isBuiltin {
            return "macbook"
        }

        return isSidecar ? "ipad.landscape" : "display"
    }

    var isExtended: Bool {
        mirrorsDisplayID == kCGNullDirectDisplay && !isInMirrorSet
    }

    var isMirrorMaster: Bool {
        mirrorsDisplayID == kCGNullDirectDisplay && isInMirrorSet
    }

    func isMirroring(_ displayID: CGDirectDisplayID) -> Bool {
        mirrorsDisplayID == displayID
    }

    var modeDescription: String {
        if mirrorsDisplayID != kCGNullDirectDisplay {
            return "Mirror"
        }

        if isInMirrorSet {
            return "Mirror"
        }

        return "Extend"
    }

    var modeDescriptionText: String {
        switch modeDescription {
        case "Extend":
            return "Extended"
        case "Mirror":
            return "Mirrored"
        default:
            return modeDescription
        }
    }
}

struct ArrangementDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isSidecar: Bool
    let pixelBounds: CGRect
    let originalOrigin: CGPoint
    var gridPosition: ArrangementGridPosition

    var symbolName: String {
        if isBuiltin {
            return "macbook"
        }

        return isSidecar ? "ipad.landscape" : "display"
    }
}

enum ArrangementLayoutMode: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal:
            return "Horizontal"
        case .vertical:
            return "Vertical"
        }
    }
}

struct ArrangementGridPosition: Hashable, Equatable {
    var row: Int
    var column: Int
}

struct ArrangementSlot: Identifiable, Equatable {
    let position: ArrangementGridPosition
    let frame: CGRect

    var id: String {
        "\(position.row)-\(position.column)"
    }
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let normalizedName: String
}

struct DisplayArrangementLayout {
    var displays: [ArrangementDisplay]
    var mode: ArrangementLayoutMode
    var mainDisplayID: CGDirectDisplayID
    var rows: Int
    var columns: Int

    init(displays: [ArrangementDisplay]) {
        self.displays = displays
        self.mode = .horizontal
        self.mainDisplayID = CGMainDisplayID()
        self.rows = 1
        self.columns = max(displays.count, 1)
    }

    init(
        displays sourceDisplays: [ArrangementDisplay],
        mode: ArrangementLayoutMode,
        mainDisplayID: CGDirectDisplayID,
        useSystemArrangement: Bool
    ) {
        self.mode = mode
        self.mainDisplayID = mainDisplayID

        guard !sourceDisplays.isEmpty else {
            self.displays = []
            self.rows = 1
            self.columns = 1
            return
        }

        let gridSize = Self.gridSize(for: sourceDisplays.count, mode: mode)
        self.rows = gridSize.rows
        self.columns = gridSize.columns

        if useSystemArrangement {
            self.displays = Self.displaysMappedFromSystemArrangement(
                sourceDisplays,
                mode: mode,
                rows: gridSize.rows,
                columns: gridSize.columns
            )
        } else {
            self.displays = Self.displaysMappedToDefaultArrangement(
                sourceDisplays,
                mode: mode,
                mainDisplayID: mainDisplayID
            )
        }
    }

    static func inferredMode(for displays: [ArrangementDisplay]) -> ArrangementLayoutMode {
        guard displays.count > 1 else {
            return .horizontal
        }

        let centerXs = displays.map { $0.pixelBounds.midX }
        let centerYs = displays.map { $0.pixelBounds.midY }
        let xSpread = (centerXs.max() ?? 0) - (centerXs.min() ?? 0)
        let ySpread = (centerYs.max() ?? 0) - (centerYs.min() ?? 0)

        return ySpread > xSpread ? .vertical : .horizontal
    }

    mutating func moveDisplay(id: CGDirectDisplayID, to targetCell: ArrangementGridPosition) -> Bool {
        guard
            let index = displays.firstIndex(where: { $0.id == id }),
            isValidCell(targetCell)
        else {
            return false
        }

        let currentCell = displays[index].gridPosition
        guard currentCell != targetCell else {
            return false
        }

        if let occupiedIndex = displays.firstIndex(where: { $0.gridPosition == targetCell }) {
            displays[occupiedIndex].gridPosition = currentCell
        }

        displays[index].gridPosition = targetCell
        return true
    }

    func nearestCell(to point: CGPoint, in canvasSize: CGSize) -> ArrangementGridPosition? {
        slots(in: canvasSize)
            .min { lhs, rhs in
                distance(from: point, to: CGPoint(x: lhs.frame.midX, y: lhs.frame.midY))
                    < distance(from: point, to: CGPoint(x: rhs.frame.midX, y: rhs.frame.midY))
            }?
            .position
    }

    func frame(for displayID: CGDirectDisplayID, in canvasSize: CGSize) -> CGRect {
        guard
            let display = displays.first(where: { $0.id == displayID }),
            let slot = slots(in: canvasSize).first(where: { $0.position == display.gridPosition })
        else {
            return .zero
        }

        return tileFrame(for: display, in: slot.frame)
    }

    func slots(in canvasSize: CGSize) -> [ArrangementSlot] {
        let padding: CGFloat = 20
        let gap: CGFloat = 12
        let availableWidth = canvasSize.width - padding * 2 - CGFloat(columns - 1) * gap
        let availableHeight = canvasSize.height - padding * 2 - CGFloat(rows - 1) * gap
        let cellWidth = availableWidth / CGFloat(max(columns, 1))
        let cellHeight = availableHeight / CGFloat(max(rows, 1))

        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let frame = CGRect(
                    x: padding + CGFloat(column) * (cellWidth + gap),
                    y: padding + CGFloat(row) * (cellHeight + gap),
                    width: cellWidth,
                    height: cellHeight
                )

                return ArrangementSlot(position: ArrangementGridPosition(row: row, column: column), frame: frame)
            }
        }
    }

    func proposedOrigins(anchoredTo mainDisplayID: CGDirectDisplayID) -> [CGDirectDisplayID: CGPoint] {
        let virtualRects = Dictionary(uniqueKeysWithValues: displays.map { display in
            (display.id, virtualRect(for: display))
        })

        guard
            let mainDisplay = displays.first(where: { $0.id == mainDisplayID }),
            let mainVirtualRect = virtualRects[mainDisplayID]
        else {
            return Dictionary(uniqueKeysWithValues: virtualRects.map { ($0.key, $0.value.origin) })
        }

        let anchorOffset = CGPoint(
            x: mainDisplay.originalOrigin.x - mainVirtualRect.minX,
            y: mainDisplay.originalOrigin.y - mainVirtualRect.minY
        )

        return Dictionary(uniqueKeysWithValues: virtualRects.map { displayID, rect in
            (
                displayID,
                CGPoint(
                    x: rect.minX + anchorOffset.x,
                    y: rect.minY + anchorOffset.y
                )
            )
        })
    }

    private func tileFrame(for display: ArrangementDisplay, in slotFrame: CGRect) -> CGRect {
        let aspectRatio = max(display.pixelBounds.width / max(display.pixelBounds.height, 1), 0.6)
        let maxWidth = slotFrame.width * 0.82
        let maxHeight = slotFrame.height * 0.70
        var width = maxWidth
        var height = width / aspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        width = min(max(width, 82), slotFrame.width * 0.90)
        height = min(max(height, 54), slotFrame.height * 0.82)

        return CGRect(
            x: slotFrame.midX - width / 2,
            y: slotFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func virtualRect(for display: ArrangementDisplay) -> CGRect {
        let cellSize = CGSize(width: 1000, height: 700)
        let aspectRatio = max(display.pixelBounds.width / max(display.pixelBounds.height, 1), 0.6)
        var width = cellSize.width * 0.82
        var height = width / aspectRatio

        if height > cellSize.height * 0.76 {
            height = cellSize.height * 0.76
            width = height * aspectRatio
        }

        let cellOrigin = CGPoint(
            x: CGFloat(display.gridPosition.column) * cellSize.width,
            y: CGFloat(display.gridPosition.row) * cellSize.height
        )

        return CGRect(
            x: cellOrigin.x + (cellSize.width - width) / 2,
            y: cellOrigin.y + (cellSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func isValidCell(_ cell: ArrangementGridPosition) -> Bool {
        cell.row >= 0 && cell.row < rows && cell.column >= 0 && cell.column < columns
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func gridSize(for displayCount: Int, mode: ArrangementLayoutMode) -> (rows: Int, columns: Int) {
        switch mode {
        case .horizontal:
            return (1, max(displayCount, 1))
        case .vertical:
            return (max(displayCount, 1), 1)
        }
    }

    private static func displaysMappedToDefaultArrangement(
        _ sourceDisplays: [ArrangementDisplay],
        mode: ArrangementLayoutMode,
        mainDisplayID: CGDirectDisplayID
    ) -> [ArrangementDisplay] {
        let orderedDisplays = orderedWithMainFirst(sourceDisplays, mainDisplayID: mainDisplayID)

        return orderedDisplays.enumerated().map { index, display in
            var arrangedDisplay = display
            switch mode {
            case .horizontal:
                arrangedDisplay.gridPosition = ArrangementGridPosition(row: 0, column: index)
            case .vertical:
                arrangedDisplay.gridPosition = ArrangementGridPosition(row: index, column: 0)
            }
            return arrangedDisplay
        }
    }

    private static func displaysMappedFromSystemArrangement(
        _ sourceDisplays: [ArrangementDisplay],
        mode: ArrangementLayoutMode,
        rows: Int,
        columns: Int
    ) -> [ArrangementDisplay] {
        let sortedDisplays: [ArrangementDisplay]
        switch mode {
        case .horizontal:
            sortedDisplays = sourceDisplays.sorted { $0.originalOrigin.x < $1.originalOrigin.x }
        case .vertical:
            sortedDisplays = sourceDisplays.sorted { $0.originalOrigin.y < $1.originalOrigin.y }
        }

        return sortedDisplays.enumerated().map { index, display in
            var arrangedDisplay = display
            switch mode {
            case .horizontal:
                arrangedDisplay.gridPosition = ArrangementGridPosition(row: 0, column: min(index, columns - 1))
            case .vertical:
                arrangedDisplay.gridPosition = ArrangementGridPosition(row: min(index, rows - 1), column: 0)
            }
            return arrangedDisplay
        }
    }

    private static func orderedWithMainFirst(
        _ displays: [ArrangementDisplay],
        mainDisplayID: CGDirectDisplayID
    ) -> [ArrangementDisplay] {
        displays.sorted { lhs, rhs in
            if lhs.id == mainDisplayID {
                return true
            }
            if rhs.id == mainDisplayID {
                return false
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var audioOutputDevices: [AudioOutputDevice] = []
    @Published private(set) var defaultAudioOutputDeviceID: AudioDeviceID?

    private var reconfigurationCallbackRegistered = false
    private var previousAudioOutputDeviceID: AudioDeviceID?

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
                let displayName = Self.displayName(for: displayID, localizedScreenName: screenNames[displayID])
                let isSidecar = Self.isSidecarName(displayName)

                return ManagedDisplay(
                    id: displayID,
                    name: displayName,
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
    }

    func audioOutput(for display: ManagedDisplay) -> AudioOutputDevice? {
        guard !display.isBuiltin else {
            return nil
        }

        let displayName = Self.normalizedAudioMatchName(display.name)
        guard !displayName.isEmpty else {
            return nil
        }

        if let exactMatch = audioOutputDevices.first(where: { $0.normalizedName == displayName }) {
            return exactMatch
        }

        if let containedMatch = audioOutputDevices.first(where: {
            $0.normalizedName.contains(displayName) || displayName.contains($0.normalizedName)
        }) {
            return containedMatch
        }

        let genericDisplayOutputs = audioOutputDevices.filter { device in
            Self.isGenericDisplayAudioName(device.normalizedName)
        }

        if genericDisplayOutputs.count == 1, externalDisplays.count == 1 {
            return genericDisplayOutputs[0]
        }

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
    }

    private func registerForDisplayChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context) == .success {
            reconfigurationCallbackRegistered = true
        }
    }

    private func refreshAudioOutputs() {
        audioOutputDevices = Self.outputAudioDevices()
        defaultAudioOutputDeviceID = Self.defaultAudioOutputDeviceID()

        if
            let previousAudioOutputDeviceID,
            !audioOutputDevices.contains(where: { $0.id == previousAudioOutputDeviceID })
        {
            self.previousAudioOutputDeviceID = nil
        }
    }

    private func restorePreviousAudioOutput() {
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

    private func setDefaultAudioOutputDevice(_ deviceID: AudioDeviceID) {
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

    private static func normalizedAudioMatchName(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGenericDisplayAudioName(_ normalizedName: String) -> Bool {
        normalizedName == "hdmi"
            || normalizedName.contains("hdmi")
            || normalizedName.contains("displayport")
            || normalizedName.contains("display port")
            || normalizedName.contains("usb c display")
    }

    private static func isMacSpeakerName(_ normalizedName: String) -> Bool {
        normalizedName.contains("macbook") && normalizedName.contains("speaker")
            || normalizedName.contains("built in output")
            || normalizedName.contains("internal speaker")
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

    private static func displayName(for displayID: CGDirectDisplayID, localizedScreenName: String?) -> String {
        if let localizedScreenName, !localizedScreenName.isEmpty {
            return localizedScreenName
        }

        if let ioDisplayName = ioDisplayName(for: displayID), !ioDisplayName.isEmpty {
            return ioDisplayName
        }

        return fallbackName(for: displayID)
    }

    private static func fallbackName(for displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Mac Display"
        }

        return "Display \(displayID)"
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

    private static func isSidecarName(_ name: String) -> Bool {
        let normalizedName = name.localizedLowercase
        return normalizedName.contains("sidecar") || normalizedName.contains("airplay")
    }
}

enum MirrorOptimization {
    case fitExternal
    case matchMac
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

final class DesktopVisibilityController: ObservableObject {
    private static let restoreNeededKey = "DesktopVisibilityRestoreNeeded"

    @Published var isHidden = false {
        didSet {
            guard isHidden != oldValue else {
                return
            }

            apply(hidden: isHidden)
        }
    }

    func showDesktop() {
        isHidden = false
        apply(hidden: false)
    }

    func restoreIfNeeded() {
        Self.restoreIfNeeded()
        isHidden = false
    }

    static func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: restoreNeededKey) else {
            return
        }

        apply(hidden: false)
    }

    private func apply(hidden: Bool) {
        Self.apply(hidden: hidden)
    }

    private static func apply(hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: restoreNeededKey)
        Self.setDefaults(domain: "com.apple.finder", key: "CreateDesktop", boolValue: !hidden)
        Self.setDefaults(domain: "com.apple.WindowManager", key: "StandardHideWidgets", boolValue: hidden)
        Self.setDefaults(domain: "com.apple.WindowManager", key: "StageManagerHideWidgets", boolValue: hidden)
        Self.run("/usr/bin/killall", arguments: ["Finder"])
        Self.run("/usr/bin/killall", arguments: ["WindowManager"])
    }

    private static func setDefaults(domain: String, key: String, boolValue: Bool) {
        run("/usr/bin/defaults", arguments: ["write", domain, key, "-bool", boolValue ? "true" : "false"])
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
}

enum SystemSettings {
    static func openDisplays() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

enum SystemCommand {
    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) -> Bool {
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

    static func output(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
