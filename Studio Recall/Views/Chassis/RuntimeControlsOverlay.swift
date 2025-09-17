//
//  RuntimeControlsOverlay.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//
import SwiftUI
import AppKit

// MARK: - Runtime controls overlay (shared)
struct RuntimeControlsOverlay: View {
	@EnvironmentObject private var sessionManager: SessionManager
	
	@Environment(\.canvasZoom) private var zoom
	
	let device: Device
	@Binding var instance: DeviceInstance
	
	@State private var editingID: UUID? = nil
	@State private var editorText: String = ""
	@State private var scratchValue: ControlValue = .knob(0)
	@State private var hoveredControl: Control?
	@State private var bubbleVisibleFor: Control.ID? = nil
	@State private var hoverToken: UUID? = nil
	
	private let knobSensitivity: CGFloat = 1.0 / 240.0
	
	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .topLeading) {
				// live visual projection of instance state over the faceplate
				RuntimePatches(device: device, instance: $instance)
					.allowsHitTesting(false)
				
				ForEach(device.controls) { def in
					let frame = def.bounds(in: geo.size)
					let value = Binding<ControlValue>(
						get: {
							let inst = instance
							return inst.controlStates[def.id] ?? ControlValue.initialValue(for: def)
						},
						set: { newVal in
							var inst = instance
							inst.controlStates[def.id] = newVal
							instance = inst
							sessionManager.setControlValue(instanceID: instance.id, controlID: def.id, to: newVal)
						}
					)
					// Put the hit rect and bubble in the same local stack (share the same 0,0)
					ZStack(alignment: .topLeading) {
						// 1) hit rect (owns hover + gestures)
						controlHit(for: def, frame: frame, value: value, onHover: { inside in
							if inside {
								let token = UUID()
								hoverToken = token
								hoveredControl = def
								let f = def.bounds(in: geo.size)
//								print("🫧 schedule  \(def.name)  token=\(token)  frame=(\(Int(f.minX)),\(Int(f.minY)))  zoom=\(zoom)")
								DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
									if hoverToken == token { bubbleVisibleFor = def.id }
//									else { print("🫧 canceled  \(def.name)  (token mismatch)") }
								}
							} else if hoveredControl?.id == def.id {
//								print("🫧 HIDE      \(def.name)")
								hoveredControl = nil
								hoverToken = nil
								bubbleVisibleFor = nil
							}
						})
						.highPriorityGesture(TapGesture(count: 2).onEnded { editingID = def.id })
						
						if bubbleVisibleFor == def.id {
							// screen-pixel metrics @ 1x
							let bubblePxH: CGFloat = 26   // ↑ a bit taller
							let pxGap: CGFloat = 8        // ↑ a bit more gap
							let extraLiftPx: CGFloat = 6  // ↑ lift just a touch more
							let lift = (bubblePxH + pxGap + extraLiftPx) / max(zoom, 0.01)
							
							// flip below if we’d clip off the top
							let wouldClipTop = frame.minY - lift < 0
							let yOffset = wouldClipTop ? +lift : -lift
							
							// Center horizontally by using a full-width wrapper inside this local stack.
							// This stack’s local (0,0) is the control’s top-left.
							HStack {
								Spacer(minLength: 0)
								HoverBubbleView(def: def, instance: instance)
									.scaleEffect(1 / max(zoom, 0.01), anchor: .top) // keep size constant; anchor on vertical axis
									.allowsHitTesting(false)
									.zIndex(10_000)
								Spacer(minLength: 0)
							}
							.frame(width: frame.width)    // span the control’s width so Spacer() can center
							.offset(y: yOffset)           // move only vertically in local coords
						}
					}
					// Give the local stack the control’s size, then place it once
					.frame(width: frame.width, height: frame.height, alignment: .topLeading)
					.position(x: frame.midX, y: frame.midY)
						if editingID == def.id {
							InlineEditor(def: def,
										 value: value,
										 text: $editorText,
										 onClose: { editingID = nil })
							.position(x: frame.midX, y: frame.midY)
							.scaleEffect(1 / max(zoom, 0.01), anchor: .topLeading)
							.zIndex(10)
						}
				}
			}
		}
	}
	
	@ViewBuilder
	private func controlHit(for def: Control, frame: CGRect, value: Binding<ControlValue>, onHover: @escaping (Bool) -> Void) -> some View {
		let doubleTap = TapGesture(count: 2).onEnded {
			editorText = displayString(for: value.wrappedValue, control: def)
			editingID = def.id
		}
		
		switch def.type {
			case .knob:
				KnobHit(frame: frame, value: value, sensitivity: knobSensitivity, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .steppedKnob:
				SteppedKnobHit(frame: frame, value: value, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .multiSwitch:
				MultiSwitchHit(
					frame: frame,
					value: value,   // ✅ use original binding
					onHover: onHover,
					count: max(2, def.options?.count ?? def.optionAngles?.count ?? 2)
				)
				.highPriorityGesture(doubleTap)
				
			case .button:
				ButtonHit(frame: frame, value: value, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .concentricKnob:
				ConcentricKnobHit(frame: frame, value: value, sensitivity: knobSensitivity, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .litButton:
				LitButtonHit(frame: frame, value: value, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .light:
				Rectangle().fill(Color.clear)
					.frame(width: frame.width, height: frame.height)
					.contentShape(Rectangle())
					.highPriorityGesture(doubleTap)
		}
	}

	private func displayString(for v: ControlValue, control def: Control) -> String {
		switch v {
			case .knob(let u):
				let abs = unitToAbsolute(u, lo: def.knobMin, hi: def.knobMax, taper: def.regions.first?.mapping?.taper)
				return String(format: "%.3f", abs)
			case .steppedKnob(let i): return "\(i)"
			case .multiSwitch(let i): return "\(i)"
			case .button(let b): return b ? "1" : "0"
			case .light(let b): return b ? "1" : "0"
			case .concentricKnob(let o, let i):
				let oAbs = unitToAbsolute(o, lo: def.outerMin, hi: def.outerMax, taper: def.outerTaper)
				let iAbs = unitToAbsolute(i, lo: def.innerMin, hi: def.innerMax, taper: def.innerTaper)
				return String(format: "%.3f, %.3f", oAbs, iAbs)
			case .litButton(let p): return "\(p ? 1 : 0)"
		}
	}
}

// MARK: - Hover Bubble with control values
private struct HoverBubbleView: View {
	let lines: [String]
	
	init(def: Control, instance: DeviceInstance) {
		self.lines = def.displayLines(for: instance)   // ← canonical call
	}
	
	init(lines: [String]) {
		self.lines = lines
	}
	
	var body: some View {
		VStack(spacing: 3) {
			ForEach(lines, id: \.self) { line in
				Text(line)
					.font(.caption.monospacedDigit())
					.lineLimit(1)
					.fixedSize(horizontal: true, vertical: true)
					.minimumScaleFactor(0.9)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 6, style: .continuous)
				.stroke(.white.opacity(0.18), lineWidth: 1)
		}
		.foregroundStyle(.white)
		.shadow(radius: 8, y: 3)
		.accessibilityHidden(false)
		.accessibilityLabel(Text(lines.joined(separator: ", ")))
	}
}

// MARK: - Inline editor (tiny, constant pixel size)
private struct InlineEditor: View {
	let def: Control
	@Binding var value: ControlValue
	@Binding var text: String   // unused now; kept to match your call site
	var onClose: () -> Void
	
	@Environment(\.canvasZoom) private var canvasZoom
	@FocusState private var focused: Bool
	
	// Local absolute-value buffers
	@State private var absVal: Double = 0
	@State private var stepIndex: Int = 0
	@State private var multiIndex: Int = 0
	@State private var outerAbs: Double = 0
	@State private var innerAbs: Double = 0
	
	var body: some View {
		Group {
			switch def.type {
				case .knob:
					let lo = resolved(def.knobMin, 0), hi = resolved(def.knobMax, 1)
					VStack(alignment: .leading, spacing: 6) {
						HStack(spacing: 8) {
							Slider(value: $absVal, in: lo...hi)
							Text(String(format: "%.2f", absVal))
								.font(.caption.monospacedDigit())
								.frame(width: 48, alignment: .trailing)
						}
						HStack {
							Spacer()
							Button("OK") { commitKnob(lo: lo, hi: hi) }
								.keyboardShortcut(.defaultAction)
						}
					}
					.onAppear {
						let u = (value.asKnob ?? 0)
						let taper = def.regions.first?.mapping?.taper
						absVal = unitToAbsolute(u, lo: def.knobMin, hi: def.knobMax, taper: taper)
					}
					
				case .steppedKnob:
					let count = max(1, def.stepAngles?.count ?? def.stepValues?.count ?? 0)
					VStack(spacing: 6) {
						Stepper("Step \(stepIndex + 1) of \(count)", value: $stepIndex, in: 0...max(0, count-1))
						HStack { Spacer(); Button("OK") { value = .steppedKnob(stepIndex); onClose() } }
					}
					.onAppear { stepIndex = value.asStep ?? 0 }
					
				case .multiSwitch:
					let count = max(2, def.options?.count ?? def.optionAngles?.count ?? 2)
					VStack(spacing: 6) {
						Stepper("Pos \(multiIndex + 1) of \(count)", value: $multiIndex, in: 0...max(1, count-1))
						HStack { Spacer(); Button("OK") { value = .multiSwitch(multiIndex); onClose() } }
					}
					.onAppear { multiIndex = value.asMulti ?? 0 }
					
				case .button:
					VStack(spacing: 6) {
						Toggle("Pressed", isOn: Binding(get: { value.asBool ?? false },
														set: { value = .button($0) }))
						.toggleStyle(.switch)
						HStack { Spacer(); Button("OK") { onClose() } }
					}
					
				case .light:
					VStack(spacing: 6) {
						Toggle("Lit",
							   isOn: Binding(
								get: { value.asLight ?? false },
								set: { value = .light($0) }
							   )
						)
						.toggleStyle(.switch)
						HStack { Spacer(); Button("OK") { onClose() } }
					}

				case .litButton:
					VStack(spacing: 6) {
						Toggle("Pressed",
							   isOn: Binding(
								get: { value.asPressed ?? false },
								set: { pressed in
									// keep current lamp bit (if present in ControlValue)
									value = .litButton(isPressed: pressed)
								}
							   )
						)
						.toggleStyle(.switch)
						
						HStack { Spacer(); Button("OK") { onClose() } }
					}
					
				case .concentricKnob:
					let oLo = resolved(def.outerMin, 0), oHi = resolved(def.outerMax, 1)
					let iLo = resolved(def.innerMin, 0), iHi = resolved(def.innerMax, 1)
					VStack(alignment: .leading, spacing: 6) {
						Text("Outer").font(.caption2).foregroundStyle(.secondary)
						HStack(spacing: 8) {
							Slider(value: $outerAbs, in: oLo...oHi)
							Text(String(format: "%.2f", outerAbs))
								.font(.caption.monospacedDigit())
								.frame(width: 48, alignment: .trailing)
						}
						Text("Inner").font(.caption2).foregroundStyle(.secondary)
						HStack(spacing: 8) {
							Slider(value: $innerAbs, in: iLo...iHi)
							Text(String(format: "%.2f", innerAbs))
								.font(.caption.monospacedDigit())
								.frame(width: 48, alignment: .trailing)
						}
						HStack { Spacer(); Button("OK") { commitConcentric(oLo: oLo, oHi: oHi, iLo: iLo, iHi: iHi) } }
					}
					.onAppear {
						let oU = value.asOuter ?? 0
						let iU = value.asInner ?? 0
						outerAbs = unitToAbsolute(oU, lo: def.outerMin, hi: def.outerMax, taper: def.outerTaper)
						innerAbs = unitToAbsolute(iU, lo: def.innerMin, hi: def.innerMax, taper: def.innerTaper)
					}
			}
		}
		.padding(8)
		.frame(width: 220)
		.background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12)))
		.scaleEffect(1 / max(canvasZoom, 0.01)) // constant pixel size
		.shadow(radius: 4)
		.focused($focused)
		.onAppear { DispatchQueue.main.async { focused = true } }
		.onExitCommand { onClose() } // Esc to dismiss
	}
	
	private func commitKnob(lo: Double, hi: Double) {
		let u = (hi == lo) ? 0 : (absVal - lo) / (hi - lo)
		value = .knob(max(0, min(1, u)))
		onClose()
	}
	private func commitConcentric(oLo: Double, oHi: Double, iLo: Double, iHi: Double) {
		let ou = (oHi == oLo) ? 0 : (outerAbs - oLo) / (oHi - oLo)
		let iu = (iHi == iLo) ? 0 : (innerAbs - iLo) / (iHi - iLo)
		value = .concentricKnob(outer: max(0, min(1, ou)), inner: max(0, min(1, iu)))
		onClose()
	}
}

// MARK: - Per-type hit views (each stores per-gesture start)
private struct KnobHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let sensitivity: CGFloat
	let onHover: (Bool) -> Void
	@State private var start: Double?
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.highPriorityGesture(
				DragGesture(minimumDistance: 0)
					.onChanged { g in
						if start == nil { start = (value.asKnob ?? 0.5) }
						let v = clamp01((start ?? 0.5) - Double(g.translation.height) * Double(sensitivity))
						value = .knob(v)
					}
					.onEnded { _ in start = nil }
				, including: .all
			)
	}
}

