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
	@Environment(\.canvasZoom) private var canvasZoom
    
    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
	@State private var dragStart: CGPoint? = nil
	@State private var showEdit = false
	@State private var editUnits: Int = 0
	
	var onDelete: (() -> Void)? = nil
    
	var body: some View {
		let spacing: CGFloat = 4
		let unit = DeviceMetrics.rackSize(units: 1, scale: settings.pointsPerInch)
		// Face padding is .padding() on the face = 16pt per side -> +32
		let faceWidth = unit.width + 32
		
		VStack(spacing: 0) {
			// 1) TABLETOP (not a drop target)
			DragStrip(
				title: (rack.name?.isEmpty == false ? rack.name : "Rack"),
				onBegan: { if dragStart == nil { dragStart = rack.position } },
				onDrag: { screenDelta in
					let origin = dragStart ?? rack.position
					let z = max(canvasZoom, 0.0001)                   // @Environment(\.canvasZoom)
					let worldDelta = CGSize(width: screenDelta.width  / z,
											height: screenDelta.height / z)
					rack.position = CGPoint(x: origin.x + worldDelta.width,
											y: origin.y + worldDelta.height)
				},
				onEnded: { dragStart = nil },
				onEditRequested: {
					editUnits = max(1, rack.slots.count)
					showEdit = true
				},
				onClearRequested: {
					clearAllRackDevices()
				},
				onDeleteRequested: {
					onDelete?()
				}
			)
			.frame(width: faceWidth)            // <<< exact match
			.zIndex(2)
			
			// 2) CHASSIS FACE (drop target)
			VStack(spacing: spacing) { chassisContent }
				.padding()
				.background(Color.black.opacity(0.8))
				.cornerRadius(8)
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.85), lineWidth: 1))
				.onDrop(of: [UTType.deviceDragPayload],
						delegate: RackCatchAllDropDelegate(
							slots: $rack.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid,
							library: library,
							rowHeight: unit.height,
							spacing: spacing
						)
				)
				.zIndex(1)
		}
		.sheet(isPresented: $showEdit) { editSheet }
	}
    
    private var chassisContent: some View {
        var views: [AnyView] = []
        var index = 0
        
        while index < rack.slots.count {
            if let instance = rack.slots[index],
               let device = library.device(for: instance.deviceID) {
                
                let units = device.rackUnits ?? 1
                views.append(
                    AnyView(
                        RackChassisSlotView(
                            index: index,
                            instance: instance,
                            slots: $rack.slots,
                            hoveredIndex: $hoveredIndex,
                            hoveredRange: $hoveredRange,
                            hoveredValid: $hoveredValid
                        )
                        .frame(height: DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch).height)
                    )
                )
                index += units // skip occupied slots
            } else {
                views.append(
                    AnyView(
                        RackChassisSlotView(
                            index: index,
                            instance: nil,
                            slots: $rack.slots,
                            hoveredIndex: $hoveredIndex,
                            hoveredRange: $hoveredRange,
                            hoveredValid: $hoveredValid
                        )
                    )
                )
                index += 1
            }
        }

    
    return VStack(spacing: 4) {
        ForEach(Array(views.enumerated()), id: \.offset) { _, view in
            view
        }
    }
}
	// MARK: - Rack edit / helpers
	
	private func clearAllRackDevices() {
		for i in rack.slots.indices { rack.slots[i] = nil }
	}
	
	@ViewBuilder
	private var editSheet: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit Rack").font(.headline)
			Stepper("Rack Units: \(editUnits)", value: $editUnits, in: 1...200)
			HStack {
				Spacer()
				Button("Cancel") { showEdit = false }
				Button("Save") {
					applyRackResize(to: editUnits)
					showEdit = false
				}.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 320)
	}
	
	private func applyRackResize(to newUnits: Int) {
		let oldUnits = rack.slots.count
		guard newUnits != oldUnits else { return }
		
		if newUnits < oldUnits {
			// trim devices that extend into the truncated bottom
			var i = 0
			while i < oldUnits {
				if let inst = rack.slots[i] {
					// top of this device span?
					if i == 0 || rack.slots[i - 1]?.id != inst.id {
						let deviceUnits = (library.device(for: inst.deviceID)?.rackUnits ?? 1)
						let span = i ..< min(i + deviceUnits, oldUnits)
						if span.upperBound > newUnits {
							for j in span { rack.slots[j] = nil }
						}
						i = span.upperBound
						continue
					}
				}
				i += 1
			}
			rack.slots = Array(rack.slots.prefix(newUnits))
		} else {
			// grow by appending empty slots at the bottom
			rack.slots.append(contentsOf: Array(repeating: nil, count: newUnits - oldUnits))
		}
	}
}

// MARK: - Catch All Drop Delegate
private struct RackCatchAllDropDelegate: DropDelegate {
	@Binding var slots: [DeviceInstance?]
	@Binding var hoveredIndex: Int?
	@Binding var hoveredRange: Range<Int>?
	@Binding var hoveredValid: Bool
	
	let library: DeviceLibrary
	let rowHeight: CGFloat
	let spacing: CGFloat
	
	// Convert a local Y (0 at top of rows) to a slot index
	private func index(for location: CGPoint) -> Int {
		// Each visual row consumes rowHeight + spacing (except last, but clamping handles it)
		let stride = max(1, rowHeight + spacing)
		let raw = Int(floor(location.y / stride))
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
		// mimic your normal proposal logic: copy from library, move otherwise
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
		let units = (device.rackUnits ?? 1)
		let range = start ..< min(start + units, slots.count)
		
		// must be valid & fully empty (except the instance being moved)
		guard canPlace(range: range, ignoring: payload.instanceId) else { return false }
		
		if payload.source == .library {
			// copy from library
			let instance = DeviceInstance(deviceID: device.id, device: device)
			for i in range { slots[i] = nil }
			slots[start] = instance
		} else {
			// move existing
			if let moving = payload.instanceId,
			   let oldIndex = slots.firstIndex(where: { $0?.id == moving }) {
				// clear old range
				if let oldDevice = library.device(for: slots[oldIndex]?.deviceID ?? device.id) {
					let oldUnits = oldDevice.rackUnits ?? 1
					for i in oldIndex ..< min(oldIndex + oldUnits, slots.count) {
						slots[i] = nil
					}
				}
			}
			// place at new range
			let instance = DeviceInstance(deviceID: device.id, device: device)
			for i in range { slots[i] = nil }
			slots[start] = instance
		}
		
		// clear hover
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
		
		// location is already in the overlay's local coords
		let loc = info.location
		let start = index(for: loc)
		let units = (device.rackUnits ?? 1)
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



