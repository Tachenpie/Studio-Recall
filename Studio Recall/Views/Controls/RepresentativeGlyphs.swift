//
//  RepresentativeGlyphs.swift
//  Studio Recall
//
//  Created by True Jackie on 10/1/25.
//

import SwiftUI

//private let REP_KNOB_MIN_DEG: Double   = -240.0
//private let REP_KNOB_SWEEP_DEG: Double =  300.0
private let REP_KNOB_MIN_DEG: Double   = -225.0
private let REP_KNOB_SWEEP_DEG: Double =  270.0

struct RepresentativeGlyphs: View {
	@Environment(\.displayScale) private var displayScale

	let device: Device
	@Binding var instance: DeviceInstance
	let faceSize: CGSize

	let selectedId: UUID?

	@State private var renderNonce = 0

	// Precompute control frames in face space
	private var controlFrames: [(control: Control, frame: CGRect)] {
		let frames = device.controls.map { ($0, $0.bounds(in: faceSize)) }
		return frames
	}

	var body: some View {
		let labelPt = CGFloat(clamp(Double(faceSize.height) * 0.024, 9.0, 11.0))
		let lineH   = labelPt * 1.15
		let accent  = representativeAccentColor(for: device.name)

		let placed  = placeLabels(labelPt: labelPt, lineH: lineH)

		ZStack(alignment: .topLeading) {

			// Controls as lightweight glyphs (no labels inside)
			ForEach(controlFrames, id: \.control.id) { pair in
				let def   = pair.control
				let frame = pair.frame

				ZStack {
					glyph(for: def)
					if def.id == selectedId {
						RoundedRectangle(cornerRadius: 8, style: .continuous)
							.stroke(accent, lineWidth: 1.5)
							.shadow(radius: 1, y: 1)
							.padding(2)
					}
				}
				.frame(width: frame.width, height: frame.height)
				.position(x: frame.midX, y: frame.midY)
				.allowsHitTesting(false)
			}
			
			// Labels place with collision-avoidance
			ForEach(controlFrames, id: \.control.id) { pair in
				if let lp = placed[pair.control.id] {
					// pixel-snap
					let px = (lp.rect.midX * displayScale).rounded() / displayScale
					let py = (lp.rect.midY * displayScale).rounded() / displayScale
					Text(lp.text)
						.font(.system(size: labelPt, weight: .regular, design: .rounded))
						.foregroundStyle(lp.isAccent ? accent : .white.opacity(0.92))
						.lineLimit(1)
						.minimumScaleFactor(0.75)
						.allowsTightening(true)
						.frame(width: lp.rect.width, height: lp.rect.height) //, alignment: .center)
						.position(x: px, y: py)
						.allowsHitTesting(false)
				}
			}
		}
		.frame(width: faceSize.width, height: faceSize.height, alignment: .topLeading)
		.id(renderNonce)
		.onChange(of: instance.controlStates) { _, _ in
			renderNonce += 1
		}
	}
	
	// MARK: - Placement engine
	private struct LabelPlacement { let rect: CGRect; let text: String; let isAccent: Bool }
	