private struct SteppedKnobHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (Bool) -> Void
	@State private var start: Int?
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.highPriorityGesture(
				DragGesture(minimumDistance: 0)
					.onChanged { g in
						if start == nil { start = (value.asStep ?? 0) }
						let d = Int(round(-g.translation.height / 12.0))
						value = .steppedKnob(max(0, (start ?? 0) + d))
					}
					.onEnded { _ in start = nil }
				, including: .all
			)
	}
}

private struct MultiSwitchHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (Bool) -> Void
	let count: Int
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.onTapGesture {
				let cur = (value.asMulti ?? 0)
				let next = (cur + 1) % max(1, count)
				value = .multiSwitch(next)
			}
	}
}

private struct ButtonHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (Bool) -> Void
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.onTapGesture {
				value = .button(!(value.asBool ?? false))
			}
	}
}

private struct LitButtonHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (Bool) -> Void
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.onTapGesture {
				let p = !(value.asPressed ?? false)
				value = .litButton(isPressed: p)
			}
	}
}

private struct ConcentricKnobHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let sensitivity: CGFloat
	let onHover: (Bool) -> Void
	@State private var startOuter: Double?
	@State private var startInner: Double?
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover(perform: onHover)
			.highPriorityGesture(
				DragGesture(minimumDistance: 0)
					.onChanged { g in
						if startOuter == nil { startOuter = (value.asOuter ?? 0.5) }
						if startInner == nil { startInner = (value.asInner ?? 0.5) }
						let o = clamp01((startOuter ?? 0.5) - Double(g.translation.height) * Double(sensitivity))
						let i = clamp01((startInner ?? 0.5) + Double(g.translation.width)  * Double(sensitivity))
						value = .concentricKnob(outer: o, inner: i)
					}
					.onEnded { _ in startOuter = nil; startInner = nil }
				, including: .all
			)
	}
}

