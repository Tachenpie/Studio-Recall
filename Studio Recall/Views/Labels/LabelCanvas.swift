//
//  LabelCanvas.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

struct LabelCanvas: View {
    // All labels in the session (or filtered upstream)
    @Binding var labels: [SessionLabel]

    /// Where these labels are anchored to (session/rack/device for this canvas)
    let anchor: LabelAnchor
    /// Parent's origin in the *same* coordinate space as the canvas content
    let parentOrigin: CGPoint

	var rackRects: [RackRect] = []
	
    // For simple editing demo
    @State private var editing: SessionLabel? = nil
    @Environment(\.canvasZoom) private var zoom

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(indicesFor(anchor: anchor), id: \.self) { idx in
                let binding = $labels[idx]
                LabelView(label: binding,
                          onBeginDrag: {},
                          onChanged: { delta in
                              var p = binding.wrappedValue.offset
                              p.x += delta.width / max(zoom, 0.0001)
                              p.y += delta.height / max(zoom, 0.0001)
                              binding.wrappedValue.offset = p
                          },
                          onEnd: {
					// Absolute position in the session canvas space
					let abs = CGPoint(
						x: parentOrigin.x + binding.wrappedValue.offset.x,
						y: parentOrigin.y + binding.wrappedValue.offset.y
					)
					// If it sits over a rack, reparent it to that rack; else keep/convert to session.
					if let hit = rackRects.first(where: { $0.frame.contains(abs) }) {
						binding.wrappedValue.anchor = .rack(hit.id)
						// New offset relative to rack's top-left
						binding.wrappedValue.offset = CGPoint(
							x: abs.x - hit.frame.minX,
							y: abs.y - hit.frame.minY
						)
					} else {
						// Anchor to session at absolute position
						binding.wrappedValue.anchor = .session
						binding.wrappedValue.offset = abs
					}
				},
                          onEdit: { editing = binding.wrappedValue },
						  onDelete: {
					let id = binding.wrappedValue.id
					labels.removeAll(where: { $0.id == id })
				}
				)
                .position(x: parentOrigin.x + binding.wrappedValue.offset.x,
                          y: parentOrigin.y + binding.wrappedValue.offset.y)
            }
        }
        .zIndex(100_000) // float above all
		.sheet(item: $editing) { item in
			if let idx = labels.firstIndex(where: { $0.id == item.id }) {
				LabelInspector(label: $labels[idx])
					.frame(minWidth: 360)
			} else {
				// Fallback if the label was deleted while the sheet was opening
				Text("Label not found").padding()
			}
		}
        .allowsHitTesting(true)
    }

    private func indicesFor(anchor: LabelAnchor) -> [Int] {
        labels.indices.filter { labels[$0].anchor == anchor }
    }
}
