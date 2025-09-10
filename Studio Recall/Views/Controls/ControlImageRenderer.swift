//
//  ControlImageRenderer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI

struct ControlImageRenderer: View {
	@Binding var control: Control
	let faceplate: NSImage?
	let canvasSize: CGSize
	/// Resolver to look up other controls (for status light linkage)
	var resolveControl: (UUID) -> Control?
	var onlyRegionIndex: Int? = nil
	
	var body: some View {
		// If we have an image region + faceplate, render the photo patch with effects
		if let faceplate, !control.regions.isEmpty {
			// decide which regions to render
			let items: [(Int, ImageRegion)] = {
				if let i = onlyRegionIndex, control.regions.indices.contains(i) {
					return [(i, control.regions[i])]
				} else {
					return Array(control.regions.enumerated())
				}
			}()
			
			// Get the CGImage once so we know true pixel dimensions
			if let cg = faceplate.cgImage(forProposedRect: nil, context: nil, hints: nil) {
				let pixelSize = CGSize(width: cg.width, height: cg.height)
				
				ForEach(items, id: \.0) { idx, region in
					let src = sourceCropRectForVisibleRegion(
						regionNorm: region.rect,
						canvasSize: canvasSize,
						imagePixelSize: pixelSize   // pixels, not NSImage.size
					)
					
					Group {
						if !src.isNull, !src.isEmpty, let cropped = cg.cropping(to: src.integral) {
							let patch = NSImage(
								cgImage: cropped,
								size: NSSize(width: src.width, height: src.height)
							)
							
							let stateKey = controlStateKey(control)   // recompute per pass
							
							GeometryReader { geo in
								Image(nsImage: patch)
									.resizable()
									.interpolation(.high)
									.scaledToFill()      // fills the region’s frame
									.clipped()
									.modifier(
										VisualEffect(mapping: region.mapping,
													 control: control,
													 resolve: resolveControl,
													 region: region,
													 regionSize: geo.size,
													 regionIndex: idx)
									)
							}
							.id(renderKey(control, regionIndex: idx)) // <<— force this subtree to refresh when value/step/index changes
						} else {
							EmptyView()
						}
					}
				}
			} else {
				EmptyView()
			}
		} else {
			ControlView(control: $control)
				.frame(width:  ImageRegion.defaultSize * canvasSize.width,
					   height: ImageRegion.defaultSize * canvasSize.height)
		}
	}

	private func rectInPixels(from normalized: CGRect) -> CGRect {
		CGRect(x: normalized.origin.x * canvasSize.width,
			   y: normalized.origin.y * canvasSize.height,
			   width: normalized.size.width * canvasSize.width,
			   height: normalized.size.height * canvasSize.height)
	}
}

struct VisualEffect: ViewModifier {
	let mapping: VisualMapping?
	let control: Control
	let resolve: (UUID) -> Control?
	let region: ImageRegion
	let regionSize: CGSize
	let regionIndex: Int
	
