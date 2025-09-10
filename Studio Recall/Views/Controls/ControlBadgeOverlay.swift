//
//  ControlBadgeOverlay.swift
//  Studio Recall
//
//  Created by True Jackie on 9/8/25.
//


import SwiftUI

struct ControlBadgeOverlay: View {
    let control: Control
    let canvasSize: CGSize
    let isSelected: Bool
    let showRegion: Bool

	@State private var isHover = false
	
    var body: some View {
        // Where the control sits (center) in canvas pixels
        let cx = control.x * canvasSize.width
        let cy = control.y * canvasSize.height

        // If control has a region, outline that; otherwise show a small badge.
        ZStack {
            if showRegion, let r = control.region?.rect {
                let frame = CGRect(
                    x: r.minX * canvasSize.width,
                    y: r.minY * canvasSize.height,
                    width:  r.width  * canvasSize.width,
                    height: r.height * canvasSize.height
                )

                // Visual-only dashed region (like RegionOverlay, but passive)
                RoundedRectangle(cornerRadius: control.region?.shape == .circle ? min(frame.width, frame.height)/2 : 4)
                    .stroke(isSelected ? Color.accentColor : Color.blue.opacity(0.7),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [4,3]))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
					.overlay(
						RoundedRectangle(cornerRadius: 6, style: .continuous)
							.stroke(isHover ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1)
					)
					.onHover { isHover = $0 } // macOS
					.animation(.easeInOut(duration: 0.12), value: isHover)
            } else {
                // Small badge ring at control center
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.blue.opacity(0.7),
                            lineWidth: isSelected ? 2 : 1)
                    .frame(width: 14, height: 14)
                    .position(x: cx, y: cy)
                    .overlay(
                        Circle()
                            .fill((isSelected ? Color.accentColor : Color.blue).opacity(0.12))
                            .frame(width: 18, height: 18)
                            .position(x: cx, y: cy)
                    )
					.overlay(
						RoundedRectangle(cornerRadius: 6, style: .continuous)
							.stroke(isHover ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1)
					)
					.onHover { isHover = $0 } // macOS
					.animation(.easeInOut(duration: 0.12), value: isHover)
                    .allowsHitTesting(false)
            }
        }
        // macOS tooltip with control name
        #if os(macOS)
        .help(control.name.isEmpty ? control.type.displayName : control.name)
        #endif
    }
}
