//
//  SessionCanvasLayer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SessionCanvasLayer: View {
    @Binding var session: Session
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary

	let canvasSize: CGSize

	let rackRectsCG: [CGRect]
	let chassisRectsCG: [CGRect]

	var rackRects: [RackRect] = []
	let visibleRect: CGRect

	private let preload: CGFloat = 120

	// Cache collision rects to avoid rebuilding every frame
	@State private var cachedCollisionRects: [CollisionRect] = []
	@State private var lastRackPositions: [UUID: CGPoint] = [:]
	@State private var lastChassisPositions: [UUID: CGPoint] = [:]
	
    var body: some View {
        // Precompute locals; avoid heavy inline expressions
		let padded = visibleRect.insetBy(dx: -preload, dy: -preload)

		let visibleRacks: [Int] = rackRectsCG.enumerated().compactMap { i, r in
			r.intersects(padded) ? i : nil
		}
		let visibleChassis: [Int] = chassisRectsCG.enumerated().compactMap { i, r in
			r.intersects(padded) ? i : nil
		}

		// Use cached collision rects - only rebuild if positions changed
		let collisionRects = computeCollisionRects()

		ZStack(alignment: .topLeading) {
            // Racks
//            ForEach(racks.indices, id: \.self) { idx in
			ForEach(visibleRacks, id: \.self) { idx in
				RackChassisView(
					rack: $session.racks[idx],
					onDelete: {
						let id = session.racks[idx].id
						session.racks.removeAll { $0.id == id }
					}
				)
                .position(session.racks[idx].position)
            }

			// Pedalboards
			ForEach(session.pedalboards.indices, id: \.self) { idx in
				PedalboardView(
					pedalboard: $session.pedalboards[idx],
					onDelete: {
						let id = session.pedalboards[idx].id
						session.pedalboards.removeAll { $0.id == id }
					}
				)
				.position(session.pedalboards[idx].position)
			}

            // Series 500 chassis
//            ForEach(chassis.indices, id: \.self) { idx in
			ForEach(visibleChassis, id: \.self) { idx in
				let chassis = session.series500Chassis[idx]
				let chassisPosition: CGPoint = {
					// If mounted, calculate position relative to rack
					if let rackID = chassis.mountedInRack,
					   let mountRow = chassis.mountedAtRow,
					   let rackIdx = session.racks.firstIndex(where: { $0.id == rackID }),
					   rackIdx < rackRectsCG.count {
						let rack = session.racks[rackIdx]

						// Calculate position within rack
						// Note: .position() places the CENTER of the view at the given point
						let rackFacePadding: CGFloat = 16
						let dragStripHeight: CGFloat = 32
						let ppi = settings.pointsPerInch
						let oneU = DeviceMetrics.rackSize(units: 1, scale: ppi)
						let rowHeight = oneU.height
						let rowSpacing: CGFloat = 1

						// Calculate the full rack height
						let faceHeight = rackFacePadding * 2
							+ CGFloat(rack.rows) * rowHeight
							+ CGFloat(max(0, rack.rows - 1)) * rowSpacing
						let totalRackHeight = dragStripHeight + faceHeight

						// rack.position is the CENTER of the entire rack view (DragStrip + face)
						// Calculate the top of the rack view
						let rackTop = rack.position.y - totalRackHeight / 2

						// Calculate Y position of the top of the mounted row
						let rowTopY = rackTop + dragStripHeight + rackFacePadding + CGFloat(mountRow) * (rowHeight + rowSpacing)

						// Chassis spans 3U
						let chassisHeight = 3 * rowHeight + 2 * rowSpacing

						// Position is at CENTER of chassis
						let chassisCenterY = rowTopY + chassisHeight / 2

						// X position: rack.position.x is center of rack, so just use it directly
						return CGPoint(x: rack.position.x, y: chassisCenterY)
					}
					return chassis.position
				}()

				Series500ChassisView(
					chassis: $session.series500Chassis[idx],
					onDelete: {
						let id = session.series500Chassis[idx].id
						session.series500Chassis.removeAll { $0.id == id }
					}
				)
                .position(chassisPosition)
            }

			// Labels
			LabelCanvas(
				labels: $session.labels,
				anchor: .session,
				parentOrigin: .zero,
				rackRects: rackRects
			)
        }
		.environment(\.collisionRects, collisionRects)
    }
	
	private func filteredRackIndices(_ rect: CGRect) -> [Int] {
		rackRects.enumerated().compactMap { i, rr in
			rr.frame.intersects(rect) ? i : nil
		}
	}

	// MARK: - Collision Rect Caching

	/// Only rebuild collision rects if positions have actually changed
	private func computeCollisionRects() -> [CollisionRect] {
		// Check if positions changed
		var positionsChanged = false

		// Check racks
		if session.racks.count != lastRackPositions.count {
			positionsChanged = true
		} else {
			for (idx, rack) in session.racks.enumerated() {
				if idx >= rackRectsCG.count { break }
				if lastRackPositions[rack.id] != rack.position {
					positionsChanged = true
					break
				}
			}
		}

		// Check chassis
		if !positionsChanged {
			if session.series500Chassis.count != lastChassisPositions.count {
				positionsChanged = true
			} else {
				for (idx, chassis) in session.series500Chassis.enumerated() {
					if idx >= chassisRectsCG.count { break }
					if lastChassisPositions[chassis.id] != chassis.position {
						positionsChanged = true
						break
					}
				}
			}
		}

		// Return cached if nothing changed
		if !positionsChanged && !cachedCollisionRects.isEmpty {
			return cachedCollisionRects
		}

		// Rebuild and cache
		let newRects = session.racks.enumerated().map { idx, rack in
			CollisionRect(id: rack.id, rect: rackRectsCG[idx], isRack: true)
		} + session.series500Chassis.enumerated().map { idx, chassis in
			CollisionRect(id: chassis.id, rect: chassisRectsCG[idx], isRack: false)
		}

		// Update cache
		DispatchQueue.main.async {
			self.cachedCollisionRects = newRects
			self.lastRackPositions = Dictionary(uniqueKeysWithValues: self.session.racks.map { ($0.id, $0.position) })
			self.lastChassisPositions = Dictionary(uniqueKeysWithValues: self.session.series500Chassis.map { ($0.id, $0.position) })
		}

		return newRects
	}
}
