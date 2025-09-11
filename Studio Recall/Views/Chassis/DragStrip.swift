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
	
	@State private var start: CGPoint?
	@State private var began = false
	
	var body: some View {
		ZStack(alignment: .bottom) {
			// tabletop
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(.thinMaterial)
				.overlay(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.stroke(.white.opacity(0.12))
				)
				.frame(height: 24)
				.shadow(color: .black.opacity(0.25), radius: 2, y: 1)
			
			// tiny front ledge
			Rectangle()
				.fill(.black.opacity(0.25))
				.frame(height: 3)
				.cornerRadius(2)
				.offset(y: 2)
		}
		.overlay(
			HStack(spacing: 8) {
				Image(systemName: "ellipsis").foregroundStyle(.secondary)
				Text((title ?? "").isEmpty ? "Chassis" : title!)
					.font(.caption)                  // let it scale with the canvas (no tricks)
					.foregroundStyle(.secondary)
					.lineLimit(1)
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
	}
}