	func body(content: Content) -> some View {
		// 1) Apply mapping (or none) to produce a base view
		let base: AnyView = {
			guard let mapping = mapping else { return AnyView(content) }
			
			switch mapping.kind {
				case .rotate:
					let pivot = mapping.pivot ?? CGPoint(x: 0.5, y: 0.5)
					let angle: Double = {
						if control.type == .steppedKnob,
						   let a = control.stepAngles, let i = control.stepIndex, i < a.count {
							return a[i]
						}
						if control.type == .multiSwitch,
						   let a = control.optionAngles, let i = control.selectedIndex, i < a.count {
							return a[i]
						}
						if control.type == .concentricKnob {
							if regionIndex == 0 {
								// Outer ring
								return mapping.rotationDegrees(
									for: control.outerValue,
									lo: control.outerMin,
									hi: control.outerMax,
									taper: control.outerTaper
								)
							} else {
								// Inner knob
								return mapping.rotationDegrees(
									for: control.innerValue,
									lo: control.innerMin,
									hi: control.innerMax,
									taper: control.innerTaper
								)
							}
						}

						return mapping.rotationDegrees(for: control)
					}()
					return AnyView(
						content.rotationEffect(.degrees(angle),
											   anchor: UnitPoint(x: pivot.x, y: pivot.y))
					)

				case .brightness:
					let on = booleanState(for: control, resolve: resolve)
					let r  = mapping.scalarRange ?? .init(lower: 0.0, upper: 0.6)
					let v  = on ? r.upper : r.lower
					return AnyView(content.brightness(v))
					
				case .opacity:
					let on = booleanState(for: control, resolve: resolve)
					let r  = mapping.scalarRange ?? .init(lower: 0.25, upper: 1.0)
					let v  = on ? r.upper : r.lower
					return AnyView(content.opacity(v))
					
					// ... inside VisualEffect.body, in the switch mapping.kind:
					
				case .translate:
					// translate within the cropped patch (region-local)
					return AnyView(
						GeometryReader { geo in
							let size = geo.size
							let t: Double = {
								if control.type == .multiSwitch {
									let steps = max(1, (control.options?.count ?? 1) - 1)
									return steps == 0 ? 0 : Double(control.selectedIndex ?? 0) / Double(steps)
								} else {
									return unitValue(for: control)
								}
							}()
							let start = mapping.transStart ?? .zero
							let end   = mapping.transEnd   ?? .zero
							let dx = CGFloat(start.x + (end.x - start.x) * t) * size.width
							let dy = CGFloat(start.y + (end.y - start.y) * t) * size.height
							content.offset(x: dx, y: dy)
						}
					)
					
				case .flip3D:
					// angle from explicit per-option tilts (preferred) or Min°/Max° fallback
					let tLinear: Double = {
						if control.type == .multiSwitch {
							let steps = max(1, (control.options?.count ?? 1) - 1)
							return steps == 0 ? 0 : Double(control.selectedIndex ?? 0) / Double(steps)
						} else {
							return unitValue(for: control)
						}
					}()
					
					let angle: Double = {
						if control.type == .multiSwitch, let i = control.selectedIndex,
						   let list = mapping.tiltByIndex, i < list.count {
							let ref = min(max(mapping.tiltRefIndex ?? 0, 0), list.count - 1)
							return list[i] - list[ref]           // reference pose = 0°
						}
						// 2-pos button support (optional)
						if control.type == .button, let list = mapping.tiltByIndex, list.count >= 2 {
							return (control.isPressed ?? false) ? list[1] : list[0]
						}
						// fallback curve
						let lo = mapping.tiltMin ?? -22
						let hi = mapping.tiltMax ??  22
						return lo + (hi - lo) * tLinear
					}()
					
					let axis = mapping.tiltAxis ?? .x
					let vector = (x: CGFloat(axis == .x ? 1 : 0),
								  y: CGFloat(axis == .y ? 1 : 0),
								  z: CGFloat(axis == .z ? 1 : 0))
					let anchor = UnitPoint(x: (mapping.pivot?.x ?? 0.5),
										   y: (mapping.pivot?.y ?? 0.85))
					let persp  = CGFloat(mapping.perspective ?? 0.6)
					
					let showGizmo = mapping.showGizmo ?? false
					let pivotPoint = mapping.pivot ?? CGPoint(x: 0.5, y: 0.85)
					
					return AnyView(
						ZStack {                            // <- compose first so the gizmo stays unrotated
							content
								.compositingGroup()
								.rotation3DEffect(.degrees(angle),
												  axis: vector,
												  anchor: anchor,
												  anchorZ: 0,
												  perspective: persp)
								.shadow(radius: 1, y: axis == .x ? (angle > 0 ? 1 : -1) : 0)
							
							if showGizmo {
								PivotGizmo(pivot: pivotPoint, axis: axis)
									.allowsHitTesting(false)
							}
						}
					)
					// in switch mapping.kind { case .sprite: ... }
				case .sprite:
					// 1) which frame?
					let frameIndex: Int = {
						if control.type == .multiSwitch {
							if let i = control.selectedIndex {
								if let map = mapping.spriteIndices, i < map.count { return map[i] }
								return i
							}
							return 0
						} else if control.type == .button {
							let pressed = control.isPressed ?? false
							if let map = mapping.spriteIndices, map.count >= 2 { return pressed ? map[1] : map[0] }
							return pressed ? 1 : 0
						} else { return 0 }
					}()
					
					// Prefer library; fall back to embedded atlas/frames
					var cgOpt: CGImage? = nil
					if let id = mapping.spriteAssetId {
						cgOpt = SpriteLibrary.shared.cgImage(forFrame: frameIndex, in: id)
					}
					if cgOpt == nil {
						cgOpt = spriteCGImage(for: frameIndex, mapping: mapping)
					}
					guard let cg = cgOpt else {
						return AnyView(content) // nothing to draw yet
					}
					
					let sprite = Image(decorative: cg, scale: 1, orientation: .up)
					
					// 2) pivots + optional per-frame pivot/offset
					let asset = mapping.spriteAssetId.flatMap { SpriteLibrary.shared.asset($0) }
					let sPivot = (mapping.spritePivots?[safe: frameIndex])
					?? (mapping.spritePivot ?? asset?.spritePivot ?? CGPoint(x: 0.5, y: 0.9))
					let rPivot = mapping.pivot ?? CGPoint(x: 0.5, y: 0.88)
					let perOffset = (mapping.spriteOffsets?[safe: frameIndex]) ?? .zero
					let scale = CGFloat(mapping.spriteScale ?? (asset?.defaultScale ?? 1.0))
					
					let turns = (mapping.spriteQuarterTurns ?? 0) % 4
					let angleDeg = Double(turns * 90)
					
					return AnyView(
						GeometryReader { geo in
							let H = geo.size.height
							let sprH = H * scale
							let rawAspect = CGFloat(cg.width) / CGFloat(cg.height)
							// If rotated 90°/270°, swap aspect so the bounding frame matches the turned image
							let effAspect = (turns % 2 == 0) ? rawAspect : 1.0 / rawAspect
							let sprW = sprH * effAspect
							
							let anchorX = rPivot.x * geo.size.width
							let anchorY = rPivot.y * geo.size.height
							let posX = anchorX - (sPivot.x * sprW) + sprW/2 + perOffset.x * geo.size.width
							let posY = anchorY - (sPivot.y * sprH) + sprH/2 + perOffset.y * geo.size.height
							
							ZStack {
								content
								sprite
									.resizable()
									.interpolation(.high)
									.frame(width: sprW, height: sprH)
									.rotationEffect(.degrees(angleDeg),
													anchor: UnitPoint(x: sPivot.x, y: sPivot.y))
									.position(x: posX, y: posY)
							}
						}
					)
			}
		}()
		
		// 2) Post-effect for buttons: pressed look (scale + slight darken + lift shadow)
		if control.type == .button {
			let pressed = booleanState(for: control, resolve: resolve)
			return AnyView(
				base
					.scaleEffect(pressed ? 0.96 : 1.0, anchor: .center)
					.brightness(pressed ? -0.08 : 0.0)
					.shadow(radius: pressed ? 0 : 2, y: pressed ? 0 : 1)
			)
		}
		
		// Tint lights with their current effective color
		if control.type == .light {
			let color = effectiveLightColor(for: control, resolve: resolve)
			return AnyView(
				base
				// Screen-like blend so the patch glows the chosen color
					.overlay(Rectangle().fill(color).blendMode(.screen))
			)
		}
		
		// Treat lit buttons similarly to lights
		if control.type == .litButton {
			let lampOn = (control.lampOverrideOn ?? (control.lampFollowsPress ?? true ? control.isPressed ?? false : false))
			let onC  = (control.lampOnColor  ?? CodableColor(.green)).color
			let offC = (control.lampOffColor ?? CodableColor(.gray)).color
			return AnyView(
				base.overlay(Rectangle().fill(lampOn ? onC : offC).blendMode(.screen))
			)
		}

		// 3) No post-effect → return the mapped content
		return base
	}

