//
//  KeyCaptureLayer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct KeyCaptureLayer: View {
    let selectedControlBinding: Binding<Control>?
    let isEditingRegion: Bool
    let coarseStep: CGFloat
    let fineStep: CGFloat

    var body: some View {
        Group {
            if selectedControlBinding != nil, isEditingRegion {
                KeyCapture(handlers: .init(
                    onArrow: { dx, dy, isResize, fine in
                        let step = fine ? fineStep : coarseStep
                        guard var rect = selectedControlBinding?.wrappedValue.region?.rect else {
                            if var sel = selectedControlBinding?.wrappedValue {
                                let base = CGRect(x: max(0, sel.x - 0.05),
                                                  y: max(0, sel.y - 0.05),
                                                  width: 0.10, height: 0.10)
                                sel.region = ImageRegion(rect: base, mapping: sel.region?.mapping)
                                selectedControlBinding?.wrappedValue = sel
                            }
                            return
                        }
                        if isResize {
                            rect.size.width  = (rect.size.width  + dx * step).clamped(to: 0.03...1)
                            rect.size.height = (rect.size.height + dy * step).clamped(to: 0.03...1)
                        } else {
                            rect.origin.x = (rect.origin.x + dx * step).clamped(to: 0...1)
                            rect.origin.y = (rect.origin.y + dy * step).clamped(to: 0...1)
                        }
                        rect.origin.x = min(rect.origin.x, 1 - rect.size.width)
                        rect.origin.y = min(rect.origin.y, 1 - rect.size.height)

                        var sel = selectedControlBinding!.wrappedValue
                        if sel.region == nil { sel.region = ImageRegion(rect: rect, mapping: nil) }
                        else { sel.region?.rect = rect }
                        selectedControlBinding!.wrappedValue = sel
                    },
                    onSnap: {
                        guard var sel = selectedControlBinding?.wrappedValue else { return }
                        let side: CGFloat = 0.10
                        var r = CGRect(
                            x: (sel.x - side/2).clamped(to: 0...1),
                            y: (sel.y - side/2).clamped(to: 0...1),
                            width: side, height: side
                        )
                        r.origin.x = min(r.origin.x, 1 - r.size.width)
                        r.origin.y = min(r.origin.y, 1 - r.size.height)
                        r.origin.x = (r.origin.x / coarseStep).rounded() * coarseStep
                        r.origin.y = (r.origin.y / coarseStep).rounded() * coarseStep
                        r.size.width  = max(0.03, (r.size.width  / coarseStep).rounded() * coarseStep)
                        r.size.height = max(0.03, (r.size.height / coarseStep).rounded() * coarseStep)

                        if sel.region == nil { sel.region = ImageRegion(rect: r, mapping: sel.region?.mapping) }
                        else { sel.region?.rect = r }
                        selectedControlBinding!.wrappedValue = sel
                    }
                ))
                .frame(width: 0, height: 0)
            }
        }
    }
}
#endif
