//
//  RuntimeControlsOverlay.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Runtime controls overlay (shared)
struct RuntimeControlsOverlay: View {
	@EnvironmentObject private var sessionManager: SessionManager
	
	@Environment(\.canvasZoom) private var zoom
	@Environment(\.renderStyle) private var renderStyle
	
	let device: Device
	@Binding var instance: DeviceInstance
	let prelayout: SlotPrelayout?
	let faceMetrics: FaceRenderMetrics?
	
	@State private var editingID: UUID? = nil
	@State private var editorText: String = ""
	@State private var scratchValue: ControlValue = .knob(0)
	@State private var hoveredControl: Control?
	@State private var hoveredPreviewText: String? = nil
	@State private var bubbleVisibleFor: Control.ID? = nil
	@State private var hoverToken: UUID? = nil
	@State private var patchesNonce: Int = 0
	
	private let knobSensitivity: CGFloat = 1.5 / 240.0
	
	// Small helpers to reduce type-checking load
	
	private func valueBinding(for def: Control) -> Binding<ControlValue> {
		Binding<ControlValue>(
			get: { instance.controlStates[def.id] ?? ControlValue.initialValue(for: def) },
			set: { newVal in
				let oldVal = instance.controlStates[def.id]
				if def.type == .multiSwitch {
					print("🔧 MultiSwitch '\(def.name)' (ID: \(def.id.uuidString.prefix(8)))")
					print("   Old: \(oldVal?.asMulti ?? -1)")
					print("   New: \(newVal.asMulti ?? -1)")
				}
				instance.controlStates[def.id] = newVal
				sessionManager.setControlValue(instanceID: instance.id, controlID: def.id, to: newVal)
				patchesNonce &+= 1
			}
		)
	}
	
	private func hoverLines(for def: Control) -> [String] {
		if renderStyle == .photoreal {
			return def.displayEntries(for: instance).map { $0.text }
		}
		if hoveredControl?.id == def.id, let s = hoveredPreviewText, !s.isEmpty {
			return [s]
		} else {
			return def.displayEntries(for: instance).map { $0.text }
		}
	}
	
	private func bubbleOffsetY(for frame: CGRect) -> CGFloat {
		// screen-pixel metrics @ 1x
		let bubblePxH: CGFloat = 26
		let pxGap: CGFloat     = 8
		let extraLiftPx: CGFloat = 6
		let lift = (bubblePxH + pxGap + extraLiftPx) / max(zoom, 0.01)
		let wouldClipTop = frame.minY - lift < 0
		return wouldClipTop ? +lift : -lift
	}
	
	@ViewBuilder
	private func controlCell(def: Control, fm: FaceRenderMetrics) -> some View {
		let frame = def.bounds(in: fm.size)
		let value = valueBinding(for: def)
		
		// Local stack that owns hit rect + bubble (same local 0,0)
		ZStack(alignment: .topLeading) {
			controlHit(for: def, frame: frame, value: value) { info in
				if info.inside {
					let token = UUID()
					hoverToken = token
					hoveredControl = def
					hoveredPreviewText = info.previewText
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
						if hoverToken == token { bubbleVisibleFor = def.id }
					}
				} else if hoveredControl?.id == def.id {
					hoveredControl = nil
					hoverToken = nil
					hoveredPreviewText = nil
					bubbleVisibleFor = nil
				}
			}
			.highPriorityGesture(TapGesture(count: 2).onEnded { editingID = def.id })
			
			if bubbleVisibleFor == def.id {
				HStack {
					Spacer(minLength: 0)
					HoverBubbleView(lines: hoverLines(for: def))
						.scaleEffect(1 / max(zoom, 0.01), anchor: .top)
						.allowsHitTesting(false)
						.zIndex(10_000)
					Spacer(minLength: 0)
				}
				.frame(width: frame.width)
				.offset(y: bubbleOffsetY(for: frame))
			}
		}
		.frame(width: frame.width, height: frame.height, alignment: .topLeading)
		.position(x: frame.midX, y: frame.midY)
		
