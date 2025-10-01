//
//  RepresentativeGlyphs.swift
//  Studio Recall
//
//  Created by True Jackie on 10/1/25.
//

import SwiftUI

struct RepresentativeGlyphs: View {
	@Environment(\.displayScale) private var displayScale
	
	let device: Device
	@Binding var instance: DeviceInstance
	let faceSize: CGSize
	
	var body: some View {
		ZStack(alignment: .topLeading) {
			
			// 1) Controls as lightweight glyphs (no labels inside)
			ForEach(device.controls) { def in
				let frame = def.bounds(in: faceSize)
				glyph(for: def)
					.frame(width: frame.width, height: frame.height, alignment: .center)
					.position(x: frame.midX, y: frame.midY)
					.allowsHitTesting(false)
			}
			
			// 2) Labels BELOW each control, placed in face coordinates
			ForEach(device.controls) { def in
				let frame = def.bounds(in: faceSize)
				let label = def.name.isEmpty ? def.type.displayName : def.name
				let labelPt = CGFloat(clamp(Double(faceSize.height) * 0.024, min: 7.0, max: 10.0))
				
				// snap to device pixels for maximum crispness
				let px = (frame.midX * displayScale).rounded() / displayScale
				let py = ((frame.maxY + 3 + labelPt * 0.5) * displayScale).rounded() / displayScale

				// offset the label 4pt below the control's rect
				Text(label)
					.font(.system(size: labelPt, weight: .regular, design: .rounded))
					.foregroundStyle(.white.opacity(0.92))
					.lineLimit(1)
					.minimumScaleFactor(0.75)
					.allowsTightening(true)
					.frame(width: max(26, frame.width + 8)) // a little extra to reduce truncation
					.position(x: px, y: py)
					.allowsHitTesting(false)
			}
		}
		.frame(width: faceSize.width, height: faceSize.height, alignment: .topLeading)
	}
	
	@ViewBuilder
	private func glyph(for def: Control) -> some View {
		switch def.type {
			case .knob:
				// t ∈ [0,1], canonical sweep centered on Y-axis (mid = straight up)
				KnobGlyphCanonical(t: (instance.controlStates[def.id]?.asKnob) ?? 0)
			case .steppedKnob:
				SteppedGlyph(index: (instance.controlStates[def.id]?.asStepped) ?? 0,
							 count: max(1, def.stepAngles?.count ?? def.stepValues?.count ?? 8))
			case .multiSwitch:
				SwitchGlyph(index: (instance.controlStates[def.id]?.asMulti) ?? 0,
							count: max(2, def.options?.count ?? def.optionAngles?.count ?? 3))
			case .button:
				ButtonGlyph(isOn: (instance.controlStates[def.id]?.asButton) ?? false)
			case .light:
				LightGlyph(isOn: (instance.controlStates[def.id]?.asLight) ?? false)
			case .concentricKnob:
				ConcentricGlyphCanonical(outer: (instance.controlStates[def.id]?.asOuter) ?? 0,
										 inner: (instance.controlStates[def.id]?.asInner) ?? 0)
			case .litButton:
				LitButtonGlyph(isOn: (instance.controlStates[def.id]?.asLitPressed) ?? false)
		}
	}
}

// MARK: - Glyphs (unchanged visuals, no label inside)

// MARK: - Canonical knob visuals (mid points straight up)

private struct KnobGlyphCanonical: View {
	let t: Double  // 0…1
	var body: some View {
		ZStack {
			Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
			tickMarks
			Needle(angleDegrees: canonicalAngle(t))
				.stroke(.white, lineWidth: 2)
		}
		.padding(4)
	}
	
	/// Canonical mapping: sweep 270°, centered on Y-axis (mid = 90°)
	private func canonicalAngle(_ t: Double) -> Double {
		// 6:30 (-165°) ... 12:00 (-90°) ... 5:30 (-15°)
		return -240.0 + 300.0 * t
	}
	
	private var tickMarks: some View {
		Canvas { ctx, size in
			let r: CGFloat = min(size.width, size.height) * 0.5 - 3.0
			let cx: CGFloat = size.width  * 0.5
			let cy: CGFloat = size.height * 0.5
			for i in 0..<21 {
				let tt = Double(i) / 20.0
				let deg = canonicalAngle(tt)
				let rad = deg * .pi / 180.0
				let c = CGFloat(cos(rad)), s = CGFloat(sin(rad))
				let p0 = CGPoint(x: cx + c * r,       y: cy + s * r)
				let p1 = CGPoint(x: cx + c * (r - 4), y: cy + s * (r - 4))
				var path = Path(); path.move(to: p0); path.addLine(to: p1)
				ctx.stroke(path, with: .color(.white.opacity(0.35)))
			}
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

private struct ConcentricGlyphCanonical: View {
	let outer: Double, inner: Double
	private func canonicalAngle(_ t: Double) -> Double {
		// same top-arc sweep as single knobs
		return -240.0 + 300.0 * t
	}
	
	var body: some View {
		ZStack {
			Circle().stroke(.white.opacity(0.25), lineWidth: 6)
			Circle().stroke(.white.opacity(0.7), lineWidth: 2).scaleEffect(0.55)
			GaugeNeedle(angleDeg: canonicalAngle(outer)).stroke(.white, lineWidth: 2)
			GaugeNeedle(angleDeg: canonicalAngle(inner)).stroke(.white.opacity(0.8), lineWidth: 2).scaleEffect(0.55)
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

private struct SteppedGlyph: View {
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

private struct SwitchGlyph: View {
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

private struct ButtonGlyph: View {
	let isOn: Bool
	var body: some View {
		Circle().fill(isOn ? .white.opacity(0.9) : .white.opacity(0.2))
			.overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
			.padding(6)
	}
}

private struct LightGlyph: View {
	let isOn: Bool
	var body: some View {
		Circle().fill(isOn ? .green.opacity(0.9) : .white.opacity(0.15))
			.padding(8)
	}
}

private struct LitButtonGlyph: View {
	let isOn: Bool
	var body: some View {
		ZStack {
			Circle().fill(isOn ? .white.opacity(0.95) : .white.opacity(0.20))
			if isOn {
				Circle().stroke(.white, lineWidth: 2).blur(radius: 0.5)
				Circle().fill(.white.opacity(0.35)).blur(radius: 3).scaleEffect(1.25)
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

// tiny util
@inline(__always) private func clamp<T: Comparable>(_ x: T, min lo: T, max hi: T) -> T { max(lo, min(hi, x)) }
