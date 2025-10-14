//
//  Series500ChassisView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct Series500ChassisView: View {
    @Binding var chassis: Series500Chassis
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var sessionManager: SessionManager
	
	@Environment(\.canvasZoom) private var canvasZoom
	@Environment(\.isInteracting) private var isInteracting
	@Environment(\.collisionRects) private var collisionRects

    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editSlots: Int = 0
	@State private var editName: String = ""
	@State private var pendingMountRackID: UUID? = nil
	@State private var showDragPreview: Bool = false
	@State private var dragPreviewScreenLocation: CGPoint = .zero

	var onDelete: (() -> Void)? = nil

	private let facePadding: CGFloat = 4

	// MARK: - Collision & Mounting

	/// Result of collision detection
	enum CollisionResult {
		case normal(CGPoint)                    // Normal position with collision resistance
		case mountingOpportunity(rackID: UUID)  // Mount into this rack
	}

	/// Calculate which row to mount at based on chassis Y position relative to rack
	private func calculateMountingRow(for rackID: UUID) -> Int {
		// Find the rack in collision rects
		guard let rackRect = collisionRects.first(where: { $0.id == rackID && $0.isRack }) else {
			return 0
		}

		// Find the rack in session to get row count
		guard let rack = sessionManager.currentSession?.racks.first(where: { $0.id == rackID }) else {
			return 0
		}

		// Calculate position relative to rack interior
		let facePadding: CGFloat = 16
		let dragStripHeight: CGFloat = 32
		let ppi = settings.pointsPerInch
		let rowHeight = DeviceMetrics.rackSize(units: 1, scale: ppi).height
		let rowSpacing: CGFloat = 1

		// Chassis center Y position - need to convert to TOP of chassis for row calculation
		let chassisCenterY = chassis.position.y
		let chassisHeight = 3 * rowHeight + 2 * rowSpacing  // 3U span
		let chassisTopY = chassisCenterY - chassisHeight / 2

		// Rack interior starts after drag strip and padding
		let rackInteriorStartY = rackRect.rect.minY + dragStripHeight + facePadding

		// Relative Y within rack interior (from top of chassis)
		let relativeY = chassisTopY - rackInteriorStartY

		// Calculate row index
		let rowIndex = Int(floor(relativeY / (rowHeight + rowSpacing)))

		// Clamp to valid range (must have room for 3U)
		let maxStartRow = max(0, rack.rows - 3)
		return max(0, min(rowIndex, maxStartRow))
	}

	/// Adjusts a proposed position to avoid collisions with other racks/chassis
	/// Special case: if near a rack with 3U space, returns mounting opportunity
	private func checkCollision(_ proposed: CGPoint, selfRect: CGRect) -> CollisionResult {
		let pushDistance: CGFloat = 8 // minimum separation in world coordinates

		// Filter out self from collision rects
		let others = collisionRects.filter { $0.id != chassis.id }

		var adjusted = proposed
		let testRect = CGRect(origin: proposed, size: selfRect.size)

		// Check for rack mounting opportunity (3U = ~5.25 inches of height)
		let mountingThreshold: CGFloat = 50 // proximity threshold for mounting detection

		for other in others {
			if other.isRack && testRect.intersects(other.rect) {
				// Check if we're overlapping this rack significantly
				let overlapX = min(testRect.maxX, other.rect.maxX) - max(testRect.minX, other.rect.minX)
				let overlapY = min(testRect.maxY, other.rect.maxY) - max(testRect.minY, other.rect.minY)

				// If overlap is substantial, this is a mounting opportunity
				if overlapX > mountingThreshold && overlapY > mountingThreshold {
					return .mountingOpportunity(rackID: other.id)
				}
			}
		}

		// Normal collision resistance for non-rack objects or distant racks
		for other in others {
			if testRect.intersects(other.rect) && !other.isRack {
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

		return .normal(adjusted)
	}

	var body: some View {
		let spacing: CGFloat = 4
		let module = DeviceMetrics.moduleSize(units: 1, scale: settings.pointsPerInch)
		let slots = chassis.slots.count
		let faceWidth = CGFloat(slots) * module.width + CGFloat(max(0, slots - 1)) * spacing
		
		VStack(spacing: 0) {
			// 1) TABLETOP (not a drop target) - only show when NOT mounted
			if !chassis.isMounted {
				DragStrip(
					title: (chassis.name?.isEmpty == false ? chassis.name : "500 Series"),
					onBegan: {
						if dragStart == nil {
							dragStart = chassis.position
							pendingMountRackID = nil
							showDragPreview = true

							// If mounted, unmount immediately when drag begins
							if chassis.isMounted {
								sessionManager.unmount500Series(chassisID: chassis.id)
							}
						}
					},
				onDrag: { screenDelta, screenLocation in
					let origin = dragStart ?? chassis.position
					let z = max(canvasZoom, 0.0001)                   // @Environment(\.canvasZoom)
					let worldDelta = CGSize(width: screenDelta.width  / z,
											height: screenDelta.height / z)
					let proposedPos = CGPoint(x: origin.x + worldDelta.width,
											  y: origin.y + worldDelta.height)

					// Update preview location to follow cursor
					dragPreviewScreenLocation = screenLocation

					// Only check for mounting if NOT currently mounted
					if chassis.isMounted {
						// Just move freely while mounted (already unmounted in onBegan)
						chassis.position = proposedPos
					} else {
						// Apply collision resistance and check for mounting opportunity
						let chassisHeight = module.height + 2 * facePadding
						let selfRect = CGRect(origin: chassis.position,
											  size: CGSize(width: faceWidth + 2 * facePadding, height: chassisHeight))

						let result = checkCollision(proposedPos, selfRect: selfRect)
						switch result {
						case .normal(let adjustedPos):
							chassis.position = adjustedPos
							pendingMountRackID = nil
						case .mountingOpportunity(let rackID):
							// Keep visual position during drag
							chassis.position = proposedPos
							pendingMountRackID = rackID
						}
					}
				},
				onEnded: {
					dragStart = nil
					showDragPreview = false
					dragPreviewScreenLocation = .zero

					// If we have a pending mount, attempt it
					if let rackID = pendingMountRackID {
						// Calculate which row to mount at based on chassis position
						let mountRow = calculateMountingRow(for: rackID)

						let success = sessionManager.mount500SeriesIntoRack(
							chassisID: chassis.id,
							targetRackID: rackID,
							startRow: mountRow
						)

						if success {
							print("✅ Mounted 500-series chassis into rack at row \(mountRow)")
						} else {
							print("❌ Failed to mount - no 3U space available at row \(mountRow)")
						}

						pendingMountRackID = nil
					}
				},
				onEditRequested: {
					editSlots = max(1, chassis.slots.count)
					editName = chassis.name ?? ""
					showEdit = true
				},
				onClearRequested: {
					clearAll500Devices()
				},
				onDeleteRequested: {
					onDelete?()
				},
				newLabelAnchor: .rack(chassis.id),
				defaultLabelOffset: CGPoint(x: 14, y: 4)
			)
			.frame(width: faceWidth)            // <<< exact match
			.zIndex(2)
			}

			// 2) CHASSIS FACE (drop target)
			// When mounted, wrap in HStack with wings for full-width rack appearance
			if chassis.isMounted {
				// Wings: 0.75" standard + 1.25" extra = 2.0" per side
				let wingWidth = 2.0 * settings.pointsPerInch

				// Chassis height spans 3U
				let threeU = DeviceMetrics.rackSize(units: 3, scale: settings.pointsPerInch)
				let chassisHeight = threeU.height

				HStack(spacing: 0) {
					// Left wing - draggable for repositioning within rack
					ZStack {
						Rectangle()
							.fill(Color.gray.opacity(0.3))

						// Chassis name (vertical text) and screw holes
						VStack {
							Circle()
								.fill(Color.black.opacity(0.3))
								.frame(width: 6, height: 6)

							Spacer()

							// Vertical chassis name
							if let name = chassis.name, !name.isEmpty {
								Text(name)
									.font(.system(size: 10, weight: .medium))
									.foregroundColor(.white.opacity(0.7))
									.rotationEffect(.degrees(-90))
									.lineLimit(1)
									.fixedSize()
							}

							Spacer()

							Circle()
								.fill(Color.black.opacity(0.3))
								.frame(width: 6, height: 6)
						}
						.padding(.vertical, 8)
					}
					.frame(width: wingWidth, height: chassisHeight)
					.contextMenu {
						Button {
							editSlots = max(1, chassis.slots.count)
							editName = chassis.name ?? ""
							showEdit = true
						} label: {
							Label("Edit Chassis…", systemImage: "slider.horizontal.3")
						}
						Button { clearAll500Devices() } label: {
							Label("Clear All Devices", systemImage: "xmark.bin")
						}
						Button(role: .destructive) { onDelete?() } label: {
							Label("Delete Chassis", systemImage: "trash")
						}
					}
					.gesture(wingDragGesture)

					// Chassis face
					HStack(spacing: spacing) { chassisContent }
						.background(Color.black)
						.overlay(
							Group {
								if !isInteracting {
									Rectangle()
										.stroke(Color.gray, lineWidth: 1)
								}
							}
						)
						.modifier(ConditionalDrawingGroup(active: isInteracting))
						.background {
							Color.clear
								.contentShape(Rectangle())
								.onDrop(
									of: [UTType.deviceDragPayload],
									delegate: Series500DropDelegate(
										fixedIndex: nil,
										indexFor: { pt in slotIndex(for: pt) },
										slots: $chassis.slots,
										hoveredIndex: $hoveredIndex,
										hoveredRange: $hoveredRange,
										hoveredValid: $hoveredValid,
										library: library,
										session: sessionManager.currentSession,
										sessionManager: sessionManager,
										onCommit: { sessionManager.saveSessions() }
									)
								)
						}

					// Right wing - draggable for repositioning within rack
					ZStack {
						Rectangle()
							.fill(Color.gray.opacity(0.3))

						// Fake screw holes at top and bottom
						VStack {
							Circle()
								.fill(Color.black.opacity(0.3))
								.frame(width: 6, height: 6)
							Spacer()
							Circle()
								.fill(Color.black.opacity(0.3))
								.frame(width: 6, height: 6)
						}
						.padding(.vertical, 8)
					}
					.frame(width: wingWidth, height: chassisHeight)
					.contextMenu {
						Button {
							editSlots = max(1, chassis.slots.count)
							editName = chassis.name ?? ""
							showEdit = true
						} label: {
							Label("Edit Chassis…", systemImage: "slider.horizontal.3")
						}
						Button { clearAll500Devices() } label: {
							Label("Clear All Devices", systemImage: "xmark.bin")
						}
						Button(role: .destructive) { onDelete?() } label: {
							Label("Delete Chassis", systemImage: "trash")
						}
					}
					.gesture(wingDragGesture)
				}
				.zIndex(1)
				.background(
					GeometryReader { proxy in
						Color.clear
							.anchorPreference(key: RackRectsKey.self, value: .bounds) { bounds in
								[RackRect(id: chassis.id, frame: proxy[bounds])]
							}
					}
				)
			} else {
				// Unmounted: show normal chassis without wings
				HStack(spacing: spacing) { chassisContent }
					.background(Color.black)
//				.cornerRadius(8)
				.overlay(
					Group {
						if !isInteracting {
							Rectangle()
								.stroke(Color.gray, lineWidth: 1)
						}
					}
				)
				.modifier(ConditionalDrawingGroup(active: isInteracting))
				.background {
					Color.clear
						.contentShape(Rectangle()) // full face hit area
						.onDrop(
							of: [UTType.deviceDragPayload],
							delegate: Series500DropDelegate(
								fixedIndex: nil,
								indexFor: { pt in slotIndex(for: pt) },   // unchanged
								slots: $chassis.slots,
								hoveredIndex: $hoveredIndex,
								hoveredRange: $hoveredRange,
								hoveredValid: $hoveredValid,
								library: library,
								session: sessionManager.currentSession,
								sessionManager: sessionManager,
								onCommit: { sessionManager.saveSessions() }
							)
						)
				}
				.zIndex(1)
				.background(
					GeometryReader { proxy in
						Color.clear
							.anchorPreference(key: RackRectsKey.self, value: .bounds) { bounds in
								[RackRect(id: chassis.id, frame: proxy[bounds])]
							}
					}
				)
			}

			// LABELS
			if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
				let session = $sessionManager.sessions[i]
				LabelCanvas(
					labels: session.labels,
					anchor: .rack(chassis.id),
					parentOrigin: CGPoint(x: facePadding, y: facePadding)
				)
				.allowsHitTesting(true)
			}
		}
		.overlay {
			// Lightweight drag preview overlay positioned in global screen coordinates
			if showDragPreview {
				GeometryReader { geometry in
					let globalFrame = geometry.frame(in: .global)
					// Convert screen location to local coordinates
					let localX = dragPreviewScreenLocation.x - globalFrame.minX
					let localY = dragPreviewScreenLocation.y - globalFrame.minY

					chassisPreview(spacing: spacing, module: module, slots: slots, faceWidth: faceWidth)
						.position(x: localX, y: localY)
						.allowsHitTesting(false)
				}
			}
		}
		.sheet(isPresented: $showEdit) { editSheet }
	}

	// MARK: - Wing Drag Gesture

	private var wingDragGesture: some Gesture {
		DragGesture(minimumDistance: 5, coordinateSpace: .global)
			.onChanged { value in
				// Start drag: store the initial position
				if dragStart == nil {
					dragStart = chassis.position
					showDragPreview = true
					print("🟢 [WingDrag] Started drag from world: \(chassis.position)")
					print("    startLocation (global): \(value.startLocation)")
				}

				guard let worldOrigin = dragStart else { return }

				// Use GLOBAL coordinate space so view movement doesn't affect translation
				// value.translation is in screen pixels (global space)
				let z = max(canvasZoom, 0.0001)
				let worldDelta = CGSize(
					width: value.translation.width / z,
					height: value.translation.height / z
				)

				let proposedY = worldOrigin.y + worldDelta.height

				// Update preview location to follow cursor in screen space
				dragPreviewScreenLocation = value.location

				print("📍 [WingDrag] translation.y=\(Int(value.translation.height)) worldDelta=\(Int(worldDelta.height)) proposedY=\(Int(proposedY)) origin=\(Int(worldOrigin.y)) zoom=\(String(format: "%.2f", z))")

				// Check if still within rack bounds
				if let rackID = chassis.mountedInRack,
				   let rack = sessionManager.currentSession?.racks.first(where: { $0.id == rackID }) {

					// Calculate metrics
					let ppi = settings.pointsPerInch
					let rowHeight = DeviceMetrics.rackSize(units: 1, scale: ppi).height
					let rowSpacing: CGFloat = 1
					let chassisHeight = 3 * rowHeight + 2 * rowSpacing

					// Get rack bounds from collision rects
					guard let rackRect = collisionRects.first(where: { $0.id == rackID && $0.isRack }) else {
						print("⚠️ [WingDrag] Could not find rack collision rect!")
						return
					}

					let dragStripHeight: CGFloat = 32
					let facePadding: CGFloat = 16
					let rackInteriorTop = rackRect.rect.minY + dragStripHeight + facePadding
					let rackInteriorBottom = rackRect.rect.maxY - facePadding

					let chassisTopY = proposedY - chassisHeight / 2
					let chassisBottomY = proposedY + chassisHeight / 2

					// Check if dragged significantly outside rack vertically
					// Use a smaller threshold to make unmounting easier
					let dragThreshold: CGFloat = 30

					// Only unmount if dragged significantly outside
					if chassisTopY < rackInteriorTop - dragThreshold || chassisBottomY > rackInteriorBottom + dragThreshold {
						// Unmount and switch to free dragging
						print("🔓 [WingDrag] UNMOUNTING - outside threshold")
						sessionManager.unmount500Series(chassisID: chassis.id)
						chassis.position = CGPoint(x: worldOrigin.x, y: proposedY)
						dragStart = chassis.position
					} else {
						// Still within rack - calculate which row the POINTER is over
						// Use a temporary position to calculate row without modifying chassis.position
						let tempPosition = CGPoint(x: worldOrigin.x, y: proposedY)

						// Temporarily set position for row calculation
						let savedPosition = chassis.position
						chassis.position = tempPosition
						let newRow = calculateMountingRow(for: rackID)
						chassis.position = savedPosition // Restore immediately

						let maxRow = max(0, rack.rows - 3)
						let clampedRow = max(0, min(newRow, maxRow))

						print("📊 [WingDrag] pointer at worldY=\(Int(proposedY)) → row=\(newRow) clamped=\(clampedRow)")

						// Update via SessionManager - this will snap position to the row center
						sessionManager.updateMountingRow(chassisID: chassis.id, newRow: clampedRow)

						print("✓ [WingDrag] After updateMountingRow, chassis snapped to: \(Int(chassis.position.y))")

						// DO NOT update dragStart or dragStartScreenLocation
						// Keep them at original values so drag continues from where it started
					}
				} else {
					// Not mounted - move freely
					chassis.position = CGPoint(x: worldOrigin.x + worldDelta.width, y: proposedY)
					print("🆓 [WingDrag] Free drag to: \(Int(proposedY))")
				}
			}
			.onEnded { _ in
				print("🔴 [WingDrag] Drag ended at position: \(chassis.position)")
				dragStart = nil
				showDragPreview = false
				dragPreviewScreenLocation = .zero
				sessionManager.saveSessions()
			}
	}

    private var chassisContent: some View {
        var views: [AnyView] = []
        var index = 0
        
		while index < chassis.slots.count {
			if let instance = chassis.slots[index],
			   let device = library.device(for: instance.deviceID) {
				
				let slotWidth = device.slotWidth ?? 1
				views.append(
					AnyView(
						Series500ChassisSlotView(
							index: index,
							instance: instance,
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid
						)
						.frame(width: DeviceMetrics
							.moduleSize(units: slotWidth, scale: settings.pointsPerInch).width)
					)
				)
				index += slotWidth
			} else {
				views.append(
					AnyView(
						Series500ChassisSlotView(
							index: index,
							instance: nil,
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid
						)
					)
				)
				index += 1
			}
		}

        return HStack(spacing: 4) {
            ForEach(Array(views.enumerated()), id: \.offset) { _, view in
                view
            }
        }
    }
	
	
	// Map a drop point (in the chassis HStack's local coords) to a 500-series slot index (horizontal).
	private func slotIndex(for pt: CGPoint) -> Int {
		let spacing: CGFloat = 4
		let module = DeviceMetrics.moduleSize(units: 1, scale: settings.pointsPerInch)
		let slotStride = module.width + spacing
		
		// This HStack has no explicit .padding() before .onDrop, so no padding compensation needed.
		let x = max(0, pt.x)
		let raw = Int(floor((x + spacing / 2) / slotStride))
		
		return max(0, min(raw, max(0, chassis.slots.count - 1)))
	}

	// MARK: - Drag Preview

	@ViewBuilder
	private func chassisPreview(spacing: CGFloat, module: CGSize, slots: Int, faceWidth: CGFloat) -> some View {
		let chassisHeight = module.height + 2 * facePadding

		// Simplified preview: just the chassis outline with a semi-transparent fill
		VStack(spacing: 0) {
			// Drag strip preview
			Rectangle()
				.fill(.ultraThinMaterial)
				.frame(width: faceWidth, height: 32)
				.overlay(
					Text(chassis.name ?? "500 Series")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
				)

			// Chassis face preview
			Rectangle()
				.fill(Color.black.opacity(0.7))
				.frame(width: faceWidth, height: chassisHeight)
				.overlay(
					Rectangle()
						.stroke(Color.gray, lineWidth: 1)
				)
				.overlay(
					Text("\(slots) slots")
						.font(.system(size: 10, weight: .medium))
						.foregroundStyle(.secondary)
				)
		}
		.shadow(radius: 16, y: 4)
		.opacity(0.85)
		.scaleEffect(canvasZoom)
	}

	// MARK: - 500-series edit / helpers

	private func clearAll500Devices() {
		for i in chassis.slots.indices { chassis.slots[i] = nil }
	}
	
	@ViewBuilder
	private var editSheet: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit 500-Series Chassis").font(.headline)

			TextField("Chassis Name (optional)", text: $editName)
				.textFieldStyle(.roundedBorder)

			Stepper("Slots: \(editSlots)", value: $editSlots, in: 1...48)

			HStack {
				Spacer()
				Button("Cancel") { showEdit = false }
				Button("Save") {
					let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
					chassis.name = trimmedName.isEmpty ? nil : trimmedName
					apply500Resize(to: editSlots)
					sessionManager.saveSessions()
					showEdit = false
				}.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 320)
	}
	
	private func apply500Resize(to newSlots: Int) {
		let oldSlots = chassis.slots.count
		guard newSlots != oldSlots else { return }
		
		if newSlots < oldSlots {
			// trim devices that extend into the truncated RIGHT edge
			var i = 0
			while i < oldSlots {
				if let inst = chassis.slots[i] {
					if i == 0 || chassis.slots[i - 1]?.id != inst.id {
						let width = (library.device(for: inst.deviceID)?.slotWidth ?? 1)
						let span = i ..< min(i + width, oldSlots)
						if span.upperBound > newSlots {
							for j in span { chassis.slots[j] = nil }
						}
						i = span.upperBound
						continue
					}
				}
				i += 1
			}
			chassis.slots = Array(chassis.slots.prefix(newSlots))
		} else {
			chassis.slots.append(contentsOf: Array(repeating: nil, count: newSlots - oldSlots))
		}
	}

}
