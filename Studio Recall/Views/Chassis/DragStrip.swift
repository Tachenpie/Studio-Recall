//
//  DragStrip.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//

import SwiftUI

struct DragStrip: View {
	var title: String? = nil
	var onBegan: () -> Void = {}
	var onDrag: (CGSize) -> Void
	var onEnded: () -> Void = {}
	
	var onEditRequested: (() -> Void)? = nil
	var onClearRequested: (() -> Void)? = nil
	var onDeleteRequested: (() -> Void)? = nil
	
	@Environment(\.canvasZoom) private var canvasZoom
	@State private var start: CGPoint?
	@State private var began = false
	
	var body: some View {
		ZStack(alignment: .bottom) {
			// tabletop
			TopOnlyRoundedRect(radius: 8)
				.fill(.thinMaterial)
				.overlay(TopOnlyRoundedRect(radius: 8).stroke(.white.opacity(0.12)))
				.frame(height: 24)
				.shadow(color: .black.opacity(0.25), radius: 2, y: 1)
			
			// tiny front ledge
			Rectangle()
				.fill(.black.opacity(0.25))
				.frame(height: 3)
				.offset(y: 2)
		}
		.overlay(
			HStack(spacing: 8) {
				Image(systemName: "ellipsis").foregroundStyle(.secondary)
				Text((title ?? "").isEmpty ? "Chassis" : title!)
					.font(.system(size: max(11, 11 * canvasZoom), weight: .regular))
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.allowsTightening(true)
					.minimumScaleFactor(0.85)
					.scaleEffect(1 / max(canvasZoom, 0.0001), anchor: .center)
					.allowsHitTesting(false)
			}
				.padding(.horizontal, 8)
		)
		.contentShape(Rectangle())
		.gesture(
			DragGesture(minimumDistance: 0, coordinateSpace: .global)   // <<< GLOBAL
				.onChanged { v in
					if !began { began = true; start = v.location; onBegan() }
					guard let s = start else { return }
					onDrag(CGSize(width: v.location.x - s.x,
								  height: v.location.y - s.y))          // stable screen translation
				}
				.onEnded { _ in
					began = false
					start = nil
					onEnded()
				}
		)
		.padding(.top, 6)
		.padding(.horizontal, 8)
		.contextMenu {
			if let onEditRequested {
				Button { onEditRequested() } label: {
					Label("Edit Chassis…", systemImage: "slider.horizontal.3")
				}
			}
			if let onClearRequested {
				Button { onClearRequested() } label: {
					Label("Clear All Devices", systemImage: "xmark.bin")
				}
			}
			if let onDeleteRequested {
				Button(role: .destructive) { onDeleteRequested() } label: {
					Label("Delete Chassis", systemImage: "trash")
				}
			}
		}
	}
}

/// Custom shape with rounded top corners only (bottom corners are square).
private struct TopOnlyRoundedRect: Shape {
	var radius: CGFloat = 8
	func path(in rect: CGRect) -> Path {
		let r = min(radius, min(rect.width, rect.height) / 2)
		var p = Path()
		p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
		p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
		p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
					   control: CGPoint(x: rect.minX, y: rect.minY))
		p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
		p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
					   control: CGPoint(x: rect.maxX, y: rect.minY))
		p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		p.closeSubpath()
		return p
	}
}