		// Inline editor as a sibling so it doesn’t complicate the ZStack builder
		if editingID == def.id {
			InlineEditor(def: def, value: value, text: $editorText, onClose: { editingID = nil })
				.position(x: frame.midX, y: frame.midY)
				.frame(minWidth: 220)
				.fixedSize()
				.zIndex(20_000)
		}
	}

	var body: some View {
		GeometryReader { geo in
			let faceW = prelayout?.faceWidthPts ?? geo.size.width
			let slotH = prelayout?.heightPts    ?? geo.size.height
			
			let fm: FaceRenderMetrics = faceMetrics
			?? DeviceMetrics.faceRenderMetrics(
				faceWidthPts: faceW,
				slotHeightPts: slotH,
				imageData: device.imageData
			)
			
			ZStack(alignment: .topLeading) {
				// live visual projection of instance state over the faceplate
				if renderStyle == .photoreal {
					RuntimePatches(device: device, instance: $instance)
						.frame(width: fm.size.width, height: fm.size.height)
						.allowsHitTesting(false)
				} else {
					RepresentativeGlyphs(device: device, instance: $instance, faceSize: fm.size, selectedId: nil)
						.allowsHitTesting(false)
				}
				
//				ForEach(device.controls, id: \.id) { def in
//					let frame = def.bounds(in: fm.size)
//					
//					let value = Binding<ControlValue>(
//						get: { return instance.controlStates[def.id] ?? ControlValue.initialValue(for: def) },
//						set: { newVal in
////							var inst = instance
////							inst.controlStates[def.id] = newVal
////							instance = inst
//							instance.controlStates[def.id] = newVal
//							sessionManager.setControlValue(instanceID: instance.id, controlID: def.id, to: newVal)
//						}
//					)
//					// Put the hit rect and bubble in the same local stack (share the same 0,0)
//					ZStack(alignment: .topLeading) {
//						// 1) hit rect (owns hover + gestures)
//						controlHit(for: def, frame: frame, value: value, onHover: { info in
//							if info.inside {
//								let token = UUID()
//								hoverToken = token
//								hoveredControl = def
////								let f = def.bounds(in: geo.size)
////								print("🫧 schedule  \(def.name)  token=\(token)  frame=(\(Int(f.minX)),\(Int(f.minY)))  zoom=\(zoom)")
//								hoveredPreviewText = info.previewText
//								DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
//									if hoverToken == token { bubbleVisibleFor = def.id }
////									else { print("🫧 canceled  \(def.name)  (token mismatch)") }
//								}
//							} else if hoveredControl?.id == def.id {
////								print("🫧 HIDE      \(def.name)")
//								hoveredControl = nil
//								hoverToken = nil
//								hoveredPreviewText = nil
//								bubbleVisibleFor = nil
//							}
//						})
//						.highPriorityGesture(TapGesture(count: 2).onEnded { editingID = def.id })
//						
//						if bubbleVisibleFor == def.id {
//							// screen-pixel metrics @ 1x
//							let bubblePxH: CGFloat = 26   // ↑ a bit taller
//							let pxGap: CGFloat = 8        // ↑ a bit more gap
//							let extraLiftPx: CGFloat = 6  // ↑ lift just a touch more
//							let lift = (bubblePxH + pxGap + extraLiftPx) / max(zoom, 0.01)
//							
//							// flip below if we’d clip off the top
//							let wouldClipTop = frame.minY - lift < 0
//							let yOffset = wouldClipTop ? +lift : -lift
//							
//							// Center horizontally by using a full-width wrapper inside this local stack.
//							// This stack’s local (0,0) is the control’s top-left.
//							HStack {
//								Spacer(minLength: 0)
//								let lines: [String]
//								if let preview = hoveredPreviewText, !preview.isEmpty {
//									lines = [preview]
//								} else {
//									lines = def.displayEntries(for: instance).map { $0.text }
//								}
//								HoverBubbleView(lines: lines)
//									.scaleEffect(1 / max(zoom, 0.01), anchor: .top) // keep size constant; anchor on vertical axis
//									.allowsHitTesting(false)
//									.zIndex(10_000)
//								Spacer(minLength: 0)
//							}
//							.frame(width: frame.width)    // span the control’s width so Spacer() can center
//							.offset(y: yOffset)           // move only vertically in local coords
//						}
//					}
//					// Give the local stack the control’s size, then place it once
//					.frame(width: frame.width, height: frame.height, alignment: .topLeading)
//					.position(x: frame.midX, y: frame.midY)
//					
//						if editingID == def.id {
//							InlineEditor(def: def,
//										 value: value,
//										 text: $editorText,
//										 onClose: { editingID = nil })
//							.position(x: frame.midX, y: frame.midY)
//							.frame(minWidth: 220)
//							.fixedSize()
//							.zIndex(20_000)
//						}
//				}
				ForEach(device.controls, id: \.id) { def in
					controlCell(def: def, fm: fm)
				}
			}
			.frame(width: fm.size.width, height: fm.size.height, alignment: .topLeading)
			.background(Color.clear.preference(key: HoverBubbleActiveKey.self,
											   value: bubbleVisibleFor != nil))
		}
		
	}
	
	@ViewBuilder
	private func controlHit(for def: Control, frame: CGRect, value: Binding<ControlValue>, onHover: @escaping (HoverInfo) -> Void) -> some View {
		let doubleTap = TapGesture(count: 2).onEnded {
			editorText = displayString(for: value.wrappedValue, control: def)
			editingID = def.id
		}
		
		switch def.type {
			case .knob:
				KnobHit(frame: frame, value: value, sensitivity: knobSensitivity, onHover: onHover)
					.highPriorityGesture(doubleTap)
				
			case .steppedKnob:
				SteppedKnobHit(
					frame: frame,
					value: value,
					onHover: onHover,
					count: max(1, def.stepAngles?.count ?? def.stepValues?.count ?? 0),
					isPhotoreal: renderStyle == .photoreal,
					angles: def.stepAngles,
					stepNames: def.options
				)
					.highPriorityGesture(doubleTap)
				
			case .multiSwitch:
				MultiSwitchHit(
					frame: frame,
					value: value,   // ✅ use original binding
					onHover: onHover,
					count: max(2, def.options?.count ?? def.optionAngles?.count ?? 2),
					isPhotoreal: renderStyle == .photoreal,
					angles: def.optionAngles,
					optionNames: def.options
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
	let entries: [ControlDisplayEntry]
	
	init(def: Control, instance: DeviceInstance) {
		self.entries = def.displayEntries(for: instance)
	}
	
	init(lines: [String]) {
		// back-compat initializer if you call it elsewhere
		self.entries = lines.map { ControlDisplayEntry(text: $0) }
	}
	
	var body: some View {
		VStack(spacing: 3) {
			ForEach(entries, id: \.self) { entry in
				HStack(spacing: 6) {
					if let symbol = entry.systemImage {
						Image(systemName: symbol)
							.font(.caption)
							.foregroundStyle(.white.opacity(0.9))
							.accessibilityHidden(true)
					}
					Text(entry.text)
						.font(.caption.monospacedDigit())
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: true)
						.minimumScaleFactor(0.9)
				}
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
		.accessibilityElement(children: .combine)
		.accessibilityLabel(Text(entries.map { $0.text }.joined(separator: ", ")))
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
	@State private var absVal:   Double = 0
	@State private var stepIndex:   Int = 0
	@State private var multiIndex:  Int = 0
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
	let onHover: (HoverInfo) -> Void
	@State private var start: Double?
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover { inside in onHover(HoverInfo(inside: inside, previewText: nil)) }
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
	let onHover: (HoverInfo) -> Void
	let count: Int
	let isPhotoreal: Bool
	let angles: [Double]?
	let stepNames: [String]?
	
	@State private var start: Int?
	@State private var clickDir: Int = 1
	@State private var optionClickDir: Int  = -1
	
	// geometry that matches RepresentativeGlyphs.SteppedGlyph
	private let dotD: CGFloat = 6
	private let spacing: CGFloat = 3
	private let topPad: CGFloat = 6
	
	private var hi: Int { max(0, count - 1) }
	private var current: Int { value.asStep ?? 0 }
	
	private func clamped(_ i: Int) -> Int { min(max(0, i), hi) }
	private func stepNormal() {
		if hi == 0 { return }
		if current >= hi { clickDir = -1 }
		if current <= 0  { clickDir =  1 }
		value = .steppedKnob(clamped(current + clickDir))
	}
	private func stepOption() {
		if hi == 0 { return }
		if current <= 0  { optionClickDir =  1 }
		if current >= hi { optionClickDir = -1 }
		value = .steppedKnob(clamped(current + optionClickDir))
	}
	
	// Representative dots layout → nearest index
	private func repDotIndex(at p: CGPoint, in size: CGSize) -> Int {
		let totalW = CGFloat(count) * dotD + CGFloat(max(0, count - 1)) * spacing
		let startX = (size.width - totalW) * 0.5 + dotD * 0.5
		let cy = topPad + dotD * 0.5
		var bestI = 0
		var bestD = CGFloat.greatestFiniteMagnitude
		for i in 0..<count {
			let cx = startX + CGFloat(i) * (dotD + spacing)
			let d = hypot(p.x - cx, p.y - cy)
			if d < bestD { bestD = d; bestI = i }
		}
		return bestI
	}
	
	var body: some View {
		GeometryReader { geo in
			Rectangle().fill(Color.clear)
				.contentShape(Rectangle())
				.background(Color.clear)
			
			// HOVER: photoreal shows current only; rep shows hovered dot’s user label
				.onContinuousHover { phase in
					switch phase {
						case .active(let loc):
							if isPhotoreal {
								onHover(HoverInfo(inside: true, previewText: nil))
							} else {
								let idx = repDotIndex(at: loc, in: geo.size)
								let name = (stepNames ?? [])[safe: idx] ?? "Step \(idx + 1)"
								onHover(HoverInfo(inside: true, previewText: name))
							}
						case .ended:
							onHover(HoverInfo(inside: false, previewText: nil))
					}
				}
			
			// GESTURE:
			//  • Photoreal: vertical drag steps; center click cycles.
			//  • Representative: ignore drag (no onChanged), only set on click to nearest dot.
				.highPriorityGesture(
					DragGesture(minimumDistance: 0)
						.onChanged { g in
							guard isPhotoreal else { return } // <- ignore drag in Rep
							if start == nil { start = current }
							let d = Int(round(-g.translation.height / 12.0))
							value = .steppedKnob(clamped((start ?? 0) + d))
						}
						.onEnded { g in
							defer { start = nil }
							let moved = abs(g.translation.height) + abs(g.translation.width)
							
#if os(macOS)
							let isOption = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
#else
							let isOption = false
#endif
							
							if moved < 3 {
								if isPhotoreal {
									if isOption { stepOption() } else { stepNormal() }
								} else {
									// Rep: single click → nearest dot only
									let idx = repDotIndex(at: g.location, in: geo.size)
									value = .steppedKnob(idx)
								}
							}
							// If it was an actual drag: do nothing in Rep; Photoreal already handled in onChanged.
						}
				)
		}
		.frame(width: frame.width, height: frame.height)
	}
}

private struct MultiSwitchHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (HoverInfo) -> Void
	let count: Int
	let isPhotoreal: Bool
	let angles: [Double]?           // unused now in Photo
	let optionNames: [String]?
	
	// geometry that matches RepresentativeGlyphs.SwitchGlyph
	private let dotW: CGFloat = 8
	private let spacing: CGFloat = 4
	private let topPad: CGFloat = 6
	
	private func centerIncDec(_ cur: Int) -> Int { (cur + 1) % max(1, count) }
	
	private func repDotIndex(at p: CGPoint, in size: CGSize) -> Int {
		let totalW = CGFloat(count) * dotW + CGFloat(max(0, count - 1)) * spacing
		let startX = (size.width - totalW) * 0.5 + dotW * 0.5
		let cy = topPad + dotW * 0.5
		var bestI = 0
		var bestD = CGFloat.greatestFiniteMagnitude
		for i in 0..<count {
			let cx = startX + CGFloat(i) * (dotW + spacing)
			let d = hypot(p.x - cx, p.y - cy)
			if d < bestD { bestD = d; bestI = i }
		}
		return bestI
	}
	
	@State private var hoverLocation: CGPoint?

	var body: some View {
		GeometryReader { geo in
			if isPhotoreal {
				// Photoreal mode: use DragGesture for center-click cycling
				Rectangle().fill(Color.clear)
					.contentShape(Rectangle())
					.background(Color.clear)
					.onContinuousHover { phase in
						switch phase {
						case .active:
							onHover(HoverInfo(inside: true, previewText: nil))
						case .ended:
							onHover(HoverInfo(inside: false, previewText: nil))
						}
					}
					.highPriorityGesture(
						DragGesture(minimumDistance: 0)
							.onEnded { g in
								let cx = geo.size.width  * 0.5
								let cy = geo.size.height * 0.5
								let dx = Double(g.location.x - cx)
								let dy = Double(g.location.y - cy)
								let dist = hypot(dx, dy)
								let centerThresh = Double(min(geo.size.width, geo.size.height)) * 0.22
								let cur = value.asMulti ?? 0

								if dist <= centerThresh {
									value = .multiSwitch(centerIncDec(cur))
								}
							}
					)
			} else {
				// Representative mode: use simple tap gesture
				Rectangle().fill(Color.clear)
					.contentShape(Rectangle())
					.background(Color.clear)
					.onContinuousHover { phase in
						switch phase {
						case .active(let loc):
							hoverLocation = loc
							let idx = repDotIndex(at: loc, in: geo.size)
							let name = (optionNames ?? [])[safe: idx] ?? "Pos \(idx + 1)"
							onHover(HoverInfo(inside: true, previewText: name))
						case .ended:
							hoverLocation = nil
							onHover(HoverInfo(inside: false, previewText: nil))
						}
					}
					.onTapGesture {
						let loc = hoverLocation ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
						let idx = repDotIndex(at: loc, in: geo.size)
						let cur = value.asMulti ?? 0

						// For binary switches (count=2), toggle instead of setting to clicked index
						if count == 2 {
							let newIdx = cur == 0 ? 1 : 0
							print("🎯 MultiSwitch TAP detected - TOGGLE mode: \(cur) → \(newIdx)")
							value = .multiSwitch(newIdx)
						} else {
							// For multi-position switches, set to clicked dot
							print("🎯 MultiSwitch TAP detected at idx=\(idx)")
							value = .multiSwitch(idx)
						}
					}
			}
		}
		.frame(width: frame.width, height: frame.height)
	}
}

private struct ButtonHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (HoverInfo) -> Void
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover { inside in onHover(HoverInfo(inside: inside, previewText: nil)) }
			.onTapGesture {
				value = .button(!(value.asBool ?? false))
			}
	}
}

private struct LitButtonHit: View {
	let frame: CGRect
	@Binding var value: ControlValue
	let onHover: (HoverInfo) -> Void
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover { inside in onHover(HoverInfo(inside: inside, previewText: nil)) }
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
	let onHover: (HoverInfo) -> Void
	@State private var startOuter: Double?
	@State private var startInner: Double?
	
	var body: some View {
		Rectangle().fill(Color.clear)
			.frame(width: frame.width, height: frame.height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.onHover { inside in onHover(HoverInfo(inside: inside, previewText: nil)) }
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

	@Environment(\.canvasLOD) private var lod

	var body: some View {
		GeometryReader { geo in
			// Apply LOD downsampling to the faceplate for control patches
			let faceplate: NSImage? = {
				guard let data = device.imageData, let nsimg = NSImage(data: data) else { return nil }
				let key = device.id.uuidString + "#" + String(data.count)
				let original = max(nsimg.size.width, nsimg.size.height)

				switch lod {
					case .full:
						return nsimg

					case .level1:
						// 1/2 resolution
						let target = original * 0.5
						return nsimg.lodImage(maxPixel: target, cacheKey: key) ?? nsimg

					case .level2:
						// 1/4 resolution
						let target = original * 0.25
						return nsimg.lodImage(maxPixel: target, cacheKey: key) ?? nsimg

					case .level3:
						// 1/8 resolution
						let target = original * 0.125
						return nsimg.lodImage(maxPixel: target, cacheKey: key) ?? nsimg

					// Legacy compatibility
					case .medium:
						// Redirect to level2 (1/4 resolution)
						let target = original * 0.25
						return nsimg.lodImage(maxPixel: target, cacheKey: key) ?? nsimg

					case .low:
						// Redirect to level3 (1/8 resolution)
						let target = original * 0.125
						return nsimg.lodImage(maxPixel: target, cacheKey: key) ?? nsimg
				}
			}()

			ZStack {
				ForEach(device.controls, id: \.id) { def in
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

// MARK: - Hover bubble z-order signal
struct HoverBubbleActiveKey: PreferenceKey {
	static var defaultValue: Bool = false
	static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct HoverInfo {
	var inside: Bool
	var previewText: String?
}

@inline(__always)
private func nearestIndex(forAngle deg: Double, in angles: [Double]) -> Int {
	func wrap(_ a: Double) -> Double {
		var x = a
		while x <= -180 { x += 360 }
		while x >   180 { x -= 360 }
		return x
	}
	var bestI = 0
	var bestD = Double.greatestFiniteMagnitude
	for (i, a) in angles.enumerated() {
		let d = abs(wrap(deg - a))
		if d < bestD { bestD = d; bestI = i }
	}
	return bestI
}

private extension Array {
	subscript(safe i: Int) -> Element? { (i >= 0 && i < count) ? self[i] : nil }
}