	// Map various control types to 0...1
	private func unitValue(for c: Control) -> Double {
		switch c.type {
			case .knob:
				let v = c.value ?? 0
				let minV = c.knobMin?.resolve(default: 0) ?? 0
				let maxV = c.knobMax?.resolve(default: 1) ?? 1
				if maxV <= minV { return 0 }       // avoid /0
				return ((v - minV) / (maxV - minV)).clamped(to: 0...1)
				
			case .steppedKnob:
				let idx = Double(c.stepIndex ?? 0)
				let max = Double(max((c.options?.count ?? 1) - 1, 1))
				return (idx / max).clamped(to: 0...1)
				
			case .multiSwitch:
				let idx = Double(c.selectedIndex ?? 0)
				let max = Double(max((c.options?.count ?? 1) - 1, 1))
				return (idx / max).clamped(to: 0...1)
				
			case .button, .light, .litButton:
				return booleanState(for: c, resolve: resolve) ? 1.0 : 0.0
				
			case .concentricKnob:
				let v = c.outerValue ?? 0
				return v.clamped(to: 0...1)

		}
	}
	
	// Resolve on/off — supports linkTarget for .light
	private func booleanState(for c: Control, resolve: (UUID) -> Control?) -> Bool {
		var base: Bool
		switch c.type {
			case .button, .litButton: base = c.isPressed ?? false
			case .light:
				if let target = c.linkTarget, let other = resolve(target) {
					base = booleanState(for: other, resolve: resolve)
				} else {
					base = c.isPressed ?? false
				}
			case .knob, .concentricKnob: base = (c.value ?? 0) > 0.5
			case .steppedKnob:
				let idx = c.stepIndex ?? 0
				base = idx > 0
			case .multiSwitch:
				base = (c.selectedIndex ?? 0) > 0
				
		}
		return (c.linkInverted ?? false) ? !base : base
	}
	
