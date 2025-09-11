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
	@Environment(\.canvasZoom) private var canvasZoom
    
    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
	@State private var dragStart: CGPoint? = nil
	
	var onDelete: (() -> Void)? = nil
    
	var body: some View {
		let spacing: CGFloat = 4
		let module = DeviceMetrics.moduleSize(units: 1, scale: settings.pointsPerInch)
		let slots = chassis.slots.count
		let faceWidth = CGFloat(slots) * module.width + CGFloat(max(0, slots - 1)) * spacing
		
		VStack(spacing: 0) {
			// 1) TABLETOP (not a drop target)
			DragStrip(
				title: (chassis.name?.isEmpty == false ? chassis.name : "500 Series"),
				onBegan: { if dragStart == nil { dragStart = chassis.position } },
				onDrag: { screenDelta in
					let origin = dragStart ?? chassis.position
					let z = max(canvasZoom, 0.0001)                   // @Environment(\.canvasZoom)
					let worldDelta = CGSize(width: screenDelta.width  / z,
											height: screenDelta.height / z)
					chassis.position = CGPoint(x: origin.x + worldDelta.width,
											   y: origin.y + worldDelta.height)
				},
				onEnded: { dragStart = nil }
			)
			.frame(width: faceWidth)            // <<< exact match
			.zIndex(2)
			
			// 2) CHASSIS FACE (drop target)
			HStack(spacing: spacing) { chassisContent }
				.background(Color.black)
				.cornerRadius(8)
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
				.onDrop(of: [UTType.deviceDragPayload],
						delegate: Series500CatchAllDropDelegate(
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid,
							library: library,
							slotWidth: module.width,
							spacing: spacing
						)
				)
				.zIndex(1)
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
}

// MARK: - Catch All Drop Delegate
private struct Series500CatchAllDropDelegate: DropDelegate {
	@Binding var slots: [DeviceInstance?]
	@Binding var hoveredIndex: Int?
	@Binding var hoveredRange: Range<Int>?
	@Binding var hoveredValid: Bool
	
	let library: DeviceLibrary
	let slotWidth: CGFloat
	let spacing: CGFloat
	
	// Map a local X (0 at left edge) to a slot index
	private func index(for location: CGPoint) -> Int {
		let stride = max(1, slotWidth + spacing)
		let raw = Int(floor(location.x / stride))
		return min(max(raw, 0), max(slots.count - 1, 0))
	}
	
	func validateDrop(info: DropInfo) -> Bool {
		info.hasItemsConforming(to: [UTType.deviceDragPayload])
	}
	
	func dropEntered(info: DropInfo) {
		updateHover(info: info)
	}
	
	func dropUpdated(info: DropInfo) -> DropProposal? {
		updateHover(info: info)
		if DragContext.shared.currentPayload?.source == .library {
			return DropProposal(operation: .copy)
		} else {
			return DropProposal(operation: .move)
		}
	}
	
	func performDrop(info: DropInfo) -> Bool {
		guard
			let payload = DragContext.shared.currentPayload,
			let device  = library.device(for: payload.deviceId)
		else { return false }
		
		let start = hoveredIndex ?? 0
		let units = device.slotWidth ?? 1
		let range = start ..< min(start + units, slots.count)
		
		// Must be valid & fully empty (except the instance being moved)
		guard canPlace(range: range, ignoring: payload.instanceId) else { return false }
		
		if payload.source == .library {
			// copy from library
			let instance = DeviceInstance(deviceID: device.id, device: device)
			for i in range { slots[i] = nil }
			slots[start] = instance
		} else {
			// move existing (clear old range, then place)
			if let moving = payload.instanceId,
			   let oldIndex = slots.firstIndex(where: { $0?.id == moving }),
			   let oldDeviceID = slots[oldIndex]?.deviceID,
			   let oldDevice = library.device(for: oldDeviceID) {
				let oldUnits = oldDevice.slotWidth ?? 1
				for i in oldIndex ..< min(oldIndex + oldUnits, slots.count) {
					slots[i] = nil
				}
			}
			let instance = DeviceInstance(deviceID: device.id, device: device)
			for i in range { slots[i] = nil }
			slots[start] = instance
		}
		
		hoveredIndex = nil
		hoveredRange = nil
		hoveredValid = false
		DragContext.shared.endDrag()
		return true
	}
	
	// MARK: - helpers
	private func updateHover(info: DropInfo) {
		guard
			let payload = DragContext.shared.currentPayload,
			let device  = library.device(for: payload.deviceId)
		else {
			hoveredIndex = nil
			hoveredRange = nil
			hoveredValid = false
			return
		}
		
		let loc = info.location
		let start = index(for: loc)
		let units = device.slotWidth ?? 1
		let range = start ..< min(start + units, slots.count)
		
		hoveredIndex = start
		hoveredRange = range
		hoveredValid = canPlace(range: range, ignoring: payload.instanceId)
	}
	
	private func canPlace(range: Range<Int>, ignoring ignored: UUID?) -> Bool {
		guard !range.isEmpty, range.upperBound <= slots.count else { return false }
		for i in range {
			if let inst = slots[i], inst.id != ignored { return false }
		}
		return true
	}
}
