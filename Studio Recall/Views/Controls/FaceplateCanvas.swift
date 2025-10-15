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
	@Binding var activeRegionIndex: Int
	@Binding var zoom: CGFloat
	@Binding var pan: CGSize
	@Binding var zoomFocusN: CGPoint?
	@Binding var activeSidebarTab: ControlSidebarTab
	
	var renderStyle: RenderStyle = .photoreal
	
	// Optional external overlay (parent-space), e.g. detection boxes.
	// Signature matches CanvasViewport.overlayContent.
	var externalOverlay: ((CGSize /*parent*/, CGSize /*canvas*/, CGFloat /*zoom*/, CGSize /*pan*/) -> AnyView)? = nil
	
	// local state just for canvas content
	@State private var draggingControlId: UUID? = nil
	@Binding var selectedShapeInstanceId: UUID?
	
	// tuning
	private let gridStep: CGFloat = 0.005   // Less strict snapping
	private let minRegion: CGFloat = 0.002  // Smaller minimum size
	
	// Callback
	var onNewControlDropped: ((UUID) -> Void)? = nil
	
	var body: some View {
		let aspect = computeAspectRatio()
		let showBadges = !(isEditingRegion || draggingControlId != nil || activeSidebarTab == .inspector)
		
		CanvasViewport(
			aspect: aspect,
			zoom: $zoom,
			pan: $pan,
			focusN: $zoomFocusN,
			content: { canvasSize in
				ZStack {
					if renderStyle == .photoreal {
						CanvasContent(
							editableDevice: editableDevice,
							canvasSize: canvasSize,
							selectedControlId: $selectedControlId,
							draggingControlId: $draggingControlId,
							gridStep: gridStep,
							showBadges: showBadges
						)
						
						// Live preview of control patches (rotate/translate/flip/sprites) in the editor
						let faceplate = editableDevice.device.imageData.flatMap { NSImage(data: $0) }
						
						ForEach(editableDevice.device.controls.indices, id: \.self) { i in
							let control = editableDevice.device.controls[i]
							
							ForEach(Array(control.regions.enumerated()), id: \.0) { idx, region in
								ControlImageRenderer(
									control: $editableDevice.device.controls[i],
									faceplate: faceplate,
									canvasSize: canvasSize,
									resolveControl: { id in
										editableDevice.device.controls.first(where: { $0.id == id })
									},
									onlyRegionIndex: idx
								)
								.compositingGroup()
								.mask { 
									RegionClipShape(
										shape: region.shape,
										shapeInstances: region.shapeInstances.isEmpty ? nil : region.shapeInstances,
										maskParams: region.maskParams
									)
								}
								.allowsHitTesting(false)
								.id(editableDevice.device.controls[i].renderKey)
							}
						}
					} else {
						// Representative face (same look as Session)
						RepresentativeFaceplate(device: editableDevice.device, size: canvasSize)
							.frame(width: canvasSize.width, height: canvasSize.height)
							.allowsHitTesting(false)

						// Live glyphs + labels + selection highlight
						RepresentativeGlyphs(
							device: editableDevice.device,
							instance: .constant(.empty(for: editableDevice.device)),
							faceSize: canvasSize,
							selectedId: selectedControlId
						)
//						RepresentativeEditorPreview(device: editableDevice.device, canvasSize: canvasSize)
//						.allowsHitTesting(false)
					}

					if !isEditingRegion {
						let hits: [ControlHitOverlay.Hit] = editableDevice.device.controls.flatMap { c in
							c.regions.map { r in ControlHitOverlay.Hit(controlId: c.id, rect: r.rect) }
						}
						ControlHitOverlay(canvasSize: canvasSize, hits: hits, selectedControlId: $selectedControlId)
					}


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
								zoom: zoom,
								controlType: sel.wrappedValue.type,
								regionIndex: idx,
								regions: sel.wrappedValue.regions,
								maskParams: sel.wrappedValue.regions[idx].maskParams
							)
							
							// Shape instance overlays for the active region
							if activeRegionIndex == idx {
								ForEach(sel.wrappedValue.regions[idx].shapeInstances.indices, id: \.self) { shapeIdx in
									let shapeInstance = sel.wrappedValue.regions[idx].shapeInstances[shapeIdx]
									if selectedShapeInstanceId == shapeInstance.id {
										ShapeInstanceOverlay(
											shapeInstance: shapeInstance,
											regionRect: sel.wrappedValue.regions[idx].rect,
											canvasSize: canvasSize,
											zoom: zoom
										)
									}
								}
							}
						}
					}
				}
				.id(renderStyle)
				.transaction { $0.animation = nil }
			},
			// Type-erase the overlay to AnyView so both branches match
			overlayContent: { parentSize, canvasSize, zoom, pan -> AnyView in
				AnyView(
					ZStack(alignment: .topLeading) {
						// Existing region edit overlay (unchanged)
						if let sel = selectedControlBinding, isEditingRegion {
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
									isPanMode: isPanMode,
									shape: sel.wrappedValue.regions[idx].shape,
									maskParams: sel.wrappedValue.regions[idx].maskParams,
									controlType: sel.wrappedValue.type,
									regionIndex: idx,
									regions: sel.wrappedValue.regions,
									isEnabled: activeRegionIndex == idx
								)
								
								// Shape instance hit layers for the active region
								if activeRegionIndex == idx {
									ForEach(sel.wrappedValue.regions[idx].shapeInstances.indices, id: \.self) { shapeIdx in
										let shapeInstance = sel.wrappedValue.regions[idx].shapeInstances[shapeIdx]
										let isSelected = selectedShapeInstanceId == shapeInstance.id
										ShapeInstanceHitLayer(
											shapeInstance: Binding(
												get: { sel.wrappedValue.regions[idx].shapeInstances[shapeIdx] },
												set: { newValue in
													var control = sel.wrappedValue
													control.regions[idx].shapeInstances[shapeIdx] = newValue
													sel.wrappedValue = control
												}
											),
											regionRect: sel.wrappedValue.regions[idx].rect,
											parentSize: parentSize,
											canvasSize: canvasSize,
											zoom: zoom,
											pan: pan,
											isPanMode: isPanMode,
											isEnabled: isSelected,
											onSelect: {
												selectedShapeInstanceId = shapeInstance.id
											}
										)
									}
								}
							}
						}
						
						// NEW: external overlay (e.g. detection boxes) in parent-space
						if let externalOverlay {
							externalOverlay(parentSize, canvasSize, zoom, pan)
								.allowsHitTesting(false)
						}
					}
						.allowsHitTesting(isEditingRegion)
				)
			},
			onDropString: { raw, localPoint, canvasSize in
				guard let type = ControlType(rawValue: raw) else { return false }
				let relX = max(0, min(1, localPoint.x / canvasSize.width))
				let relY = max(0, min(1, localPoint.y / canvasSize.height))
				let c = Control(name: type.displayName, type: type, x: relX, y: relY)
	
				// no snapping here
				editableDevice.device.controls.append(c)
				selectedControlId = c.id
				onNewControlDropped?(c.id)
				return true
			}
		)
		.environment(\.isRegionEditing, isEditingRegion)
		.onChange(of: selectedControlId) { _, newId in
			if let id = newId,
			   let idx = editableDevice.device.controls.firstIndex(where: { $0.id == id }) {
				editableDevice.device.controls[idx].ensureConcentricRegions()
			}
		}

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
			let w: CGFloat = DeviceMetrics.bodyInches(for: editableDevice.device.rackWidth) // 19 / 8.5 / 5.5
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
		// min size
		r.size.width  = max(minRegion, r.size.width)
		r.size.height = max(minRegion, r.size.height)
		// clamp to canvas 0…1
		r.origin.x = min(max(r.origin.x, 0), 1 - r.size.width)
		r.origin.y = min(max(r.origin.y, 0), 1 - r.size.height)
		
		var c = sel.wrappedValue
		if c.regions.indices.contains(idx) {
			// NO aspect enforcement here
			c.regions[idx].rect = r
		} else {
			let fallbackShape = c.regions.first?.shape ?? .circle
			c.regions.append(ImageRegion(rect: r, mapping: nil, shape: fallbackShape))
		}
		sel.wrappedValue = c
	}


	private func snap(_ v: CGFloat) -> CGFloat {
		(v.clamped(to: 0...1) / gridStep).rounded() * gridStep
	}
}

