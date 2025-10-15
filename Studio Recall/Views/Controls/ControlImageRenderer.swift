//
//  ControlImageRenderer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif


#if DEBUG
private let LOG_ROTATE = false   // flip to false to silence
#else
private let LOG_ROTATE = false
#endif

// --- Region-edit preview toggle (flows from Faceplate/Editor) ---
private struct RegionEditingKey: EnvironmentKey { static let defaultValue: Bool = false }
extension EnvironmentValues {
	var isRegionEditing: Bool {
		get { self[RegionEditingKey.self] }
		set { self[RegionEditingKey.self] = newValue }
	}
}

struct ControlImageRenderer: View {
	@Binding var control: Control
	
	@State private var isDragging = false
	
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
						imagePixelSize: pixelSize,   // pixels, not NSImage.size
						mapping: region.mapping
					)
					
					Group {
						if !src.isNull, !src.isEmpty, let cropped = cg.cropping(to: src.integral) {
							
							// ----- Hi-DPI aware SwiftUI Image from CGImage -----
#if os(macOS)
							let scale = NSScreen.main?.backingScaleFactor ?? 2.0
#else
							let scale = UIScreen.main.scale
#endif
							let patchImage = Image(decorative: cropped, scale: scale, orientation: .up)
							
							// Region-local size/position in canvas points
							let regionW = region.rect.width  * canvasSize.width
							let regionH = region.rect.height * canvasSize.height
							let regionPosX = region.rect.midX * canvasSize.width
							let regionPosY = region.rect.midY * canvasSize.height
							
							GeometryReader { geo in
								ZStack {
									if region.useAlphaMask {
										// Layer 1: Stationary background faceplate (always visible)
										Image(nsImage: faceplate)
											.resizable()
											.interpolation(.high)
											.antialiased(true)
											.scaledToFill()
											.frame(width: canvasSize.width, height: canvasSize.height)
											.offset(
												x: -region.rect.midX * canvasSize.width + geo.size.width / 2,
												y: -region.rect.midY * canvasSize.height + geo.size.height / 2
											)

										// Layer 2: Rotating patch visible only where mask is white (pointer areas)
										if let maskData = region.alphaMaskImage,
										   let maskImage = NSImage(data: maskData) {
											let _ = print("🔄 Mask rotation mapping: \(region.mapping?.kind.rawValue ?? "nil"), control: \(control.type), stepIndex: \(control.stepIndex ?? -1), stepAngles: \(control.stepAngles?.description ?? "nil")")
											patchImage
												.resizable()
												.interpolation(.high)
												.antialiased(true)
												.scaledToFill()
												.mask {
													// Mask: white areas = show patch, black = hide patch
													// Our mask has white = pointer, so this shows patch only at pointer
													Image(nsImage: maskImage)
														.resizable()
														.interpolation(.high)
														.antialiased(true)
														.scaledToFill()
												}
												.modifier(
													VisualEffect(mapping: region.mapping,
																 control: control,
																 resolve: resolveControl,
																 region: region,
																 regionSize: geo.size,
																 regionIndex: idx)
												)
										}
									} else {
										// Normal rendering when not using alpha mask
										patchImage
											.resizable()
											.interpolation(.high)
											.antialiased(true)
											.scaledToFill()
											.modifier(
												VisualEffect(mapping: region.mapping,
															 control: control,
															 resolve: resolveControl,
															 region: region,
															 regionSize: geo.size,
															 regionIndex: idx)
											)
									}

									// ✅ Overlay text if dragging or flagged by double-click
									if isDragging || control.showLabel {
										Text(displayLabel(for: control))
											.font(.caption)
											.padding(4)
											.background(Color.black.opacity(0.7))
											.cornerRadius(4)
											.foregroundColor(.white)
											.offset(y: -40) // float above control
											.transition(.opacity)
									}
								}
								.mask {
									if region.mapping?.kind == .sprite {
										// For sprites (multiSwitch etc.), no mask — let lever extend
										Rectangle()
									} else if control.type == .concentricKnob,
											  let pair = concentricPairIndices(control.regions),
											  pair.outer == idx {
										let outerRectLocal = CGRect(origin: .zero, size: geo.size)
										let innerLocal = innerRectInOuterLocal(
											outer: region.rect,
											inner: control.regions[pair.inner].rect,
											regionSize: geo.size
										)
										DonutShape(outerRect: outerRectLocal, innerRect: innerLocal)
											.fill(style: FillStyle(eoFill: true))
									} else {
										// Keep normal region clipping for knobs, lights, etc.
										RegionClipShape(shape: region.shape, maskParams: region.maskParams)
											.frame(width: geo.size.width, height: geo.size.height)
									}
								}
							}
							.frame(width: regionW, height: regionH)
							.position(x: regionPosX, y: regionPosY)
							.compositingGroup()
							.contentShape(RegionClipShape(shape: region.shape, maskParams: region.maskParams))
							.id(renderKey(control, regionIndex: idx))
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
	
	private func displayLabel(for control: Control) -> String {
		switch control.type {
			case .steppedKnob:
				if let opts = control.options,
				   let idx = control.stepIndex,
				   idx < opts.count {
					return opts[idx]
				}
				return "\(control.stepIndex ?? 0)"
			case .multiSwitch:
				if let opts = control.options,
				   let idx = control.selectedIndex,
				   idx < opts.count {
					return opts[idx]
				}
				return "\(control.selectedIndex ?? 0)"
			case .knob:
				return String(format: "%.2f", control.value ?? 0)
			case .button, .litButton:
				return (control.isPressed ?? false) ? "On" : "Off"
			case .light:
				return (control.isPressed ?? false) ? "Lit" : "Dark"
			case .concentricKnob:
				return String(format: "Outer %.2f / Inner %.2f",
							  control.outerValue ?? 0,
							  control.innerValue ?? 0)
		}
	}

}

struct VisualEffect: ViewModifier {
	@Environment(\.isRegionEditing) private var isRegionEditing
	
	let mapping: VisualMapping?
	let control: Control
	let resolve: (UUID) -> Control?
	let region: ImageRegion
	let regionSize: CGSize
	let regionIndex: Int
	
	func body(content: Content) -> some View {
		if isRegionEditing {
			if LOG_ROTATE {
				print("[Rotate] SKIP (isRegionEditing) id=\(control.id) type=\(control.type) region=\(regionIndex)")
			}
			
			// While region editing, show the raw (unrotated/unmodified) patch
			return AnyView(content)
		}
		// 1) Apply mapping (or none) to produce a base view
		
		let effective: VisualMapping? = {
			if let m = mapping { return m }
			switch control.type {
				case .knob:
					return .rotate(min: -135, max: 135, pivot: .init(x: 0.5, y: 0.5), taper: .linear)
				case .concentricKnob:
					let pair = concentricPairIndices(control.regions)
					if pair?.outer == regionIndex {
						return control.outerMapping ?? .rotate(min: -135, max: 135, pivot: .init(x: 0.5, y: 0.5), taper: control.outerTaper ?? .linear)
					} else {
						return control.innerMapping ?? .rotate(min: -135, max: 135, pivot: .init(x: 0.5, y: 0.5), taper: control.innerTaper ?? .linear)
					}
				default:
					return nil
			}
		}()
		
		if LOG_ROTATE {
			if mapping == nil, let eff = effective {
				print("[Rotate] FALLBACK mapping id=\(control.id) type=\(control.type) region=\(regionIndex) kind=\(eff.kind) deg=[\(eff.degMin ?? -135), \(eff.degMax ?? 135)] pivot=\(eff.pivot?.debugString ?? "nil")")
			} else {
				print("[Rotate] USING mapping id=\(control.id) type=\(control.type) region=\(regionIndex) kind=\(String(describing: mapping?.kind))")
			}
		}
		
		let base: AnyView = {
			guard let mapping = effective else { return AnyView(content) }
			
			switch mapping.kind {
				// MARK: rotate
				case .rotate:
					let pivot = mapping.pivot ?? CGPoint(x: 0.5, y: 0.5)
					
					let angle: Double = {
						switch control.type {
							case .knob:
								return mapping.rotationDegrees(for: control)
								
							case .steppedKnob:
								if let steps = control.stepAngles,
								   let idx = control.stepIndex,
								   steps.indices.contains(idx) {
									let ang = steps[idx]
									if LOG_ROTATE { print("[Rotate] stepped \(control.name) idx=\(idx) deg=\(ang.rounded1)") }
									return ang
								} else {
									let count   = control.stepAngles?.count
									?? control.stepValues?.count
									?? control.options?.count
									?? 1
									let maxIdx  = max(count - 1, 1)
									let idx     = min(max(control.stepIndex ?? 0, 0), maxIdx)
									let t       = Double(idx) / Double(maxIdx)
									let a0      = mapping.degMin ?? -135
									let a1      = mapping.degMax ??  135
									let ang     = a0 + (a1 - a0) * t
									if LOG_ROTATE { print("[Rotate] stepped (fallback) \(control.name) idx=\(idx)/\(maxIdx) t=\(t.rounded3) deg=\(ang.rounded1)") }
									return ang
								}
								
							case .multiSwitch:
								if let list = control.optionAngles,
								   let idx = control.selectedIndex,
								   list.indices.contains(idx) {
									let ang = list[idx]
									if LOG_ROTATE { print("[Rotate] switch \(control.name) idx=\(idx) deg=\(ang)") }
									return ang
								} else {
									let count   = control.optionAngles?.count
									?? control.options?.count
									?? 1
									let maxIdx  = max(count - 1, 1)
									let idx     = min(max(control.selectedIndex ?? 0, 0), maxIdx)
									let t       = Double(idx) / Double(maxIdx)
									let a0      = mapping.degMin ?? 0
									let a1      = mapping.degMax ?? 180
									let ang     = a0 + (a1 - a0) * t
									if LOG_ROTATE { print("[Rotate] switch (fallback) \(control.name) idx=\(idx)/\(maxIdx) t=\(t.rounded3) deg=\(ang.rounded1)") }
									return ang
								}
								
							case .concentricKnob:
								let pair = concentricPairIndices(control.regions)
								let isConcentricOuter = (control.type == .concentricKnob && pair?.outer == regionIndex)
								// Per-ring normalization (keep your existing behavior)
								if isConcentricOuter {
									return mapping.rotationDegrees(
										for: control.outerValue,
										lo: control.outerMin,
										hi: control.outerMax,
										taper: control.outerTaper ?? mapping.taper
									)
								} else {
									return mapping.rotationDegrees(
										for: control.innerValue,
										lo: control.innerMin,
										hi: control.innerMax,
										taper: control.innerTaper ?? mapping.taper
									)
								}
								
							default:
								return mapping.rotationDegrees(for: control)
						}
					}()
					
					return AnyView(
						content.rotationEffect(
							.degrees(angle),
							anchor: UnitPoint(x: pivot.x, y: pivot.y)
						)
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
					
				case .sprite:
					let logicalIndex = control.selectedIndex ?? control.stepIndex ?? 0
					let frameIndex = control.frameMapping?[logicalIndex] ?? logicalIndex
					
					let resolvedIndex: Int = {
						if let map = mapping.spriteIndices, frameIndex < map.count {
							return map[frameIndex]
						}
						if let map = mapping.spriteIndices, map.count >= 2 {
							let isPressed = control.isPressed ?? false
							return isPressed ? map[1] : map[0]
						}
						return frameIndex
					}()
					
					return AnyView(
						GeometryReader { geo in
							if let image = spriteCGImage(for: resolvedIndex, mapping: mapping, layout: control.spriteLayout) {
								
								// Sprite hinge (within the sprite itself)
								let spriteAnchor = UnitPoint(
									x: mapping.spritePivot?.x ?? 0.5,
									y: mapping.spritePivot?.y ?? 0.5
								)
								
								// Region hinge (where it should sit in the cropped patch)
								let controlAnchor = CGPoint(
									x: (mapping.pivot?.x ?? 0.5) * geo.size.width,
									y: (mapping.pivot?.y ?? 0.5) * geo.size.height
								)
								
								let offset = (mapping.spriteOffsets?.indices.contains(resolvedIndex) == true) ? mapping.spriteOffsets![resolvedIndex] : .zero
								let dx = -offset.x * regionSize.width //geo.size.width
								let dy = -offset.y * regionSize.height //geo.size.height
								
//								let _ = print("""
//	🎨 Sprite Render Debug:
//	- resolvedIndex = \(resolvedIndex)
//	- geo.size = \(geo.size)
//	- spriteAnchor = \(spriteAnchor)
//	- controlAnchor = \(controlAnchor)
//	- offset = \(offset) → (\(dx), \(dy))
//	""")
								
								Image(decorative: image, scale: 1.0)
									.resizable()
									.scaledToFill() //t()
									.rotationEffect(
										.degrees(Double(mapping.spriteQuarterTurns ?? 0) * 90.0),
										anchor: spriteAnchor
									)
//									.offset({
//										if let offsets = mapping.spriteOffsets, resolvedIndex < offsets.count {
//											let off = offsets[resolvedIndex]
//											return CGSize(width: off.x * geo.size.width,
//														  height: off.y * geo.size.height)
//										}
//										return .zero
//									}())
								// Move so sprite’s hinge aligns to region’s pivot
									.position(
										x: controlAnchor.x + dx,
										y: controlAnchor.y + dy
									)
									.frame(width: geo.size.width, height: geo.size.height)
							} else {
								let _ = print("❌ Failed to load sprite for index \(resolvedIndex)")
								EmptyView()
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

			// Use new brightness model if available
			let lampColor: Color
			if control.useMultiColor != true, let baseColor = control.ledColor {
				let brightness = lampOn ? (control.onBrightness ?? 1.0) : (control.offBrightness ?? 0.15)
				lampColor = baseColor.color.opacity(brightness)
			} else {
				// Fall back to legacy two-color system
				let onC  = (control.lampOnColor  ?? CodableColor(.green)).color
				let offC = (control.lampOffColor ?? CodableColor(.gray)).color
				lampColor = lampOn ? onC : offC
			}

			return AnyView(
				base.overlay(Rectangle().fill(lampColor).blendMode(.screen))
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
				let steps = c.options?.count ?? 1
				let maxIndex = max(steps - 1, 1)
				let idx = min(max(c.stepIndex ?? 0, 0), maxIndex)
				return Double(idx) / Double(maxIndex)
//				let idx = Double(c.stepIndex ?? 0)
//				let max = Double(max((c.options?.count ?? 1) - 1, 1))
//				return (idx / max).clamped(to: 0...1)
				
			case .multiSwitch:
				let steps = c.options?.count ?? 1
				let maxIndex = max(steps - 1, 1)
				let idx = min(max(c.selectedIndex ?? 0, 0), maxIndex)
				return Double(idx) / Double(maxIndex)
//				let idx = Double(c.selectedIndex ?? 0)
//				let max = Double(max((c.options?.count ?? 1) - 1, 1))
//				return (idx / max).clamped(to: 0...1)
				
			case .button, .light, .litButton:
				return booleanState(for: c, resolve: resolve) ? 1.0 : 0.0
				
			case .concentricKnob:
				let v = c.outerValue ?? 0
				return v.clamped(to: 0...1)

		}
	}
	
	private func spriteCGImage(
		for frameIndex: Int,
		mapping: VisualMapping,
		layout: Control.SpriteLayout
	) -> CGImage? {
		// 0. Library asset (preferred)
		if let assetId = mapping.spriteAssetId,
		   let cg = SpriteLibrary.shared.cgImage(forFrame: frameIndex, in: assetId) {
//			print("🎨 Rendering frame \(frameIndex) from SpriteLibrary asset \(assetId)")
			return cg
		}
		
		// 1. Embedded frames (legacy)
		if let frames = mapping.spriteFrames, frameIndex < frames.count {
#if os(iOS)
			if let uiImage = UIImage(data: frames[frameIndex]),
			   let cg = uiImage.cgImage {
//				print("🎨 Rendering frame \(frameIndex) from embedded spriteFrames")
				return cg
			}
#elseif os(macOS)
			if let nsImage = NSImage(data: frames[frameIndex]),
			   let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
//				print("🎨 Rendering frame \(frameIndex) from embedded spriteFrames")
				return cg
			}
#endif
//			print("⚠️ Failed to decode spriteFrames[\(frameIndex)]")
		}
		
		// 2. Embedded atlas (legacy)
#if os(iOS)
		guard
			let data = mapping.spriteAtlasPNG,
			let uiImage = UIImage(data: data),
			let atlas = uiImage.cgImage
		else {
//			print("⚠️ Could not decode spriteAtlasPNG (iOS)")
			return nil
		}
#elseif os(macOS)
		guard
			let data = mapping.spriteAtlasPNG,
			let nsImage = NSImage(data: data),
			let atlas = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
		else {
//			print("⚠️ Could not decode spriteAtlasPNG (macOS)")
			return nil
		}
#endif
		
		let cols = mapping.spriteCols ?? 1
		let rows = mapping.spriteRows ?? 1
		let frameWidth = atlas.width / cols
		let frameHeight = atlas.height / rows
		
		var rect: CGRect
		switch layout {
			case .vertical:
				let row = frameIndex % rows
				rect = CGRect(x: 0, y: row * frameHeight, width: frameWidth, height: frameHeight)
			case .horizontal:
				let col = frameIndex % cols
				rect = CGRect(x: col * frameWidth, y: 0, width: frameWidth, height: frameHeight)
		}
		
		if let cropped = atlas.cropping(to: rect) {
//			print("🎨 Cropped atlas frame \(frameIndex)")
			return cropped
		} else {
//			print("⚠️ Failed to crop atlas at rect \(rect)")
			return nil
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

		// Use new brightness model if available
		if c.useMultiColor != true, let baseColor = c.ledColor {
			let brightness = isOn ? (c.onBrightness ?? 1.0) : (c.offBrightness ?? 0.15)
			return baseColor.color.opacity(brightness)
		}

		// Fall back to legacy two-color system
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
	imagePixelSize: CGSize,   // use CGImage pixel size
	mapping: VisualMapping? = nil
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
		y: (localY / scale),
		width:  regCanvas.width  / scale,
		height: regCanvas.height / scale
	)
	
	// ✅ Add padding for sprites
	let padding: CGFloat = 0.5
	if mapping?.kind == .sprite {
		let padX = src.width * padding
		let padY = src.height * padding
		src = src.insetBy(dx: -padX, dy: -padY)
	}
	
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

private extension Double {
	var rounded1: String { String(format: "%.1f", self) }
	var rounded3: String { String(format: "%.3f", self) }
}
private extension CGPoint {
	var debugString: String { "(\(Double(x).rounded3), \(Double(y).rounded3))" }
}

// Pick outer/inner by area so order in the array can’t break us.
private func concentricPairIndices(_ regions: [ImageRegion]) -> (outer: Int, inner: Int)? {
	guard regions.count >= 2 else { return nil }
	let areas = regions.enumerated().map { (i, r) in (i, r.rect.width * r.rect.height) }
	let outer = areas.max(by: { $0.1 < $1.1 })!.0
	let inner = areas.min(by: { $0.1 < $1.1 })!.0
	return (outer, inner)
}

// Convert the inner rect into the local coords of the outer patch (used by the mask).
private func innerRectInOuterLocal(outer: CGRect, inner: CGRect, regionSize: CGSize) -> CGRect {
	// 'outer' & 'inner' are normalized (0…1) rects in canvas space.
	let ox = outer.minX, oy = outer.minY
	let ow = max(outer.width,  .leastNonzeroMagnitude)
	let oh = max(outer.height, .leastNonzeroMagnitude)
	return CGRect(
		x: (inner.minX - ox) / ow * regionSize.width,
		y: (inner.minY - oy) / oh * regionSize.height,
		width:  inner.width  / ow * regionSize.width,
		height: inner.height / oh * regionSize.height
	)
}
