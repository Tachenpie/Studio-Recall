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
    
    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editSlots: Int = 0
	
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
				onEnded: { dragStart = nil },
				onEditRequested: {
					editSlots = max(1, chassis.slots.count)
					showEdit = true
				},
				onClearRequested: {
					clearAll500Devices()
				},
				onDeleteRequested: {
					onDelete?()
				}
			)
			.frame(width: faceWidth)            // <<< exact match
			.zIndex(2)
			
			// 2) CHASSIS FACE (drop target)
			HStack(spacing: spacing) { chassisContent }
				.background(Color.black)
				.cornerRadius(8)
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
				.onDrop(of: [UTType.deviceDragPayload],
						delegate: Series500DropDelegate(
							fixedIndex: nil,
							indexFor: { pt in slotIndex(for: pt) },   // your helper maps CGPoint → slot index
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid,
							library: library,
							onCommit: { sessionManager.saveSessions() }
						)
				)
				.zIndex(1)
		}
		.sheet(isPresented: $showEdit) { editSheet }
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

	// MARK: - 500-series edit / helpers
	
	private func clearAll500Devices() {
		for i in chassis.slots.indices { chassis.slots[i] = nil }
	}
	
	@ViewBuilder
	private var editSheet: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit 500-Series Chassis").font(.headline)
			Stepper("Slots: \(editSlots)", value: $editSlots, in: 1...48)
			HStack {
				Spacer()
				Button("Cancel") { showEdit = false }
				Button("Save") {
					apply500Resize(to: editSlots)
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