private struct ControlHitOverlay: View {
	struct Hit: Identifiable {
		let id = UUID()
		let controlId: UUID
		let rect: CGRect   // normalized (0…1)
	}
	let canvasSize: CGSize
	let hits: [Hit]
	@Binding var selectedControlId: UUID?
	
	var body: some View {
		ZStack {
			ForEach(hits) { h in
				Color.clear
					.frame(width:  h.rect.width  * canvasSize.width,
						   height: h.rect.height * canvasSize.height)
					.position(x: h.rect.midX * canvasSize.width,
							  y: h.rect.midY * canvasSize.height)
					.contentShape(Rectangle())
					.onTapGesture { selectedControlId = h.controlId }
			}
		}
	}
}

// MARK: - Representative View
// Minimal editor shim that renders the full representative faceplate + glyphs
private struct RepresentativeEditorPreview: View {
	let device: Device
	let canvasSize: CGSize
	
	var body: some View {
		ZStack {
			// The same plate background you use elsewhere
			RepresentativeFaceplate(device: device, size: canvasSize)
			
			// Controls as vector glyphs
			ForEach(device.controls) { c in
				// Use first region if present, otherwise a sensible 8% default around (x,y)
				let r = c.regions.first?.rect
				?? CGRect(x: c.x - 0.04, y: c.y - 0.04, width: 0.08, height: 0.08)
				
				let frame = CGRect(
					x: r.minX * canvasSize.width,
					y: r.minY * canvasSize.height,
					width:  r.width  * canvasSize.width,
					height: r.height * canvasSize.height
				)
				
				RepresentativeGlyphForEditor(control: c)
					.frame(width: frame.width, height: frame.height)
					.position(x: frame.midX, y: frame.midY)
			}
		}
		.frame(width: canvasSize.width, height: canvasSize.height)
	}
}