	private func placeLabels(labelPt: CGFloat, lineH: CGFloat) -> [UUID: LabelPlacement] {
		var result: [UUID: LabelPlacement] = [:]
		
		// Occupied zones start with all control glyph frames
		var occupied: [CGRect] = controlFrames.map { $0.frame.insetBy(dx: -2, dy: -2) }
		
		for (def, frame) in controlFrames {
			let defaultText  = def.name.isEmpty ? def.type.displayName : def.name
			var text = defaultText
			var accent = false
			
			switch def.type {
				case .multiSwitch:
					let count = max(2, def.options?.count ?? def.optionAngles?.count ?? 0)
					if count > 2 {
						let idx = instance.controlStates[def.id]?.asMulti ?? multiIndex(def)
						if let names = def.options, idx < names.count {
							text = "\(def.name): \(names[idx])"
						} else {
							text = "\(def.name): #\(idx)"
						}
						accent = true
					}
				case .steppedKnob:
					let count = max(2, def.stepValues?.count ?? def.stepAngles?.count ?? 0)
					if count > 2 {
						let idx = instance.controlStates[def.id]?.asStepped ?? steppedIndex(def)
						if let names = def.options, idx < names.count {
							text = "\(def.name): \(names[idx])"
						} else {
							text = "\(def.name): Step \(idx + 1)"
						}
						accent = true
					}
				default:
					break
			}
			
			let width = max(26, frame.width + 8)
			// Candidate rects (order: bottom, right, left, top)
			let bottom = CGRect(x: frame.midX - width/2, y: frame.maxY + 3, width: width, height: lineH)
			let right  = CGRect(x: frame.maxX + 4,       y: frame.midY - lineH/2, width: width, height: lineH)
			let left   = CGRect(x: frame.minX - 4 - width, y: frame.midY - lineH/2, width: width, height: lineH)
			let top    = CGRect(x: frame.midX - width/2, y: frame.minY - 3 - lineH, width: width, height: lineH)
			
			let candidates = [bottom, right, left, top]
			let chosen = candidates.first(where: { !intersectsAny($0, occupied) }) ?? bottom
			
			result[def.id] = LabelPlacement(rect: chosen, text: text, isAccent: accent)
			occupied.append(chosen)
		}
		return result
	}
	
	@ViewBuilder
	private func glyph(for def: Control) -> some View {
		switch def.type {
			case .knob:
				let instRaw = instance.controlStates[def.id]?.asKnob
				let raw     = max(0, min(1, instRaw ?? normalizedKnobValue(def)))
				let t   = canonicalT(for: def, value: raw)      // <- use canonicalT here
				let (start, sweep) = startSweep(for: def)
				KnobGlyphCanonical(
					t: t,
					startDeg: start,
					sweepDeg: sweep
				)

			case .concentricKnob:
				let oInst = instance.controlStates[def.id]?.asOuter
				let iInst = instance.controlStates[def.id]?.asInner
				let oRaw  = max(0, min(1, oInst ?? normalizedOuterValue(def)))
				let iRaw  = max(0, min(1, iInst ?? normalizedInnerValue(def)))
				let o     = canonicalT(for: def, ring: .outer, value: oRaw)
				let i     = canonicalT(for: def, ring: .inner, value: iRaw)
				let (start, sweep) = startSweep(for: def)
				ConcentricGlyphCanonical(outer: o, inner: i, startDeg: start, sweepDeg: sweep)

			case .steppedKnob:
				let idx = instance.controlStates[def.id]?.asStepped ?? steppedIndex(def)
				let count = max(2, def.stepValues?.count ?? def.stepAngles?.count ?? def.options?.count ?? 2)
				if count == 2 {
					BinarySquareGlyph(isOn: idx == 1)
				} else {
					SteppedGlyph(index: idx, count: count)
				}

			case .multiSwitch:
				let idx = instance.controlStates[def.id]?.asMulti ?? multiIndex(def)
				let count = max(2, def.options?.count ?? def.optionAngles?.count ?? 2)
				if count == 2 {
					BinarySquareGlyph(isOn: idx == 1)
				} else {
					SwitchGlyph(index: idx, count: count)
				}

			case .button:
				let isOn = instance.controlStates[def.id]?.asButton ?? (def.isPressed ?? false)
				BinarySquareGlyph(isOn: isOn)

			case .litButton:
				let isOn = instance.controlStates[def.id]?.asLitPressed ?? (def.isPressed ?? false)
//				let color = (isOn ? def.onColor : def.offColor)?.color ?? .green
				let onCol = def.onColor?.color ?? def.ledColor?.color ?? .green
				let offCol = def.offColor?.color ?? .white.opacity(0.15)
				LitButtonGlyph(isOn: isOn, color: isOn ? onCol : offCol)

			case .light:
				let isOn = resolveLightState(for: def)
				// Prefer lampOnColor, fallback to ledColor, then onColor, then default
				let onCol = def.lampOnColor?.color ?? def.ledColor?.color ?? def.onColor?.color ?? .green
				let offCol = def.lampOffColor?.color ?? def.offColor?.color ?? .white.opacity(0.15)
				LightGlyph(isOn: isOn, onColor: onCol, offColor: offCol)
		}
	}

