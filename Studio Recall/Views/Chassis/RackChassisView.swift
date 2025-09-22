//
//  RackChassisView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import UniformTypeIdentifiers
import SwiftUI

struct RackChassisView: View {
	@Binding var rack: Rack
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var sessionManager: SessionManager
	
	@Environment(\.canvasZoom) private var canvasZoom
	
	@State private var hoveredIndex: Int? = nil
	@State private var hoveredValid: Bool = false
	@State private var hoveredRange: Range<Int>? = nil
	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editUnits: Int = 0
	
	var onDelete: (() -> Void)? = nil
	
	private let rowSpacing: CGFloat = 1      // between U rows in the VStack
	private let facePadding: CGFloat = 16    // .padding() around the chassis face
	
	var body: some View {
		// Pull common numbers out so the builder stays simple.
		let ppi      = settings.pointsPerInch
		let oneU     = DeviceMetrics.rackSize(units: 1, scale: ppi)
		let innerW   = oneU.width
		let rowH     = oneU.height
		let faceW    = innerW + facePadding * 2
		let colW     = innerW / CGFloat(RackGrid.columnsPerRow) // for drop grid only
		let faceH    = facePadding * 2
		+ CGFloat(rack.rows) * rowH
		+ rowSpacing * CGFloat(max(0, rack.rows - 1))
		
		VStack(spacing: 0) {
			// 1) TABLETOP (not a drop target)
			DragStrip(
				title: (rack.name?.isEmpty == false ? rack.name : "Rack"),
				onBegan: { if dragStart == nil { dragStart = rack.position } },
				onDrag: { screenDelta in
					let origin = dragStart ?? rack.position
					let z = max(canvasZoom, 0.0001)
					let worldDelta = CGSize(width: screenDelta.width  / z,
											height: screenDelta.height / z)
					rack.position = CGPoint(x: origin.x + worldDelta.width,
											y: origin.y + worldDelta.height)
				},
				onEnded: { dragStart = nil },
				onEditRequested: {
					editUnits = max(1, rack.rows)
					showEdit = true
				},
				onClearRequested: { clearAllRackDevices() },
				onDeleteRequested: { onDelete?() }
			)
			.frame(width: faceW)
			.zIndex(2)
			
			// --- 2) CHASSIS FACE (fixed size; no GeometryReader) ---
			ZStack(alignment: .topLeading) {
				// A) GRID (empty-cell drop targets)
				VStack(spacing: rowSpacing) {
					ForEach(0..<rack.rows, id: \.self) { r in
						HStack(spacing: 0) {
							ForEach(0..<RackGrid.columnsPerRow, id: \.self) { c in
								if rack.slots[r][c] == nil {
									Rectangle()
										.fill(Color.white.opacity(0.06))
										.overlay(
											Rectangle().stroke(Color.secondary.opacity(0.6),
															   style: StrokeStyle(lineWidth: 1, dash: [4]))
										)
										.contentShape(Rectangle())
										.onDrop(of: [UTType.deviceDragPayload],
												delegate: ChassisDropDelegate(
													fixedCell: (r, c),
													indexFor: nil,
													rowX0: -.infinity,
													rowWidthPts: .infinity,
													slots: $rack.slots,
													hoveredIndex: $hoveredIndex,
													hoveredValid: $hoveredValid,
													hoveredRange: $hoveredRange,
													library: library,
													kind: .rack,
													onCommit: { sessionManager.saveSessions() }
												))
								} else {
									Color.clear.allowsHitTesting(false)
								}
							}
						}
						.frame(height: rowH)
					}
				}
				.frame(width: innerW)
				.padding(facePadding)
				
				// B) DEVICES — inch-accurate overlay
				ForEach(rack.slots.indices, id: \.self) { row in
					let rowLayouts = buildRowLayout(row: row, ppi: ppi)
					let yTop = facePadding + CGFloat(row) * (rowH + rowSpacing)
					
					ForEach(rowLayouts, id: \.instance.id) { L in
						let xLeft = facePadding + L.xPts
						let pre = SlotPrelayout(
							faceWidthPts: L.faceW,
							totalWidthPts: L.totalW,
							leftWingPts: L.lWing,
							rightWingPts: L.rWing,
							leftRailPts: L.lRail,
							rightRailPts: L.rRail,
							heightPts: L.hPts,
							externalLeft: L.externalLeft,
							externalRight: L.externalRight
						)
						
						RackChassisSlotView(
							row: row,
							col: 0,                // unused in prelayout path
							instance: L.instance,  // pass the instance directly
							prelayout: pre,
							slots: $rack.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid
						)
						.frame(width: L.totalW, height: L.hPts, alignment: .topLeading)
						.position(x: xLeft + L.totalW / 2, y: yTop + L.hPts / 2)
					}
				}
			}
			.contentShape(Rectangle())
			.frame(width: faceW, height: faceH)
			.background(Color.black.opacity(0.8))
			.cornerRadius(8)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.85), lineWidth: 1))
			.allowsHitTesting(true)
			.onDrop(
				of: [UTType.deviceDragPayload, .item, .data, .plainText, .utf8PlainText],
				delegate: ChassisDropDelegate(
					fixedCell: nil,
					indexFor: { pt in
						// Clamp to the inner chassis band (same coords as the ZStack)
						let xL = facePadding
						let xR = facePadding + innerW
						let innerH = faceH - 2 * facePadding        // total drawable height inside padding
						let yT = facePadding
						let yB = facePadding + innerH
						
						let clamped = CGPoint(
							x: max(xL, min(pt.x, xR - 0.5)),
							y: max(yT, min(pt.y, yB - 0.5))
						)
						
						// Map to grid
						var (r, c0) = cellIndex(for: clamped, colW: colW, rowH: rowH)
						
						// Snap start so the full span fits (right-most / bottom-most)
						if let payload = DragContext.shared.currentPayload,
						   let dev = library.device(for: payload.deviceId) {
							
							let spanCols = max(1, dev.rackWidth.rawValue)
							let spanRows = max(1, dev.rackUnits ?? 1)
							
							let maxStartCol = RackGrid.columnsPerRow - spanCols
							let maxStartRow = rack.rows - spanRows
							
							c0 = min(max(c0, 0), maxStartCol)
							r  = min(max(r, 0), maxStartRow)
						}
						return (r, c0)
					},
					rowX0: facePadding,
					rowWidthPts: innerW,
					slots: $rack.slots,
					hoveredIndex: $hoveredIndex,
					hoveredValid: $hoveredValid,
					hoveredRange: $hoveredRange,
					library: library,
					kind: .rack,
					onCommit: {
						sessionManager.saveSessions()
						DragContext.shared.endDrag()
					}
				)
			)
			.zIndex(1)
		}
		.sheet(isPresented: $showEdit) { editSheet }
	}
	
	// MARK: - Per-row prelayout (inch-accurate)
	private struct SlotLayout {
		let instance: DeviceInstance
		let xPts: CGFloat
		let faceW: CGFloat
		let totalW: CGFloat
		let lWing: CGFloat
		let rWing: CGFloat
		let lRail: CGFloat
		let rRail: CGFloat
		let hPts: CGFloat
		let externalLeft: Bool
		let externalRight: Bool
	}

	// Inch-accurate, anchor-stable row layout.
	// - Base pads: every boundary gets grid-gap points (19″/6 * empty columns).
	// - Leftover: split uniformly across internal seams; each neighbor gets half as rails.
	// - External wings only on the far row edges for partial-width devices.
	private func buildRowLayout(row: Int, ppi: CGFloat) -> [SlotLayout] {
		let rowPts  = 19.0 * ppi
		let colPts  = rowPts / CGFloat(RackGrid.columnsPerRow)
		let wingPts = DeviceMetrics.wingWidth * ppi
		
		func isTopAnchor(_ inst: DeviceInstance) -> Bool {
			guard row > 0 else { return true }
			return !rack.slots[row - 1].contains(where: { $0?.id == inst.id })
		}
		
		struct Item { let inst: DeviceInstance; let dev: Device; let col: Int; let spanCols: Int }
		var items: [Item] = []
		var seen = Set<UUID>()
		for c in rack.slots[row].indices {
			if let inst = rack.slots[row][c],
			   isTopAnchor(inst),
			   !seen.contains(inst.id),
			   let dev = library.device(for: inst.deviceID) {
				items.append(.init(inst: inst, dev: dev, col: c, spanCols: max(1, dev.rackWidth.rawValue)))
				seen.insert(inst.id)
			}
		}
		guard !items.isEmpty else { return [] }
		items.sort { $0.col < $1.col }
		
		// --- base pads from empty grid columns (edges + internal) ---
		let leadingUnits = max(0, items.first!.col)
		var internalUnits: [Int] = []
		for i in 0..<(items.count - 1) {
			let leftEnd = items[i].col + items[i].spanCols
			let rightStart = items[i+1].col
			internalUnits.append(max(0, rightStart - leftEnd))
		}
		let trailingUnits = max(0, RackGrid.columnsPerRow - (items.last!.col + items.last!.spanCols))
		
		let P_leftBase  = CGFloat(leadingUnits)  * colPts
		let P_rightBase = CGFloat(trailingUnits) * colPts
		var seamBasePts: [CGFloat] = internalUnits.map { CGFloat($0) * colPts } // one per internal boundary
		
		// --- faces + external wings (partials only at far edges) ---
		var faces: [CGFloat] = []
		var wingsL: [CGFloat] = []
		var wingsR: [CGFloat] = []
		for i in items.indices {
			let dev = items[i].dev
			faces.append(DeviceMetrics.bodyInches(for: dev.rackWidth) * ppi) // 19 / 8.5 / 5.5
			let isFirst = (i == 0), isLast = (i == items.count - 1)
			wingsL.append((dev.rackWidth != .full && isFirst) ? wingPts : 0)
			wingsR.append((dev.rackWidth != .full && isLast)  ? wingPts : 0)
		}
		
		var used: CGFloat = P_leftBase + P_rightBase
		for v in seamBasePts { used += v }
		for i in items.indices { used += faces[i] + wingsL[i] + wingsR[i] }
		
		// --- leftover becomes UNIFORM extra seam width (edges never get any) ---
		let seamCount = max(0, items.count - 1)
		let extraPerSeam = seamCount > 0 ? max(0, (rowPts - used) / CGFloat(seamCount)) : 0
		if extraPerSeam > 0 {
			for i in seamBasePts.indices { seamBasePts[i] += extraPerSeam }
		}
		
		// --- build final layouts ---
		var result: [SlotLayout] = []
		var x: CGFloat = P_leftBase
		for i in items.indices {
			let lRail = (i == 0) ? 0 : seamBasePts[i - 1] / 2
			let rRail = (i == items.count - 1) ? 0 : seamBasePts[i] / 2
			let total = faces[i] + wingsL[i] + wingsR[i] + lRail + rRail
			let h     = DeviceMetrics.rackSize(units: items[i].dev.rackUnits ?? 1, scale: ppi).height
			
			result.append(SlotLayout(
				instance: items[i].inst,
				xPts: x,
				faceW: faces[i],
				totalW: total,
				lWing: wingsL[i],
				rWing: wingsR[i],
				lRail: lRail,
				rRail: rRail,
				hPts: h,
				externalLeft: (i == 0),
				externalRight: (i == items.count - 1)
			))
			x += total
		}
		
		// small FP guard: nudge the last right rail only (faces don't move)
		let usedNow = P_leftBase + result.reduce(0) { $0 + $1.totalW } + P_rightBase
		let err = rowPts - usedNow
		if abs(err) > 0.75, let i = result.indices.last {
			let L = result[i]
			result[i] = SlotLayout(
				instance: L.instance,
				xPts: L.xPts,
				faceW: L.faceW,
				totalW: L.totalW + err,
				lWing: L.lWing,
				rWing: L.rWing,
				lRail: L.lRail,
				rRail: L.rRail + err,
				hPts: L.hPts,
				externalLeft: L.externalLeft,
				externalRight: L.externalRight
			)
		}
		return result
	}


	// MARK: - Drop grid helpers (unchanged)
	private func cellIndex(for pt: CGPoint, colW: CGFloat, rowH: CGFloat) -> (row: Int, col: Int) {
		let faceHeight = facePadding * 2
		+ CGFloat(rack.rows) * rowH
		+ rowSpacing * CGFloat(max(0, rack.rows - 1))
		
		let xFromLeft = max(0, pt.x - facePadding)
		let yFromTop  = max(0, faceHeight - pt.y - facePadding)
		
		let col = min(RackGrid.columnsPerRow - 1, max(0, Int(floor(xFromLeft / colW))))
		let row = min(rack.rows - 1,          max(0, Int(floor(yFromTop  / (rowH + rowSpacing)))))
		return (row, col)
	}
	
	private func clearAllRackDevices() {
		for r in rack.slots.indices {
			for c in 0..<RackGrid.columnsPerRow {
				rack.slots[r][c] = nil
			}
		}
	}
	
	// MARK: - Edit sheet
	@ViewBuilder
	private var editSheet: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit Rack").font(.headline)
			Stepper("Rack Units: \(rack.rows)", value: Binding(
				get: { rack.rows },
				set: { applyRackResize(to: $0) }
			), in: 1...200)
			HStack {
				Spacer()
				Button("Close") { showEdit = false }
			}
		}
		.padding(20)
		.frame(width: 320)
	}
	
	private func applyRackResize(to newRows: Int) {
		guard newRows != rack.rows else { return }
		if newRows < rack.rows {
			rack.slots = Array(rack.slots.prefix(newRows))
		} else {
			let extra = Array(
				repeating: Array<DeviceInstance?>(repeating: nil, count: RackGrid.columnsPerRow),
				count: newRows - rack.rows
			)
			rack.slots.append(contentsOf: extra)
		}
		rack.rows = newRows
	}
}
