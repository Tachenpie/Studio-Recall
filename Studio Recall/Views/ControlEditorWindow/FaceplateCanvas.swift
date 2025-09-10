//
//  FaceplateCanvas.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
// FaceplateCanvas.swift
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct FaceplateCanvas: View {
	@ObservedObject var editableDevice: EditableDevice
	@Environment(\.undoManager) private var undoManager
	@Environment(\.isPanMode) private var isPanMode
	
	// Selection / region edit
	@Binding var selectedControlId: UUID?
	@Binding var isEditingRegion: Bool
	@Binding var zoom: CGFloat
	@Binding var pan: CGSize
	
	// local state just for canvas content
	@State private var draggingControlId: UUID? = nil
	
	// tuning
	private let gridStep: CGFloat = 0.0025
	private let minRegion: CGFloat = 0.004
	
	var body: some View {
		let aspect = computeAspectRatio()
		let showBadges = !(isEditingRegion || draggingControlId != nil)
		
		CanvasViewport(
			aspect: aspect,
			zoom: $zoom,
			pan: $pan,
			content: { canvasSize in
				ZStack {
					CanvasContent(
						editableDevice: editableDevice,
						canvasSize: canvasSize,
						selectedControlId: $selectedControlId,
						draggingControlId: $draggingControlId,
						gridStep: gridStep,
						showBadges: showBadges
					)
					
					// Visual-only overlay stays in canvas space
					if let sel = selectedControlBinding, isEditingRegion {
						ForEach(sel.wrappedValue.regions.indices, id: \.self) { idx in
							RegionOverlay(
								rect: Binding(
									get: { sel.wrappedValue.regions[idx].rect },
									set: { updateRegionRect(of: sel, to: $0, idx: idx) }
								),
								canvasSize: canvasSize,
								gridStep: gridStep,
								minRegion: minRegion,
								shape: sel.wrappedValue.regions[idx].shape,
								zoom: zoom
							)
						}
					}
				}
			},
			// Type-erase the overlay to AnyView so both branches match
			overlayContent: { parentSize, canvasSize, zoom, pan -> AnyView in
				if let sel = selectedControlBinding, isEditingRegion {
					return AnyView(
						ForEach(sel.wrappedValue.regions.indices, id: \.self) { idx in
							RegionHitLayer(
								rect: Binding(
									get: { sel.wrappedValue.regions[idx].rect },
									set: { updateRegionRect(of: sel, to: $0, idx: idx) }
								),
								parentSize: parentSize,
								canvasSize: canvasSize,
								zoom: zoom,
								pan: pan,
								isPanMode: isPanMode
							)
						}
					)
				}
				else {
					return AnyView(EmptyView())
				}
			},
			onDropString: { raw, localPoint, canvasSize in
				guard let type = ControlType(rawValue: raw) else { return false }
				let relX = max(0, min(1, localPoint.x / canvasSize.width))
				let relY = max(0, min(1, localPoint.y / canvasSize.height))
				let c = Control(name: type.displayName, type: type, x: relX, y: relY)
				// no snapping here
				editableDevice.device.controls.append(c)
				selectedControlId = c.id
				return true
			}
		)
#if os(macOS)
		.overlay(
			KeyCaptureLayer(
				selectedControlBinding: selectedControlBinding,
				isEditingRegion: isEditingRegion,
				coarseStep: gridStep,
				fineStep: gridStep / 2
			)
			.allowsHitTesting(false)
		)
#endif
	}

	// MARK: helpers
	private func computeAspectRatio() -> CGFloat {
		if editableDevice.device.type == .rack {
			let w: CGFloat = 19.0
			let h: CGFloat = 1.75 * CGFloat(editableDevice.device.rackUnits ?? 1)
			return w / h
		} else {
			let w: CGFloat = 1.5 * CGFloat(editableDevice.device.slotWidth ?? 1)
			let h: CGFloat = 5.25
			return w / h
		}
	}
	
	private var selectedControlBinding: Binding<Control>? {
		guard let id = selectedControlId,
			  let idx = editableDevice.device.controls.firstIndex(where: { $0.id == id }) else { return nil }
		return $editableDevice.device.controls[idx]
	}
	
	private func defaultRect(around c: Control) -> CGRect {
		let s = ImageRegion.defaultSize
		var r = CGRect(x: max(0, c.x - s * 0.5),
					   y: max(0, c.y - s * 0.5),
					   width: s, height: s)
		r.origin.x = min(r.origin.x, 1 - r.size.width)
		r.origin.y = min(r.origin.y, 1 - r.size.height)
		return r
	}
	
	private func updateRegionRect(of sel: Binding<Control>, to new: CGRect, idx: Int = 0) {
		var r = new
		// enforce min size
		r.size.width  = max(minRegion, r.size.width)
		r.size.height = max(minRegion, r.size.height)
		// clamp to canvas bounds
		r.origin.x = min(max(r.origin.x, 0), 1 - r.size.width)
		r.origin.y = min(max(r.origin.y, 0), 1 - r.size.height)
		
		var c = sel.wrappedValue
		if c.regions.indices.contains(idx) {
			// enforce square for circle shapes
			if c.regions[idx].shape == .circle {
				let s = min(r.size.width, r.size.height)
				r.size = CGSize(width: s, height: s)
			}
			c.regions[idx].rect = r
		} else {
			// seed new region if missing
			let shape: ImageRegionShape = .rect
			var newRegion = ImageRegion(rect: r, mapping: nil, shape: shape)
			if c.type == .concentricKnob && idx == 0 { newRegion.shape = .circle }
			if c.type == .concentricKnob && idx == 1 { newRegion.shape = .circle }
			if c.regions.count <= idx {
				c.regions.append(newRegion)
			} else {
				c.regions[idx] = newRegion
			}
		}
		sel.wrappedValue = c
	}
	
	private func snap(_ v: CGFloat) -> CGFloat {
		(v.clamped(to: 0...1) / gridStep).rounded() * gridStep
	}
}
