//
//  KeyCapture.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//
//
//  KeyCapture.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//  Updated: adds optional handlers for delete/return/number hotkeys without breaking existing call sites.
//

import SwiftUI

#if os(macOS)
import AppKit

struct KeyCapture: NSViewRepresentable {
	struct Handlers {
		// REQUIRED: existing handlers (unchanged)
		var onArrow: (_ dx: CGFloat, _ dy: CGFloat, _ isResize: Bool, _ fine: Bool) -> Void
		var onSnap: () -> Void = {}
		
		// NEW: all optional, default no-ops so old call sites compile untouched
		var onDelete: (() -> Void)? = nil
		var onAccept: (() -> Void)? = nil
		/// e.g. map 1..6 to a domain-specific type (Knob, Step, Switch, Button, LED, Slider)
		var onTypeHotkey: ((Int) -> Void)? = nil
		/// Escape pressed (e.g., cancel)
		var onCancel: (() -> Void)? = nil
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
			// Modifiers: Shift = resize, Option/Command = fine step
			let fine = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command)
			let isResize = event.modifierFlags.contains(.shift)
			
			switch event.keyCode {
					// ← → ↓ ↑
				case 123: handlers.onArrow(-1, 0, isResize, fine)   // left
				case 124: handlers.onArrow( 1, 0, isResize, fine)   // right
				case 125: handlers.onArrow( 0, 1, isResize, fine)   // down
				case 126: handlers.onArrow( 0,-1, isResize, fine)   // up
					
					// Delete / Forward Delete
				case 51, 117:
					handlers.onDelete?()
					
					// Return / Enter → Accept
				case 36, 76:
					handlers.onAccept?()
					
					// Escape → Cancel
				case 53:
					handlers.onCancel?()
					
				default:
					if let chars = event.charactersIgnoringModifiers {
						// Support number hotkeys "1"..."9"
						if let n = Int(chars), (1...9).contains(n) {
							handlers.onTypeHotkey?(n)
							return
						}
						// Existing snap shortcut (S / s)
						if chars.uppercased() == "S" {
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