private struct EditorRepOverlay: View {
	@Binding var device: Device
	let canvasSize: CGSize
	
	var body: some View {
		ZStack {
			ForEach(device.controls) { c in
				let r = c.regions.first?.rect ?? CGRect(x: c.x - 0.04, y: c.y - 0.04, width: 0.08, height: 0.08)
				let frame = CGRect(
					x: r.minX * canvasSize.width,
					y: r.minY * canvasSize.height,
					width:  r.width * canvasSize.width,
					height: r.height * canvasSize.height
				)
				
				RepresentativeGlyphForEditor(control: c)
					.frame(width: frame.width, height: frame.height)
					.position(x: frame.midX, y: frame.midY)
			}
		}
	}
}

// Super-light wrapper that uses Control’s own value/stepIndex/selectedIndex.
private struct RepresentativeGlyphForEditor: View {
	let control: Control
	var body: some View {
		switch control.type {
			case .knob:
				KnobGlyphCanonical(
					t: control.normalizedValue ?? 0.5,
					startDeg: control.repStartDeg ?? -225, // top-arc default
					sweepDeg: control.repSweepDeg ?? 270
				)
			case .steppedKnob:
				let idx = control.stepIndex ?? 0
				let count = max(2, control.options?.count ?? (control.stepAngles?.count ?? 0))
				if count == 2 {
					BinarySquareGlyph(isOn: idx == 1)
				} else {
					SteppedGlyph(index: idx, count: count)
				}
			case .multiSwitch:
				let idx = control.selectedIndex ?? 0
				let count = max(2, control.options?.count ?? 2)
				if count == 2 {
					BinarySquareGlyph(isOn: idx == 1)
				} else {
					SwitchGlyph(index: idx, count: count)
				}
			case .button:
				BinarySquareGlyph(isOn: control.isPressed ?? false)
			case .light:
				let isOn = control.isPressed ?? false
				let onCol = control.lampOnColor?.color ?? control.ledColor?.color ?? control.onColor?.color ?? .green
				let offCol = control.lampOffColor?.color ?? control.offColor?.color ?? .white.opacity(0.15)
				LightGlyph(isOn: isOn, onColor: onCol, offColor: offCol)
			case .concentricKnob:
				ConcentricGlyphCanonical(
					outer: control.outerValueNormalized ?? 0.5,
					inner: control.innerValueNormalized ?? 0.5,
					startDeg: control.repStartDeg ?? -225,
					sweepDeg: control.repSweepDeg ?? 270
				)
			case .litButton:
				let isOn = control.isPressed ?? false
				let color = (isOn ? control.onColor : control.offColor)?.color ?? .green
				LitButtonGlyph(isOn: isOn, color: color)
		}
	}
}
