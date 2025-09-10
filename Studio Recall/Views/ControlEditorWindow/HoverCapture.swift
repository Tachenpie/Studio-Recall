//
//  HoverCapture.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI
#if os(macOS)
import AppKit

struct HoverCapture: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void   // view-local coordinates (nil when left)

    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onMove = onMove
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?

        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited]
            tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(tracking!)
        }

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            onMove?(p)
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }
    }
}
#endif
