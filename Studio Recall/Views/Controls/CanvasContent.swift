//
//  CanvasContent.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI

struct CanvasContent: View {
    @ObservedObject var editableDevice: EditableDevice
    let canvasSize: CGSize
    @Binding var selectedControlId: UUID?
    @Binding var draggingControlId: UUID?
    let gridStep: CGFloat
	let showBadges: Bool

    var body: some View {
        ZStack {
            // Faceplate
            if let data = editableDevice.device.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                Text("No Faceplate Image").foregroundColor(.white.opacity(0.7))
            }

			// Controls (names/badges overlay)
			if showBadges {
				AcceptedControlsOverlay(
					controls: editableDevice.device.controls,
					selectedId: $selectedControlId,
					canvasSize: canvasSize
				)
			}
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}

private struct AcceptedControlsOverlay: View {
	let controls: [Control]
	@Binding var selectedId: UUID?
	let canvasSize: CGSize
	
	var body: some View {
		ZStack {
			ForEach(controls) { c in
				let r = rectForControl(c)
				let frame = CGRect(
					x: r.minX * canvasSize.width,
					y: r.minY * canvasSize.height,
					width:  r.width * canvasSize.width,
					height: r.height * canvasSize.height
				)
				let isSel = (selectedId == c.id)
				
				ZStack(alignment: .top) {
					RoundedRectangle(cornerRadius: 3)
						.stroke(
							isSel ? Color.accentColor : .yellow,
							style: StrokeStyle(lineWidth: isSel ? 2 : 1,
											   dash: isSel ? [6,4] : [4,4])
						)
						.frame(width: frame.width, height: frame.height)
					
					Text(displayName(for: c))
						.font(.caption2)
						.lineLimit(1)
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(.thinMaterial, in: Capsule())
						.overlay(Capsule().stroke(.separator.opacity(0.6)))
						.offset(y: -20)
				}
				.position(x: frame.midX, y: frame.midY)
				.contentShape(Rectangle())
				.onTapGesture { selectedId = c.id }
			}
		}
		.allowsHitTesting(true)
	}
	
	private func displayName(for c: Control) -> String {
		c.name.isEmpty ? c.type.displayName : c.name
	}
	
	private func rectForControl(_ c: Control) -> CGRect {
		// Prefer the primary region’s rect if present, else a small box around the normalized center.
		if let first = c.regions.first?.rect {
			return first
		}
		let w: CGFloat = 0.08, h: CGFloat = 0.08
		let x = max(0, min(1 - w, c.x - w/2))
		let y = max(0, min(1 - h, c.y - h/2))
		return CGRect(x: x, y: y, width: w, height: h)
	}
}

private func baseName(for kind: ControlType) -> String {
	switch kind {
		case .knob, .steppedKnob, .concentricKnob: return "Knob"
		case .button, .litButton:                 return "Button"
		case .multiSwitch:                         return "Switch"
		case .light:                               return "Lamp"
	}
}

private func displayName(for c: Control, within all: [Control]) -> String {
	let trimmed = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
	guard trimmed.isEmpty else { return trimmed }
	let base = baseName(for: c.type)
	let tolY: CGFloat = 0.04 // ~4% of canvas height in normalized space
	let peers = all.filter { $0.type == c.type }.sorted {
		if abs($0.y - $1.y) > tolY { return $0.y < $1.y }
		return $0.x < $1.x
	}
	if let i = peers.firstIndex(where: { $0.id == c.id }) { return "\(base) \(i+1)" }
	return base
}
