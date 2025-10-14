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
	@Environment(\.isInteracting) private var isInteracting
	@Environment(\.collisionRects) private var collisionRects

	@ObservedObject private var dragContext = DragContext.shared
	
	@State private var hoveredIndex: Int? = nil
	@State private var hoveredValid: Bool = false
	@State private var hoveredRange: Range<Int>? = nil
	@State private var hoveredRows: Range<Int>? = nil   // NEW: vertical span
	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editUnits: Int = 0
	@State private var editName: String = ""
	@State private var rowLayoutsCache: [[SlotLayout]] = []
	
	var onDelete: (() -> Void)? = nil
	
	private let rowSpacing: CGFloat = 1      // between U rows in the VStack
	private let facePadding: CGFloat = 16    // .padding() around the chassis face

	// MARK: - Collision Resistance

	/// Adjusts a proposed position to avoid collisions with other racks/chassis
	private func collisionResistantPosition(_ proposed: CGPoint, selfRect: CGRect) -> CGPoint {
		let pushDistance: CGFloat = 8 // minimum separation in world coordinates

		// Filter out self from collision rects
		let others = collisionRects.filter { $0.id != rack.id }

		var adjusted = proposed
		let testRect = CGRect(origin: proposed, size: selfRect.size)

		// Check each collision rect and push away if overlapping
		for other in others {
			if testRect.intersects(other.rect) {
				// Calculate overlap and push direction
				let overlapX = min(testRect.maxX, other.rect.maxX) - max(testRect.minX, other.rect.minX)
				let overlapY = min(testRect.maxY, other.rect.maxY) - max(testRect.minY, other.rect.minY)

				// Push in direction of least overlap
				if overlapX < overlapY {
					// Push horizontally
					if testRect.midX < other.rect.midX {
						adjusted.x -= (overlapX + pushDistance)
					} else {
						adjusted.x += (overlapX + pushDistance)
					}
				} else {
					// Push vertically
					if testRect.midY < other.rect.midY {
						adjusted.y -= (overlapY + pushDistance)
					} else {
						adjusted.y += (overlapY + pushDistance)
					}
				}
			}
		}

		return adjusted
	}

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
				onDrag: { screenDelta, _ in  // Ignore screen location for racks (no preview needed)
					let origin = dragStart ?? rack.position
					let z = max(canvasZoom, 0.0001)
					let worldDelta = CGSize(width: screenDelta.width  / z,
											height: screenDelta.height / z)
					let proposedPos = CGPoint(x: origin.x + worldDelta.width,
											  y: origin.y + worldDelta.height)

					// Apply collision resistance
					let selfRect = CGRect(origin: rack.position, size: CGSize(width: faceW, height: faceH))
					rack.position = collisionResistantPosition(proposedPos, selfRect: selfRect)
				},
				onEnded: { dragStart = nil },
				onEditRequested: {
					editUnits = max(1, rack.rows)
					editName = rack.name ?? ""
					showEdit = true
				},
				onClearRequested: { clearAllRackDevices() },
				onDeleteRequested: { onDelete?() },
				newLabelAnchor: .rack(rack.id),
				defaultLabelOffset: CGPoint(x: 32, y: 28)
			)
			.frame(width: faceW)
			.zIndex(2)
			
			// --- 2) CHASSIS FACE (fixed size; no GeometryReader) ---
			ZStack(alignment: .topLeading) {
				
				let showDropGrid = (dragContext.currentPayload != nil)
				
				// A) GRID (visual only, no per-cell drop targets)
				if showDropGrid {
					VStack(spacing: rowSpacing) {
						ForEach(0..<rack.rows, id: \.self) { r in
							HStack(spacing: 0) {
								ForEach(0..<RackGrid.columnsPerRow, id: \.self) { c in
									let empty = (rack.slots[r][c] == nil)
									Rectangle()
										.fill(empty ? Color.white.opacity(0.06) : .clear)
										.overlay(
											Group {
												if !isInteracting {
													Rectangle().stroke(
														Color.secondary.opacity(0.6),
														style: StrokeStyle(lineWidth: 1, dash: [4])
													)
												}
											}
										)
										.allowsHitTesting(false) // ← critical
								}
							}
							.frame(height: rowH)
						}
					}
					.frame(width: innerW)
					.padding(facePadding)
				}


				if showDropGrid, let rows = hoveredRows, let cols = hoveredRange {
					// Position/size in points (include row spacing)
					let x = facePadding + CGFloat(cols.lowerBound) * colW
					let w = CGFloat(cols.count) * colW
					
					let y = facePadding
					+ CGFloat(rows.lowerBound) * (rowH + rowSpacing)               // ← include spacing
					let h = CGFloat(rows.count) * rowH
					+ CGFloat(max(0, rows.count - 1)) * rowSpacing                 // ← include spacing
					
					Rectangle()
						.fill(hoveredValid
							  ? Color.black.opacity(0.5)                                  // allowed
							  : Color(NSColor.unemphasizedSelectedTextBackgroundColor))  // disallowed
						.frame(width: w, height: h)
						.position(x: x + w/2, y: y + h/2)
						.allowsHitTesting(false)
						.zIndex(5)
						.transaction { $0.animation = nil }
//						.drawingGroup(opaque: false)
				}
				
				// B) DEVICES — inch-accurate overlay
				ForEach(rack.slots.indices, id: \.self) { row in
					let rowLayouts = (row < rowLayoutsCache.count) ? rowLayoutsCache[row] : [] //buildRowLayout(row: row, ppi: ppi)
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
							hoveredValid: $hoveredValid,
							hoveredRange: $hoveredRange,
							hoveredRows:  $hoveredRows
						)
						.frame(width: L.totalW, height: L.hPts, alignment: .topLeading)
						.position(x: xLeft + L.totalW / 2, y: yTop + L.hPts / 2)
					}
				}
				
				// LABELS
				if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
					let session = $sessionManager.sessions[i]
					LabelCanvas(
						labels: session.labels,
						anchor: .rack(rack.id),
						parentOrigin: CGPoint(x: facePadding, y: facePadding)
					)
					.allowsHitTesting(true)
				}
			}
			.modifier(ConditionalDrawingGroup(active: isInteracting))
			.shadow(radius: isInteracting ? 0 : 16)
			.contentShape(Rectangle())
			.frame(width: faceW, height: faceH)
			.background(Color.black.opacity(0.8))
			.cornerRadius(8)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.85), lineWidth: 1))
			.allowsHitTesting(true)
			.background {
				// Keep this in the same coordinate space as the ZStack
				Color.clear.onDrop(
					of: [UTType.deviceDragPayload],
					delegate: ChassisDropDelegate(
						fixedCell: nil,
						indexFor: { pt in
							// Inner face bounds (same coord space as ZStack top-left)
							let xL = facePadding
							let xR = facePadding + innerW
							let innerH = faceH - 2 * facePadding
							let yT = facePadding
							let yB = facePadding + innerH

							// Clamp pointer to the inner face
							let p = CGPoint(
								x: max(xL, min(pt.x, xR - 0.5)),
								y: max(yT, min(pt.y, yB - 0.5))
							)

							// Columns: simple width division
							let c = Int(floor((p.x - xL) / colW))

							// Rows: use step = rowH + rowSpacing so the gaps map to the row ABOVE
							let step = rowH + rowSpacing
							let r = Int(floor((p.y - yT) / step))

							// Clamp to valid indices
							let rr = max(0, min(r, rack.rows - 1))
							let cc = max(0, min(c, RackGrid.columnsPerRow - 1))
							return (rr, cc)
						},
						rowX0: facePadding,
						rowWidthPts: innerW,
						slots: $rack.slots,
						hoveredIndex: $hoveredIndex,
						hoveredValid: $hoveredValid,
						hoveredRange: $hoveredRange,
						hoveredRows:  $hoveredRows,
						library: library,
						kind: .rack,
						session: sessionManager.currentSession,
						sessionManager: sessionManager,
						onCommit: {
							sessionManager.saveSessions()
							DragContext.shared.endDrag()
						}
					)
				)
			}
