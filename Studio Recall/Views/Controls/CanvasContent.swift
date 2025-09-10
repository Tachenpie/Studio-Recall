//
//  CanvasContent.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI

struct CanvasContent: View {
    @ObservedObject var editableDevice: EditableDevice
    let canvasSize: CGSize
    @Binding var selectedControlId: UUID?
    @Binding var draggingControlId: UUID?
    let gridStep: CGFloat
	let showBadges: Bool

    var body: some View {
        ZStack {
            // Faceplate
            if let data = editableDevice.device.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                Text("No Faceplate Image").foregroundColor(.white.opacity(0.7))
            }

            // Controls
            ForEach($editableDevice.device.controls) { $control in
                ControlItemView(
                    control: $control,
                    geoSize: canvasSize,
                    editableDevice: editableDevice,
                    selectedControlId: $selectedControlId,
                    draggingControlId: $draggingControlId,
                    gridStep: gridStep,
					showBadges: showBadges
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}

// MARK: - Control item view
private struct ControlItemView: View {
    @Binding var control: Control
    let geoSize: CGSize
    let editableDevice: EditableDevice
    @Binding var selectedControlId: UUID?
    @Binding var draggingControlId: UUID?
    let gridStep: CGFloat
	let showBadges: Bool
	
	var body: some View {
		ZStack {
			if !control.regions.isEmpty {
				ForEach(control.regions.indices, id: \.self) { idx in
					let region = control.regions[idx]
					ControlImageRenderer(
						control: $control,
						faceplate: (editableDevice.device.imageData.flatMap { NSImage(data: $0) }),
						canvasSize: geoSize,
						resolveControl: { id in editableDevice.device.controls.first(where: { $0.id == id }) },
						onlyRegionIndex: idx   // <— draw just this region
					)
					.clipShape(RegionClipShape(shape: region.shape))
					.frame(width: region.rect.width * geoSize.width,
						   height: region.rect.height * geoSize.height)
					.position(x: region.rect.midX * geoSize.width,
							  y: region.rect.midY * geoSize.height)
					.contentShape(Rectangle())
					.onTapGesture { selectedControlId = control.id }
				}
			} else {
				// Vector fallback; draggable
				ControlImageRenderer(
					control: $control,
					faceplate: (editableDevice.device.imageData.flatMap { NSImage(data: $0) }),
					canvasSize: geoSize,
					resolveControl: { id in editableDevice.device.controls.first(where: { $0.id == id }) }
				)
				.frame(width: 30, height: 30)
				.position(x: control.x * geoSize.width, y: control.y * geoSize.height)
				.onTapGesture { selectedControlId = control.id }
				.gesture(
					DragGesture()
						.onChanged { g in
							draggingControlId = control.id
							selectedControlId = control.id
							let nx = (g.location.x / geoSize.width).clamped(to: 0...1)
							let ny = (g.location.y / geoSize.height).clamped(to: 0...1)
							control.x = snap(nx)
							control.y = snap(ny)
						}
						.onEnded { _ in draggingControlId = nil }
				)
				.contextMenu {
					Button {
						var copy = control
						copy.id = UUID()
						copy.name = control.name + " Copy"
						copy.x = min(1, control.x + 0.02)
						copy.y = min(1, control.y + 0.02)
						if let idx = editableDevice.device.controls.firstIndex(where: { $0.id == control.id }) {
							editableDevice.device.controls.insert(copy, at: idx + 1)
						} else {
							editableDevice.device.controls.append(copy)
						}
						selectedControlId = copy.id
					} label: { Label("Duplicate", systemImage: "plus.square.on.square") }
					
					Button(role: .destructive) {
						if let i = editableDevice.device.controls.firstIndex(where: { $0.id == control.id }) {
							_ = editableDevice.device.controls.remove(at: i)
							if selectedControlId == control.id { selectedControlId = nil }
						}
					} label: { Label("Delete", systemImage: "trash") }
				}
			}
			if showBadges {
				ForEach(editableDevice.device.controls) { c in
					ControlBadgeOverlay(
						control: c,
						canvasSize: geoSize,
						isSelected: c.id == selectedControlId,
						showRegion: true   // show the region box if one exists
					)
					.contentShape(Rectangle()) // make it easy to tap
					.onTapGesture {
						selectedControlId = c.id
					}
				}
			}
		}
	}

    private func snap(_ v: CGFloat) -> CGFloat {
        (v.clamped(to: 0...1) / gridStep).rounded() * gridStep
    }
}