	// Resolve light state, checking linkTarget if present
	private func resolveLightState(for control: Control) -> Bool {
		// Check if light is linked to another control (prioritize this over own state)
		if let targetId = control.linkTarget {
			// Find the target control
			if let target = device.controls.first(where: { $0.id == targetId }) {
				var isOn: Bool

				// Get target's state based on its type
				switch target.type {
				case .button, .litButton:
					let state = instance.controlStates[target.id]?.asButton ?? (target.isPressed ?? false)
					isOn = state
				case .multiSwitch:
					let currentIndex = instance.controlStates[target.id]?.asMulti ?? (target.selectedIndex ?? 0)
					let wantIndex = control.linkOnIndex ?? 0
					isOn = (currentIndex == wantIndex)
				case .steppedKnob:
					let currentIndex = instance.controlStates[target.id]?.asStepped ?? (target.stepIndex ?? 0)
					isOn = currentIndex > 0
				case .knob:
					let value = instance.controlStates[target.id]?.asKnob ?? (target.value ?? 0)
					isOn = value > 0.5
				default:
					isOn = false
				}

				// Apply inversion if configured
				if control.linkInverted ?? false {
					isOn.toggle()
				}

				return isOn
			}
		}

		// Check instance state (runtime value from session) if no link
		if let runtimeState = instance.controlStates[control.id]?.asLight {
			return runtimeState
		}

		// Fallback to light's own isPressed state
		return control.isPressed ?? false
	}
}

// MARK: - Value Helpers
@inline(__always)
private func startSweep(for def: Control) -> (Double, Double) {
	let start = def.repStartDeg ?? REP_KNOB_MIN_DEG   // e.g. -225 by default
	let sweep = def.repSweepDeg ?? REP_KNOB_SWEEP_DEG // e.g. 270 by default
	return (start, sweep)
}

private func knobAngle(startDeg: Double, sweepDeg: Double, t: Double) -> Double {
	startDeg + sweepDeg * t
}

private enum Ring { case outer, inner }

private func normalizedKnobValue(_ c: Control) -> Double {
	let lo = c.knobMin?.resolve(default: 0) ?? 0
	let hi = c.knobMax?.resolve(default: 1) ?? 1
	guard hi > lo else { return 0 }
	let v  = c.value ?? lo
	return min(max((v - lo) / (hi - lo), 0), 1)
}

private func normalizedOuterValue(_ c: Control) -> Double {
	let lo = c.outerMin?.resolve(default: 0) ?? 0
	let hi = c.outerMax?.resolve(default: 1) ?? 1
	guard hi > lo else { return 0 }
	let v  = c.outerValue ?? lo
	return min(max((v - lo) / (hi - lo), 0), 1)
}

private func normalizedInnerValue(_ c: Control) -> Double {
	let lo = c.innerMin?.resolve(default: 0) ?? 0
	let hi = c.innerMax?.resolve(default: 1) ?? 1
	guard hi > lo else { return 0 }
	let v  = c.innerValue ?? lo
	return min(max((v - lo) / (hi - lo), 0), 1)
}

// Index helpers (safe)
private func steppedIndex(_ c: Control) -> Int {
	let idx = c.stepIndex ?? 0
	let cnt = max(1, c.stepAngles?.count ?? c.stepValues?.count ?? c.options?.count ?? 1)
	return min(max(idx, 0), cnt - 1)
}

private func multiIndex(_ c: Control) -> Int {
	let idx = c.selectedIndex ?? 0
	let cnt = max(2, c.options?.count ?? c.optionAngles?.count ?? 2)
	return min(max(idx, 0), cnt - 1)
}

// MARK: - Canonical knob visuals (mid points straight up)

struct KnobGlyphCanonical: View {
	let t: Double  // 0…1
	let startDeg: Double
	let sweepDeg: Double
	
	var body: some View {
		ZStack {
			Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
			tickMarks
			Needle(angleDegrees: knobAngle(startDeg: startDeg, sweepDeg: sweepDeg, t: t))
				.stroke(.white, lineWidth: 1)
		}
		.padding(4)
	}
	
	private var tickMarks: some View {
		TickRingShape(
			tickCount: 25,
			minDeg: startDeg,
			sweepDeg: sweepDeg
		)
		.stroke(.white.opacity(0.35), lineWidth: 0.5)
	}
	
