//
//  ChassisDropDelegate.swift
//  Studio Recall
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ChassisDropDelegate: DropDelegate {
	// Use EITHER a fixed anchor cell (per-cell onDrop) OR a mapper (chassis-level onDrop)
	let fixedCell: (row: Int, col: Int)?
	let indexFor: ((CGPoint) -> (Int, Int))?   // returns (row, col)
	let rowX0: CGFloat
	let rowWidthPts: CGFloat
	
	@Binding var slots: [[DeviceInstance?]]          // rows × cols
	
	@Binding var hoveredIndex: Int?
	@Binding var hoveredValid: Bool
	@Binding var hoveredRange: Range<Int>?
	@Binding var hoveredRows:  Range<Int>?
	
	let library: DeviceLibrary
	let kind: DeviceType
	let onCommit: (() -> Void)?
	
	// MARK: - Payload helpers
	// We already stash the current payload when the drag begins. Use it directly.
	// (Matches DragContext/DragPayload in your project.) :contentReference[oaicite:0]{index=0} :contentReference[oaicite:1]{index=1}
	private var currentPayload: DragPayload? { DragContext.shared.currentPayload }
	
	private func device(for payload: DragPayload) -> Device? {
		library.device(for: payload.deviceId)
	}
	
	// MARK: - Anchor & target math
	private func clampedAnchor(for device: Device, at point: CGPoint) -> (row: Int, col: Int) {
		// Prefer a fixed anchor if provided (per-empty-cell onDrop)
		if let fixed = fixedCell { return fixed }
		
		// Otherwise map the pointer into (row,col)
		let mapped: (Int, Int) = indexFor?(point) ?? (0, 0)
		let row = mapped.0
		let col0 = mapped.1
		
		// Clamp the start col so the span fits
		let span = max(1, device.rackWidth.rawValue)   // 2 for ⅓, 3 for ½ in your 6-col grid
		let maxStart = max(0, RackGrid.columnsPerRow - span)
		let col = min(max(col0, 0), maxStart)
		return (row, col)
	}
	
	private func targetRanges(for device: Device, at point: CGPoint)
	-> (rows: Range<Int>, cols: Range<Int>, anchorCol: Int) {
		
		let spanRows = max(1, device.rackUnits ?? 1)
		let spanCols = max(1, device.rackWidth.rawValue)
		
		// Anchor from current indexer (your clampedAnchor / indexFor etc.)
		let a = clampedAnchor(for: device, at: point)
		
		let maxStartRow = max(0, slots.count - spanRows)
		let maxStartCol = max(0, RackGrid.columnsPerRow - spanCols)
		
		let startRow = min(max(a.row, 0), maxStartRow)
		let startCol = min(max(a.col, 0), maxStartCol)
		
		let rows = startRow ..< (startRow + spanRows)
		let cols = startCol ..< (startCol + spanCols)
		return (rows, cols, startCol)
	}

	@inline(__always)
	private func clampedX(_ x: CGFloat) -> CGFloat {
		max(rowX0, min(x, rowX0 + rowWidthPts - 0.5))
	}
	
	@inline(__always)
	private func outOfBounds(_ x: CGFloat) -> Bool {
		x < rowX0 || x >= rowX0 + rowWidthPts
	}
	
	@inline(__always)
	private func clampedPoint(from info: DropInfo) -> CGPoint {
		var p = info.location
		p.x = clampedX(p.x)
		return p
	}
	
	// MARK: - Availability / placement wrappers
	private func canPlace(_ rr: Range<Int>, _ cc: Range<Int>, ignoring instanceId: UUID?) -> Bool {
		RackPlacement.canPlace(slots: slots, rows: rr, cols: cc, ignoring: instanceId)
	}
	
	// Because DropDelegate methods are nonmutating on a struct, update via a local copy then assign back.
	private func clearOldSpan(_ instanceId: UUID) {
		var tmp = slots
		RackPlacement.clearOldSpan(slots: &tmp, instanceId: instanceId)
		slots = tmp
	}
	private func place(_ instance: DeviceInstance, in rr: Range<Int>, _ cc: Range<Int>) {
		var tmp = slots
		RackPlacement.place(slots: &tmp, instance: instance, rows: rr, cols: cc)
		slots = tmp
	}
	
	// MARK: - DropDelegate
	func validateDrop(info: DropInfo) -> Bool {
		return info.hasItemsConforming(to: [.deviceDragPayload])
	}

	func dropEntered(info: DropInfo) {
		guard let payload = currentPayload, let dev = device(for: payload) else { return }
		// use the clamped point so the initial hover never escapes horizontally
		let p = clampedPoint(from: info)
		let t = targetRanges(for: dev, at: p)
		setHover(anchorCol: t.anchorCol,
				 rows: t.rows,
				 cols: t.cols,
				 valid: canPlace(t.rows, t.cols, ignoring: payload.instanceId))
	}
	
	func dropUpdated(info: DropInfo) -> DropProposal? {
		guard let payload = currentPayload, let dev = device(for: payload) else {
			hoveredIndex = nil; hoveredRange = nil; hoveredRows = nil; hoveredValid = false
			return DropProposal(operation: .forbidden)
		}
		
		let p = clampedPoint(from: info)
		let t = targetRanges(for: dev, at: p)                 // ⬅️ snaps inside
		setHover(anchorCol: t.anchorCol,
				 rows: t.rows,
				 cols: t.cols,
				 valid: canPlace(t.rows, t.cols, ignoring: payload.instanceId))
		
		return DropProposal(operation: hoveredValid ? .move : .forbidden)
	}

	func dropExited(info: DropInfo) {
		setHover(anchorCol: nil, rows: nil, cols: nil, valid: false)
	}
	
	func performDrop(info: DropInfo) -> Bool {
//		defer { hoveredIndex = nil; hoveredRange = nil; hoveredRows = nil; hoveredValid = false }
		setHover(anchorCol: nil, rows: nil, cols: nil, valid: false)
		guard let payload = currentPayload, let dev = device(for: payload) else { return false }
		
		let p = clampedPoint(from: info)
		let t = targetRanges(for: dev, at: p)                 // ⬅️ snaps inside
		guard canPlace(t.rows, t.cols, ignoring: payload.instanceId) else { return false }
		
		if let movingId = payload.instanceId {
			// Find the existing instance in the grid; if we can't, abort the move.
			guard let inst = slots.flatMap({ $0 }).compactMap({ $0 }).first(where: { $0.id == movingId }) else {
				return false
			}
			clearOldSpan(movingId)
			place(inst, in: t.rows, t.cols)
		} else {
			let inst = library.createInstance(of: dev)
			place(inst, in: t.rows, t.cols)
		}
		onCommit?()
		DragContext.shared.endDrag()
		return true
	}
	
	@inline(__always)
	private func setHover(anchorCol: Int?, rows: Range<Int>?, cols: Range<Int>?, valid: Bool) {
		if hoveredIndex != anchorCol { hoveredIndex = anchorCol }
		if hoveredRows  != rows      { hoveredRows  = rows }
		if hoveredRange != cols      { hoveredRange = cols }
		if hoveredValid != valid     { hoveredValid = valid }
	}

}