// MARK: - Visual projector (instance → absolute → ControlImageRenderer)
struct RuntimePatches: View {
	let device: Device
	@Binding var instance: DeviceInstance
	
	var body: some View {
		GeometryReader { geo in
			let faceplate: NSImage? = device.imageData.flatMap { NSImage(data: $0) }
			ZStack {
				ForEach(device.controls) { def in
					let proxy = projectedControl(def: def, state: instance.controlStates[def.id])
					
					ForEach(Array(proxy.regions.enumerated()), id: \.0) { idx, region in
						ControlImageRenderer(
							control: .constant(proxy),
							faceplate: faceplate,
							canvasSize: geo.size,
							resolveControl: { id in
								let d = device.controls.first(where: { $0.id == id })
								return d.map { projectedControl(def: $0, state: instance.controlStates[id]) }
							},
							onlyRegionIndex: idx
						)
//						.frame(
//							width:  region.rect.width  * geo.size.width,
//							height: region.rect.height * geo.size.height
//						)
//						.position(
//							x: region.rect.midX * geo.size.width,
//							y: region.rect.midY * geo.size.height
//						)
						.compositingGroup()
						.mask { RegionClipShape(shape: region.shape) }
						.allowsHitTesting(false)
					}
				}
			}
		}
	}
}