	private struct TickRingShape: Shape {
		let tickCount: Int
		let minDeg: Double
		let sweepDeg: Double
		
		func path(in rect: CGRect) -> Path {
			let r  = min(rect.width, rect.height) * 0.5 - 3.0
			let cx = rect.midX, cy = rect.midY
			var p  = Path()
			for i in 0..<tickCount {
				let t   = Double(i) / Double(max(1, tickCount - 1))
				let deg = minDeg + sweepDeg * t
				let rad = deg * .pi / 180.0
				let c   = CGFloat(cos(rad)), s = CGFloat(sin(rad))
				let p0  = CGPoint(x: cx + c * r,       y: cy + s * r)
				let p1  = CGPoint(x: cx + c * (r - 4), y: cy + s * (r - 4))
				p.move(to: p0); p.addLine(to: p1)
			}
			return p
		}
	}
	
	private struct Needle: Shape {
		let angleDegrees: Double
		func path(in rect: CGRect) -> Path {
			let r: CGFloat = min(rect.width, rect.height) * 0.5 - 6.0
			let aRad = angleDegrees * .pi / 180.0
			var p = Path()
			p.move(to: CGPoint(x: rect.midX, y: rect.midY))
			p.addLine(to: CGPoint(x: rect.midX + CGFloat(cos(aRad)) * r,
								  y: rect.midY + CGFloat(sin(aRad)) * r))
			return p
		}
	}
}

struct ConcentricGlyphCanonical: View {
	let outer: Double, inner: Double
	let startDeg: Double
	let sweepDeg: Double
	
	var body: some View {
		ZStack {
			Circle().stroke(.white.opacity(0.25), lineWidth: 6)
			Circle().stroke(.white.opacity(0.7), lineWidth: 2).scaleEffect(0.55)
			GaugeNeedle(angleDeg: knobAngle(startDeg: startDeg, sweepDeg: sweepDeg, t: outer))
				.stroke(.white, lineWidth: 2)
			GaugeNeedle(angleDeg: knobAngle(startDeg: startDeg, sweepDeg: sweepDeg, t: inner))
				.stroke(.white.opacity(0.8), lineWidth: 2)
				.scaleEffect(0.55)
		}.padding(6)
	}
	
	private struct GaugeNeedle: Shape {
		let angleDeg: Double
		func path(in rect: CGRect) -> Path {
			let r: CGFloat = min(rect.width, rect.height) * 0.5 - 6.0
			let a = angleDeg * .pi / 180.0
			var p = Path()
			p.move(to: CGPoint(x: rect.midX, y: rect.midY))
			p.addLine(to: CGPoint(x: rect.midX + CGFloat(cos(a)) * r,
								  y: rect.midY + CGFloat(sin(a)) * r))
			return p
		}
	}
}

struct SteppedGlyph: View {
	let index: Int, count: Int
	var body: some View {
		HStack(spacing: 3) {
			ForEach(0..<count, id: \.self) { i in
				Circle().fill(i == index ? .white.opacity(0.9) : .white.opacity(0.2))
					.frame(width: 6, height: 6)
			}
		}.padding(.top, 6)
	}
}

struct SwitchGlyph: View {
	let index: Int, count: Int

	var body: some View {
		HStack(spacing: 4) {
			ForEach(0..<count, id: \.self) { i in
				RoundedRectangle(cornerRadius: 2, style: .continuous)
					.fill(i == index ? .white.opacity(0.9) : .white.opacity(0.2))
					.frame(width: 8, height: 8)
			}
		}.padding(.top, 6)
	}
}

struct ButtonGlyph: View {
	let isOn: Bool
	var body: some View {
		Circle().fill(isOn ? .white.opacity(0.9) : .white.opacity(0.2))
			.overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
			.padding(6)
	}
}

struct BinarySquareGlyph: View {
	let isOn: Bool
	@Environment(\.displayScale) private var displayScale