	private func effectiveLightColor(for c: Control, resolve: (UUID) -> Control?) -> Color {
		// Decide ON/OFF using link target (including multiswitch + linkOnIndex) and inversion.
		var isOn: Bool = c.isPressed ?? false
		if let targetId = c.linkTarget, let target = resolve(targetId) {
			switch target.type {
				case .button:
					isOn = target.isPressed ?? false
				case .multiSwitch:
					let want = c.linkOnIndex ?? 0
					isOn = (target.selectedIndex ?? 0) == want
				default:
					break
			}
		}
		if c.linkInverted ?? false { isOn.toggle() }
		let onC  = (c.onColor  ?? CodableColor(.green)).color
		let offC = (c.offColor ?? CodableColor(.gray)).color
		return isOn ? onC : offC
	}
	
	private func spriteCGImage(for index: Int, mapping: VisualMapping) -> CGImage? {
		// frames mode takes precedence
		if mapping.spriteMode == .frames, let frames = mapping.spriteFrames, index < frames.count {
			if let ns = NSImage(data: frames[index])?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
				return ns
			}
		}
		// atlas fallback (your existing code)
		if let data = mapping.spriteAtlasPNG,
		   let ns = NSImage(data: data),
		   let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil),
		   let cols = mapping.spriteCols, let rows = mapping.spriteRows, cols > 0, rows > 0
		{
			let fw = cg.width / cols, fh = cg.height / rows
			let clamped = max(0, min(index, cols*rows - 1))
			let col = clamped % cols, row = clamped / cols
			let crop = CGRect(x: col * fw, y: (rows - 1 - row) * fh, width: fw, height: fh)
			return cg.cropping(to: crop)
		}
		return nil
	}

}

private struct PivotGizmo: View {
	let pivot: CGPoint        // 0…1 within the cropped patch
	let axis: VisualMapping.Axis3D
	
	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width, h = geo.size.height
			let px = CGFloat(pivot.x) * w
			let py = CGFloat(pivot.y) * h
			
			// hairline strokes
			let hair: CGFloat = max(1, min(2, min(w, h) / 160))
			
			// crosshair + hinge line
			ZStack {
				// hinge direction line
				Path { p in
					switch axis {
						case .x: // up/down hinge → vertical hinge line
							p.move(to: CGPoint(x: px, y: py - h))
							p.addLine(to: CGPoint(x: px, y: py + h))
						case .y: // left/right hinge → horizontal hinge line
							p.move(to: CGPoint(x: px - w, y: py))
							p.addLine(to: CGPoint(x: px + w, y: py))
						case .z:
							// rare for flip; show both to hint it's the center
							p.move(to: CGPoint(x: px, y: py - h))
							p.addLine(to: CGPoint(x: px, y: py + h))
							p.move(to: CGPoint(x: px - w, y: py))
							p.addLine(to: CGPoint(x: px + w, y: py))
					}
				}
				.stroke(Color.black.opacity(0.25), lineWidth: hair)
				
				// crosshair
				Path { p in
					let s: CGFloat = 10
					p.move(to: CGPoint(x: px - s, y: py))
					p.addLine(to: CGPoint(x: px + s, y: py))
					p.move(to: CGPoint(x: px, y: py - s))
					p.addLine(to: CGPoint(x: px, y: py + s))
				}
				.stroke(.white, lineWidth: hair)
				.overlay(
					Path { p in
						let s: CGFloat = 10
						p.move(to: CGPoint(x: px - s, y: py))
						p.addLine(to: CGPoint(x: px + s, y: py))
						p.move(to: CGPoint(x: px, y: py - s))
						p.addLine(to: CGPoint(x: px, y: py + s))
					}
						.stroke(.black.opacity(0.8), lineWidth: hair/2)
				)
				
				// pivot dot
				Circle()
					.fill(.white)
					.overlay(Circle().stroke(.black, lineWidth: hair))
					.frame(width: 6, height: 6)
					.position(x: px, y: py)
			}
		}
	}
}