//			.allowsHitTesting(true)
//			.onDrop(
//				of: [UTType.deviceDragPayload],
//				delegate: ChassisDropDelegate(
//					fixedCell: nil,
//					indexFor: { pt in
//						// Clamp inside the inner face (same coord space as ZStack)
//						let xL = facePadding
//						let xR = facePadding + innerW
//						let innerH = faceH - 2 * facePadding
//						let yT = facePadding
//						let yB = facePadding + innerH
//						
//						let clamped = CGPoint(
//							x: max(xL, min(pt.x, xR - 0.5)),
//							y: max(yT, min(pt.y, yB - 0.5))
//						)
//						
//						// --- Column from simple width ---
//						var (r, c0) = cellIndex(for: clamped, colW: colW, rowH: rowH) // we’ll overwrite r next
//						
//						// --- Row using step = rowH + rowSpacing (so gaps map to the row above) ---
//						let stepY = rowH + rowSpacing
//						let relY  = clamped.y - yT
//						var rFromSpacing = Int(floor(relY / stepY))        // map spacing to the row above
//						
//						// Snap start so the full span fits (right-most / bottom-most)
//						if let payload = DragContext.shared.currentPayload,
//						   let dev = library.device(for: payload.deviceId) {
//							
//							let spanCols = max(1, dev.rackWidth.rawValue)
//							let spanRows = max(1, dev.rackUnits ?? 1)
//							
//							let maxStartCol = RackGrid.columnsPerRow - spanCols
//							let maxStartRow = rack.rows - spanRows
//							
//							c0 = min(max(c0, 0), maxStartCol)
//							rFromSpacing = min(max(rFromSpacing, 0), maxStartRow)
//						}
//						
//						// replace row computed by cellIndex with spacing-aware one
//						r = rFromSpacing
//						return (r, c0)
//					},
//					rowX0: facePadding,
//					rowWidthPts: innerW,
//					slots: $rack.slots,
//					hoveredIndex: $hoveredIndex,
//					hoveredValid: $hoveredValid,
//					hoveredRange: $hoveredRange,
//					hoveredRows:  $hoveredRows,
//					library: library,
//					kind: .rack,
//					onCommit: {
//						sessionManager.saveSessions()
//						DragContext.shared.endDrag()
//					}
//				)
//			)
			.zIndex(1)
			.background(
				GeometryReader { proxy in
					Color.clear
						.anchorPreference(key: RackRectsKey.self, value: .bounds) { bounds in
							[RackRect(id: rack.id, frame: proxy[bounds])]
						}
				}
			)
		}
		.sheet(isPresented: $showEdit) { editSheet }
		.onAppear { rebuildRowLayouts(ppi: settings.pointsPerInch) }
		.onChange(of: rack.slots) { _, _ in rebuildRowLayouts(ppi: settings.pointsPerInch) }
		.onChange(of: rack.rows)  { _, _ in rebuildRowLayouts(ppi: settings.pointsPerInch) }
		.onChange(of: settings.pointsPerInch) { _, ppi in rebuildRowLayouts(ppi: ppi) }
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
	
	private func rebuildRowLayouts(ppi: CGFloat) {
		rowLayoutsCache = (0..<rack.rows).map { r in buildRowLayout(row: r, ppi: ppi) }
	}


	// MARK: - Per-row prelayout (inch-accurate)
	private func buildRowLayout(row: Int, ppi: CGFloat) -> [SlotLayout] {
		let rowPts  = 19.0 * ppi
		let colPts  = rowPts / CGFloat(RackGrid.columnsPerRow)
		let wingPts = DeviceMetrics.wingWidth * ppi
		let eps: CGFloat = 0.25
		
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
		
		var seamBasePts = internalUnits.map { CGFloat($0) * colPts }   // one per internal seam
		
		// --- faces + wings only if actually touching rack edge (pad ~ 0) ---
		var faces:  [CGFloat] = []
		var wingsL: [CGFloat] = []
		var wingsR: [CGFloat] = []
		for i in items.indices {
			let dev = items[i].dev
			faces.append(DeviceMetrics.bodyInches(for: dev.rackWidth) * ppi)
			
			let isFirst = (i == 0), isLast = (i == items.count - 1)
			let wantsLeftWing  = (dev.rackWidth != .full && isFirst && P_leftBase  <= eps)
			let wantsRightWing = (dev.rackWidth != .full && isLast  && P_rightBase <= eps)
			
			wingsL.append(wantsLeftWing  ? wingPts : 0)
			wingsR.append(wantsRightWing ? wingPts : 0)
		}
		
		// --- compute uniform extra seam width (edges never get any) ---
		var used: CGFloat = P_leftBase + P_rightBase
		for v in seamBasePts { used += v }
		for i in items.indices { used += faces[i] + wingsL[i] + wingsR[i] }
		
		let seamCount = max(0, items.count - 1)
		let extraPerSeam = seamCount > 0 ? max(0, (rowPts - used) / CGFloat(seamCount)) : 0
		if extraPerSeam > 0 {
			for i in seamBasePts.indices { seamBasePts[i] += extraPerSeam }
		}
		
		// --- build final layouts ---
		var result: [SlotLayout] = []
		var x: CGFloat = 0   // ← keep the leading gap as position, not as a rail
		
		for i in items.indices {
			// internal seams split 50/50
			let leftInternal  = (i == 0) ? 0 : seamBasePts[i - 1] * 0.5
			let rightInternal = (i == items.count - 1) ? 0 : seamBasePts[i] * 0.5
			
			let isFirst = (i == 0)
			let isLast  = (i == items.count - 1)
			let hasLeftWing  = wingsL[i] > 0
			let hasRightWing = wingsR[i] > 0
			
			// Edge pads become rails on the single adjacent device,
			// BUT never on a side that has a wing.
			let lRailRaw = leftInternal  + (isFirst && !hasLeftWing  ? P_leftBase  : 0)
			let rRailRaw = rightInternal + (isLast  && !hasRightWing ? P_rightBase : 0)
			
			let lRail = (lRailRaw <= eps) ? 0 : lRailRaw
			let rRail = (rRailRaw <= eps) ? 0 : rRailRaw
			
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
		
		// tiny FP guard: nudge last box width only (never mutate rails)
		let usedNow = result.reduce(0) { $0 + $1.totalW }   // ← no + P_leftBase here
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
				rRail: L.rRail,
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

			TextField("Rack Name (optional)", text: $editName)
				.textFieldStyle(.roundedBorder)

			Stepper("Rack Units: \(rack.rows)", value: Binding(
				get: { rack.rows },
				set: { applyRackResize(to: $0) }
			), in: 1...200)

			HStack {
				Spacer()
				Button("Cancel") {
					showEdit = false
				}
				Button("Save") {
					let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
					rack.name = trimmedName.isEmpty ? nil : trimmedName
					sessionManager.saveSessions()
					showEdit = false
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 320)
	}
	
	private func applyRackResize(to newRows: Int) {
		guard newRows != rack.rows else { return }

		// Racks grow/shrink from the bottom only
		// Since slots are stored top-to-bottom (index 0 = top), we need to:
		// - When shrinking: remove from the END (bottom rows)
		// - When growing: append to the END (add bottom rows)
		// This keeps the top position stable

		if newRows < rack.rows {
			// Shrinking: remove bottom rows
			// Clear any devices that span into the removed rows
			let keepRows = newRows
			for r in 0..<min(keepRows, rack.slots.count) {
				for c in 0..<RackGrid.columnsPerRow {
					if let inst = rack.slots[r][c],
					   let dev = library.device(for: inst.deviceID) {
						let spanRows = max(1, dev.rackUnits ?? 1)
						// If this device extends past the new size, remove it
						if r + spanRows > keepRows {
							// Clear entire span
							for rr in r..<min(r + spanRows, rack.slots.count) {
								for cc in 0..<RackGrid.columnsPerRow {
									if rack.slots[rr][cc]?.id == inst.id {
										rack.slots[rr][cc] = nil
									}
								}
							}
						}
					}
				}
			}
			rack.slots = Array(rack.slots.prefix(newRows))
		} else {
			// Growing: add empty rows at the bottom
			let extra = Array(
				repeating: Array<DeviceInstance?>(repeating: nil, count: RackGrid.columnsPerRow),
				count: newRows - rack.rows
			)
			rack.slots.append(contentsOf: extra)
		}

		rack.rows = newRows
		sessionManager.saveSessions()
	}
}