	var body: some View {
		GeometryReader { geo in
			// square sized to the control box, pixel-snapped for crisp edges
			let side0 = min(geo.size.width, geo.size.height) * 0.70
			let side  = (side0 * displayScale).rounded() / displayScale
			let color = isOn ? Color.white : Color.black
			
			ZStack {
				Rectangle()
					.fill(color)
					.frame(width: side, height: side)
					.overlay(
						// keep the OFF state visible on a dark panel
						Rectangle()
							.stroke(Color.white.opacity(isOn ? 0 : 0.6), lineWidth: 1)
							.overlay(Rectangle().stroke(Color.black.opacity(isOn ? 0.25 : 0), lineWidth: 0.5))
					)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		}
	}
}

struct LightGlyph: View {
	let isOn: Bool
	let onColor: Color
	let offColor: Color

	var body: some View {
		ZStack {
			Circle().fill(isOn ? onColor : offColor)
			if isOn {
				// Add glow effect when on
				Circle().fill(onColor.opacity(0.5)).blur(radius: 3).scaleEffect(1.3)
			}
		}
		.padding(8)
	}
}

struct LitButtonGlyph: View {
	let isOn: Bool
	let color: Color

	var body: some View {
		ZStack {
			Circle().fill(isOn ? color : color.opacity(0.20))
			if isOn {
				// Glow effect using the specified color
				Circle().stroke(color, lineWidth: 2).blur(radius: 0.5)
				Circle().fill(color.opacity(0.35)).blur(radius: 3).scaleEffect(1.25)
			}
		}
		.padding(6)
	}
}

// MARK: - ControlValue shims (unchanged)
private extension ControlValue {
	var asKnob: Double?         { if case .knob(let v) = self { return v } else { return nil } }
	var asStepped: Int?         { if case .steppedKnob(let s) = self { return s } else { return nil } }
	var asMulti: Int?           { if case .multiSwitch(let i) = self { return i } else { return nil } }
	var asButton: Bool?         { if case .button(let b) = self { return b } else { return nil } }
	var asLight: Bool?          { if case .light(let b) = self { return b } else { return nil } }
	var asLitPressed: Bool?     { if case .litButton(let p) = self { return p } else { return nil } }
	var asOuter: Double?        { if case .concentricKnob(let o, _) = self { return o } else { return nil } }
	var asInner: Double?        { if case .concentricKnob(_, let i) = self { return i } else { return nil } }
}

// MARK: - Helpers
@inline(__always) private func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, x)) }

// Collision test (with tiny padding)
private func intersectsAny(_ r: CGRect, _ others: [CGRect]) -> Bool {
	let pad: CGFloat = 1
	let a = r.insetBy(dx: -pad, dy: -pad)
	return others.contains(where: { $0.intersects(a) })
}

// Smallest signed angular difference in degrees in the range (-180, 180]
@inline(__always)
private func signedDeltaDegrees(from a: Double, to b: Double) -> Double {
	var d = b - a
	while d <= -180 { d += 360 }
	while d >   180 { d -= 360 }
	return d
}

/// Return t (0…1) corrected when the authored rotate mapping runs clockwise.
/// We look up the rotate mapping on the requested ring (if any), otherwise on the first region
/// that actually carries a rotate with degMin/degMax.
@inline(__always)
private func canonicalT(for def: Control, ring: Ring? = nil, value t: Double) -> Double {
	// Representative mode is canonical: ignore image mappings entirely.
	return max(0, min(1, t))
}

// reuse the same deterministic accent you use on the faceplate
@inline(__always)
private func representativeAccentColor(for name: String) -> Color {
	var h: UInt64 = 0
	for u in name.unicodeScalars { h = (h &* 1099511628211) ^ UInt64(u.value) }
	let hue = Double(h % 360) / 360.0
	return Color(hue: hue, saturation: 0.60, brightness: 0.9)
}

// Best-effort display string for stepped/multi (fallbacks if no names exist)
private func selectionText(_ def: Control, instance: DeviceInstance) -> String? {
	switch def.type {
		case .steppedKnob:
			let idx = instance.controlStates[def.id]?.asStepped ?? 0
			if let names = def.options, idx < names.count { return names[idx] }
			return "Step \(idx + 1)"
		case .multiSwitch:
			let idx = instance.controlStates[def.id]?.asMulti ?? 0
			if let opts = def.options, idx < opts.count { return opts[idx] }
			return "Pos \(idx + 1)"
		default:
			return nil
	}
}