// MARK: - Mapping helpers
fileprivate func resolved(_ b: Bound?, _ def: Double) -> Double { b?.resolve(default: def) ?? def }
fileprivate func unitToAbsolute(_ uIn: Double, lo: Bound?, hi: Bound?, taper: ValueTaper?) -> Double {
	let u = max(0, min(1, uIn))
	switch taper ?? .linear {
		case .linear:
			let a = resolved(lo, 0), b = resolved(hi, 1)
			return a + (b - a) * u
		case .decibel:
			let minDb = resolved(lo, -120), maxDb = resolved(hi, 0)
			let rMin = pow(10.0, minDb / 20.0)
			let rMax = pow(10.0, maxDb / 20.0)
			let r = rMin + (rMax - rMin) * u
			return 20.0 * log10(max(r, 1e-12))
	}
}

fileprivate func projectedControl(def: Control, state: ControlValue?) -> Control {
	var c = def
	switch (def.type, state) {
		case (.knob, .knob(let u)?):
			let taper = def.regions.first?.mapping?.taper
			c.value = unitToAbsolute(u, lo: def.knobMin, hi: def.knobMax, taper: taper)
		case (.steppedKnob, .steppedKnob(let idx)?):
			c.stepIndex = idx
		case (.multiSwitch, .multiSwitch(let idx)?):
			c.selectedIndex = idx
		case (.button, .button(let on)?):
			c.isPressed = on
		case (.litButton, .litButton(let p)?):
			c.isPressed = p
		case (.concentricKnob, .concentricKnob(let ou, let iu)?):
			c.outerValue = unitToAbsolute(ou, lo: def.outerMin, hi: def.outerMax, taper: def.outerTaper)
			c.innerValue = unitToAbsolute(iu, lo: def.innerMin, hi: def.innerMax, taper: def.innerTaper)
		default: break
	}
	return c
}

// MARK: - ControlValue helpers
private extension ControlValue {
	var asKnob: Double? { if case .knob(let v) = self { return v } else { return nil } }
	var asStep: Int? { if case .steppedKnob(let i) = self { return i } else { return nil } }
	var asBool: Bool? { if case .button(let b) = self { return b } else { return nil } }
	var asMulti: Int? { if case .multiSwitch(let i) = self { return i } else { return nil } }
	var asPressed: Bool? { if case .litButton(let p) = self { return p } else { return nil } }
	var asLight: Bool? { if case .light(let b) = self { return b } else { return nil } }
	var asOuter: Double? { if case .concentricKnob(let o, _) = self { return o } else { return nil } }
	var asInner: Double? { if case .concentricKnob(_, let i) = self { return i } else { return nil } }
}

// MARK: - Min helpers
@inline(__always) private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
