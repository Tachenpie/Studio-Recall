//
//  RackPlacement.swift
//  Studio Recall
//
//  Created by True Jackie on 9/18/25.
//


import Foundation

enum RackPlacement {
    static func isValidType(_ device: Device, kind: DeviceType) -> Bool {
        device.type == kind
    }

    static func span(for device: Device) -> (rows: Int, cols: Int) {
        (max(1, device.rackUnits ?? 1), max(1, device.rackWidth.rawValue))
    }

    /// Compute a clamped placement rect using a TOP-LEFT anchor.
    /// For full-width devices, columns are always 0 ..< RackGrid.columnsPerRow.
    static func rect(for device: Device,
                     droppingAt raw: (row: Int, col: Int),
                     gridRows: Int,
                     gridCols: Int) -> (rows: Range<Int>, cols: Range<Int>, anchor: (row: Int, col: Int)) {

        let rowsNeeded = max(1, device.rackUnits ?? 1)
        let colsNeeded = max(1, device.rackWidth.rawValue)

        // Clamp top row so the rect never overflows downward.
        let maxTopRow = max(0, gridRows - rowsNeeded)
        let r0 = max(0, min(raw.row, maxTopRow))

        // Left column: full width ignores pointer X, partial clamps left edge.
        let c0: Int = (device.rackWidth == .full)
            ? 0
            : max(0, min(raw.col, max(0, gridCols - colsNeeded)))

        let rr = r0 ..< (r0 + rowsNeeded)
        let cc = (device.rackWidth == .full)
            ? (0 ..< gridCols)
            : (c0 ..< (c0 + colsNeeded))

        return (rr, cc, (r0, c0))
    }

    static func canPlace(slots: [[DeviceInstance?]],
                         rows rr: Range<Int>,
                         cols cc: Range<Int>,
                         ignoring id: UUID?) -> Bool {
        for r in rr { for c in cc {
            if let occ = slots[r][c], occ.id != id { return false }
        }}
        return true
    }

    static func clearOldSpan(slots: inout [[DeviceInstance?]], instanceId: UUID) {
        for r in slots.indices {
            for c in 0..<RackGrid.columnsPerRow {
                if slots[r][c]?.id == instanceId { slots[r][c] = nil }
            }
        }
    }

    static func place(slots: inout [[DeviceInstance?]],
                      instance: DeviceInstance,
                      rows rr: Range<Int>,
                      cols cc: Range<Int>) {
        for r in rr { for c in cc { slots[r][c] = instance } }
    }
}
