//
//  Models.swift
//  CastControl
//

import AppKit
import CoreAudio
import CoreGraphics
import Foundation

struct ManagedDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let identity: DisplayIdentity
    let name: String
    let aliases: [String]
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

struct DisplayIdentity: Hashable, Equatable {
    let vendorID: UInt32
    let modelID: UInt32
    let serialNumber: UInt32
    let fallbackDisplayID: CGDirectDisplayID

    var cacheKey: String {
        if vendorID != 0 || modelID != 0 || serialNumber != 0 {
            return "vendor:\(vendorID)-model:\(modelID)-serial:\(serialNumber)"
        }

        return "display-id:\(fallbackDisplayID)"
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

enum MirrorOptimization {
    case fitExternal
    case matchMac
}

enum DesktopClutterState {
    case hidden
    case visible
    case mixed
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
