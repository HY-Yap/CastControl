//
//  DisplayArrangementView.swift
//  CastControl
//

import AppKit
import CoreGraphics
import SwiftUI

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
