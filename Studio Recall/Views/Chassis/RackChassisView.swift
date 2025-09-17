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
						delegate: ChassisDropDelegate(
							currentIndex: nil,
							indexFor: { pt in slotIndex(for: pt) }, // your existing mapper: point → slot index
							slots: $rack.slots,
							hoveredIndex: $hoveredIndex,
							hoveredValid: $hoveredValid,
							hoveredRange: $hoveredRange,
							library: library,
							measure: { $0.rackUnits ?? 1 },
							kind: .rack,
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
	// Map a drop point (in the chassis VStack's local coords) to a slot index.
	private func slotIndex(for pt: CGPoint) -> Int {
		// Match the layout used above
		let spacing: CGFloat = 4
		let unit = DeviceMetrics.rackSize(units: 1, scale: settings.pointsPerInch)
		let unitH = unit.height
		
		// Account for the .padding() on the chassis container (default ~= 16)
		let containerPadding: CGFloat = 16
		var y = pt.y - containerPadding
		if y < 0 { y = 0 }
		
		// Convert y → row index, snapping by (unit height + spacing)
		let rowFloat = (y + spacing / 2) / (unitH + spacing)
		let row = Int(rowFloat.rounded(.down))
		
		// Clamp to slots
		return max(0, min(row, max(0, rack.slots.count - 1)))
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