/// Convert a 0–1 canvas-space rect to a source-image crop,
/// accounting for the faceplate being drawn `.scaledToFit` (letterboxed).
private func sourceCropRectForVisibleRegion(
	regionNorm: CGRect,
	canvasSize: CGSize,
	imagePixelSize: CGSize   // use CGImage pixel size
) -> CGRect {
	// Scale from *pixels* to canvas points (same factor used to draw the background image)
	let scale = min(canvasSize.width  / imagePixelSize.width,
					canvasSize.height / imagePixelSize.height)
	
	// Letterboxed image rect in canvas points
	let visSize = CGSize(width: imagePixelSize.width * scale,
						 height: imagePixelSize.height * scale)
	let visRect = CGRect(
		x: (canvasSize.width  - visSize.width)  * 0.5,
		y: (canvasSize.height - visSize.height) * 0.5,
		width: visSize.width, height: visSize.height
	)
	
	// Region in canvas points
	let regCanvas = CGRect(
		x: regionNorm.minX * canvasSize.width,
		y: regionNorm.minY * canvasSize.height,
		width:  regionNorm.width  * canvasSize.width,
		height: regionNorm.height * canvasSize.height
	)
	
	// Visible-local (canvas pts)
	let localX = regCanvas.minX - visRect.minX
	let localY = regCanvas.minY - visRect.minY
	
	// Convert to pixel crop & flip Y for CGImage space
	var src = CGRect(
		x: localX / scale,
//		y: (imagePixelSize.height) - ((localY / scale) + (regCanvas.height / scale)),
		y: (localY / scale),
		width:  regCanvas.width  / scale,
		height: regCanvas.height / scale
	)
	
	// Clamp to image bounds
	let bounds = CGRect(origin: .zero, size: imagePixelSize)
	src = src.intersection(bounds)
	return (src.isNull || src.isEmpty) ? .null : src
}

// Force the image patch subtree to refresh when the control's *semantic* state changes.
// (Keeps the canvas in sync when you tweak Value/Index/etc. in the Inspector.)
private func controlStateKey(_ c: Control) -> String {
	switch c.type {
		case .knob:
			return "knob:\(c.value ?? -1)"
			
		case .steppedKnob:
			return "stepped:\(c.stepIndex ?? -1)"
			
		case .multiSwitch:
			return "switch:\(c.selectedIndex ?? -1)"
			
		case .button:
			return "button:\(c.isPressed ?? false ? 1 : 0)"
			
		case .light:
			// Lights can follow links; without the Device here we key off isPressed only.
			// (If you want live updates when a linked target flips, we can thread Device into this view.)
			return "light:\(c.isPressed ?? false ? 1 : 0)"
			
		case .concentricKnob:
			// Include both rings so either ring change refreshes the patch.
			return "concentric:\(c.outerValue ?? -1):\(c.innerValue ?? -1)"
			
		case .litButton:
			// Include press + common link fields so lamp changes will refresh when local state changes.
			// (Again, if it follows a different control via linkTarget, we can extend this later.)
			return "lit:\(c.isPressed ?? false ? 1 : 0):\(c.lampOverrideOn ?? false ? 1 : 0):\(c.linkInverted ?? false ? 1 : 0):\(c.linkOnIndex ?? -1)"
	}
}

private func renderKey(_ c: Control, regionIndex i: Int) -> String {
	switch c.type {
		case .knob:
			return "knob:\(c.value ?? -1)"
		case .steppedKnob:
			return "step:\(c.stepIndex ?? -1)"
		case .multiSwitch:
			return "ms:\(c.selectedIndex ?? -1)"
		case .button, .light, .litButton:
			return "btn:\(c.isPressed ?? false)"
		case .concentricKnob:
			// differentiate outer vs inner by region index
			let outer = c.outerValue ?? -1
			let inner = c.innerValue ?? -1
			return "ck:\(i):\(outer):\(inner)"
	}
}

private extension CGRect { var nonEmpty: CGRect? { isNull || isEmpty ? nil : self } }

// convenience (file-local)
private extension Array {
	subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}
