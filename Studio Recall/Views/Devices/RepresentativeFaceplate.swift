//
//  RepresentativeFaceplate.swift
//  Studio Recall
//
//  Created by True Jackie on 10/1/25.
//
import SwiftUI

struct RepresentativeFaceplate: View {
	let device: Device
	let size: CGSize
	
	@Environment(\.displayScale) private var displayScale
	
	var body: some View {
		let titlePt = CGFloat(clamp(Double(size.height) * 0.045, min: 8.0, max: 11.0))
		let accent = representativeAccentColor(for: device.name)

		ZStack(alignment: .top) {
			// base plate
			RoundedRectangle(cornerRadius: 6, style: .continuous)
				.fill(
					LinearGradient(colors: [
						Color.black.opacity(0.95),
						Color.black.opacity(0.88),
						Color.gray.opacity(0.60)
					], startPoint: .top, endPoint: .bottomTrailing)
				)
			
			// brushed texture (very light)
			Canvas { ctx, s in
				let stripes = Path { p in
					for y in stride(from: 0.0, through: s.height, by: 3) {
						p.addRect(CGRect(x: 0, y: y, width: s.width, height: 1))
					}
				}
				ctx.stroke(stripes, with: .color(.white.opacity(0.05)))
			}
			.mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
			.allowsHitTesting(false)
			
			// left accent stripe
			RoundedRectangle(cornerRadius: 3, style: .continuous)
				.fill(
					LinearGradient(colors: [
						accent.opacity(0.85), accent.opacity(0.55)
					], startPoint: .top, endPoint: .bottom)
				)
				.frame(width: max(6, size.width * 0.035))
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.leading, 4)
				.allowsHitTesting(false)
			
			// screws (four corners)
			Screws()
				.stroke(.white.opacity(0.45), lineWidth: 1)
				.overlay(Screws().stroke(.black.opacity(0.35), lineWidth: 0.5))
				.padding(8)
				.allowsHitTesting(false)
			
			// centered device name
			Text(device.name)
				.font(.system(size: titlePt, weight: .semibold, design: .rounded))
				.kerning(0.2)
				.foregroundStyle(.white.opacity(0.92))
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.padding(.top, 5)
				.frame(maxWidth: .infinity, alignment: .center)
				.allowsHitTesting(false)
		}
		.frame(width: size.width, height: size.height)
	}
}

// MARK: - Tiny shapes/utilities

/// Four little screw heads with slots, positioned in the corners of the rect they're drawn in.
private struct Screws: Shape {
	func path(in r: CGRect) -> Path {
		let d: CGFloat = 9
		let inset: CGFloat = 0
		var p = Path()
		
		func addScrew(_ c: CGPoint) {
			p.addEllipse(in: CGRect(x: c.x - d/2, y: c.y - d/2, width: d, height: d))
			// slot
			let slot = CGRect(x: c.x - d*0.3, y: c.y - 0.75, width: d*0.6, height: 1.5)
			p.addRoundedRect(in: slot, cornerSize: CGSize(width: 0.75, height: 0.75))
		}
		
		addScrew(CGPoint(x: r.minX + inset, y: r.minY + inset))
		addScrew(CGPoint(x: r.maxX - inset, y: r.minY + inset))
		addScrew(CGPoint(x: r.minX + inset, y: r.maxY - inset))
		addScrew(CGPoint(x: r.maxX - inset, y: r.maxY - inset))
		return p
	}
}

/// Deterministic accent color based on the device name (stable across runs).
private func representativeAccentColor(for name: String) -> Color {
	var h: UInt64 = 0
	for u in name.unicodeScalars { h = (h &* 1099511628211) ^ UInt64(u.value) }
	let hue = Double(h % 360) / 360.0
	return Color(hue: hue, saturation: 0.60, brightness: 0.9)
}

@inline(__always) private func clamp<T: Comparable>(_ x: T, min lo: T, max hi: T) -> T { max(lo, min(hi, x)) }
