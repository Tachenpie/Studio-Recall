//
//  ControlItemView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/12/25.
//
//
//  ControlItemView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/12/25.
//

import SwiftUI
import AppKit

struct ControlItemView: View {
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
				RegionPatchesView(
					control: $control,
					geoSize: geoSize,
					editableDevice: editableDevice,
					onTap: { selectedControlId = control.id }
				)
			} else {
				FallbackVectorView(
					control: $control,
					geoSize: geoSize,
					editableDevice: editableDevice,
					onTap: { selectedControlId = control.id },
					onDragChanged: { loc in
						draggingControlId = control.id
						selectedControlId = control.id
						let nx = (loc.x / geoSize.width).clamped(to: 0...1)
						let ny = (loc.y / geoSize.height).clamped(to: 0...1)
						control.x = snap(nx)
						control.y = snap(ny)
					},
					onDragEnded: { draggingControlId = nil }
				)
			}
			
			if showBadges {
				ControlBadgesOverlayList(
					device: editableDevice,
					geoSize: geoSize,
					selectedControlId: $selectedControlId
				)
				.allowsHitTesting(true)
			}
		}
	}
	
	private func snap(_ v: CGFloat) -> CGFloat {
		(v.clamped(to: 0...1) / gridStep).rounded() * gridStep
	}
}

// MARK: - Region patches (image regions with transforms + proper mask)
private struct RegionPatchesView: View {
	@Binding var control: Control
	let geoSize: CGSize
	let editableDevice: EditableDevice
	let onTap: () -> Void
	
	var body: some View {
		// Resolve once to keep the type-checker calm
		let faceplate: NSImage? = editableDevice.device.imageData.flatMap { NSImage(data: $0) }
		let resolver: (UUID) -> Control? = { id in
			editableDevice.device.controls.first(where: { $0.id == id })
		}
		
		return ZStack {
			ForEach(Array(control.regions.enumerated()), id: \.0) { idx, region in
				RegionPatch(
					control: $control,
					faceplate: faceplate,
					geoSize: geoSize,
					regionIndex: idx,
					region: region,
					resolve: resolver,
					onTap: onTap
				)
				.id(control.renderKey) // nudge redraw when values change
			}
		}
	}
}

private struct RegionPatch: View {
	@Binding var control: Control
	let faceplate: NSImage?
	let geoSize: CGSize
	let regionIndex: Int
	let region: ImageRegion
	let resolve: (UUID) -> Control?
	let onTap: () -> Void
	
	var body: some View {
		ControlImageRenderer(
			control: $control,
			faceplate: faceplate,
			canvasSize: geoSize,
			resolveControl: resolve,
			onlyRegionIndex: regionIndex
		)
		.frame(
			width:  region.rect.width  * geoSize.width,
			height: region.rect.height * geoSize.height
		)
		.position(
			x: region.rect.midX * geoSize.width,
			y: region.rect.midY * geoSize.height
		)
		// IMPORTANT: mask after layout/position so circles are truly circles.
		.compositingGroup()
		.mask { RegionClipShape(shape: region.shape) }
		.contentShape(RegionClipShape(shape: region.shape))
		.onTapGesture { onTap() }
	}
}

// MARK: - Fallback vector glyph (no regions defined)
private struct FallbackVectorView: View {
	@Binding var control: Control
	let geoSize: CGSize
	let editableDevice: EditableDevice
	let onTap: () -> Void
	let onDragChanged: (CGPoint) -> Void
	let onDragEnded: () -> Void
	
	var body: some View {
		let faceplate: NSImage? = editableDevice.device.imageData.flatMap { NSImage(data: $0) }
		let resolver: (UUID) -> Control? = { id in
			editableDevice.device.controls.first(where: { $0.id == id })
		}
		
		return ControlImageRenderer(
			control: $control,
			faceplate: faceplate,
			canvasSize: geoSize,
			resolveControl: resolver
		)
		.frame(width: 30, height: 30)
		.position(x: control.x * geoSize.width, y: control.y * geoSize.height)
		.onTapGesture { onTap() }
		.gesture(
			DragGesture()
				.onChanged { g in onDragChanged(g.location) }
				.onEnded { _ in onDragEnded() }
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
			} label: { Label("Duplicate", systemImage: "plus.square.on.square") }
			
			Button(role: .destructive) {
				if let i = editableDevice.device.controls.firstIndex(where: { $0.id == control.id }) {
					_ = editableDevice.device.controls.remove(at: i)
				}
			} label: { Label("Delete", systemImage: "trash") }
		}
	}
}

// MARK: - Badges overlay list
private struct ControlBadgesOverlayList: View {
	let device: EditableDevice
	let geoSize: CGSize
	@Binding var selectedControlId: UUID?
	
	var body: some View {
		ForEach(device.device.controls) { c in
			ControlBadgeOverlay(
				control: c,
				canvasSize: geoSize,
				isSelected: c.id == selectedControlId,
				showRegion: true
			)
			.contentShape(Rectangle())
			.onTapGesture { selectedControlId = c.id }
		}
	}
}

