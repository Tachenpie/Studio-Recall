//
//  KeyCapture.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI

#if os(macOS)
import AppKit

struct KeyCapture: NSViewRepresentable {
    struct Handlers {
        var onArrow: (_ dx: CGFloat, _ dy: CGFloat, _ isResize: Bool, _ fine: Bool) -> Void
        var onSnap: () -> Void
    }

    let handlers: Handlers

    func makeNSView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.handlers = handlers
        DispatchQueue.main.async {
            v.window?.makeFirstResponder(v)
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {}

    final class KeyCaptureView: NSView {
        var handlers: Handlers!
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let fine = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command)
            let isResize = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 123: // ←
                handlers.onArrow(-1, 0, isResize, fine)
            case 124: // →
                handlers.onArrow( 1, 0, isResize, fine)
            case 125: // ↓
                handlers.onArrow(0,  1, isResize, fine)
            case 126: // ↑
                handlers.onArrow(0, -1, isResize, fine)
            default:
                if let chars = event.charactersIgnoringModifiers?.uppercased() {
                    if chars == "S" {
                        handlers.onSnap()
                        return
                    }
                }
                super.keyDown(with: event)
            }
        }
    }
}
#endif
