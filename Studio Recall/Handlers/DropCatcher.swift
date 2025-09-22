//
//  DropCatcher.swift
//  Studio Recall
//
//  Created by True Jackie on 9/18/25.
//

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A drop layer that fills its container and forwards drops to Swift closures.
struct DropCatcher: NSViewRepresentable {
	var name: String
	var types: [UTType]
	var onEnter: ((CGPoint, [String]) -> Void)? = nil
	var onUpdate: ((CGPoint) -> Void)? = nil
	var onExit: (() -> Void)? = nil
	var onDrop: (NSPasteboard, CGPoint) -> Void
	
	// Set this to true briefly if you want to *see* the overlay:
	var debugTint: Bool = false
	
	func makeNSView(context: Context) -> NSView {
		let v = CatcherView(name: name,
							pasteboardTypes: types.map { NSPasteboard.PasteboardType($0.identifier) },
							onEnter: onEnter, onUpdate: onUpdate, onExit: onExit, onDrop: onDrop)
		v.translatesAutoresizingMaskIntoConstraints = false
		if debugTint {
			v.wantsLayer = true
			v.layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.08).cgColor
		}
		return v
	}
	
	func updateNSView(_ nsView: NSView, context: Context) {
		// Pin to superview if not already pinned
		guard let superview = nsView.superview else { return }
		let hasConstraints = !(nsView.constraints.isEmpty && superview.constraints.first(where: {
			// any constraint that references nsView counts
			$0.firstItem as? NSView === nsView || $0.secondItem as? NSView === nsView
		}) == nil)
		
		if !hasConstraints {
			NSLayoutConstraint.activate([
				nsView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
				nsView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
				nsView.topAnchor.constraint(equalTo: superview.topAnchor),
				nsView.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
			])
		}
	}
}

private final class CatcherView: NSView {
	let name: String
	let pbTypes: [NSPasteboard.PasteboardType]
	let onEnter: ((CGPoint, [String]) -> Void)?
	let onUpdate: ((CGPoint) -> Void)?
	let onExit: (() -> Void)?
	let onDropHandler: (NSPasteboard, CGPoint) -> Void
	
	init(name: String,
		 pasteboardTypes: [NSPasteboard.PasteboardType],
		 onEnter: ((CGPoint, [String]) -> Void)?,
		 onUpdate: ((CGPoint) -> Void)?,
		 onExit: (() -> Void)?,
		 onDrop: @escaping (NSPasteboard, CGPoint) -> Void) {
		self.name = name
		self.pbTypes = pasteboardTypes
		self.onEnter = onEnter
		self.onUpdate = onUpdate
		self.onExit = onExit
		self.onDropHandler = onDrop
		super.init(frame: .zero)
		registerForDraggedTypes(pbTypes)
		// Accept mouse for DnD but otherwise stay transparent
		wantsLayer = true
		layer?.backgroundColor = .clear
	}
	
	required init?(coder: NSCoder) { fatalError() }
	
	override func hitTest(_ point: NSPoint) -> NSView? { self }
	
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		let t = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
		let loc = convert(sender.draggingLocation, from: nil)
		Swift.print("🧲[\(name)] ENTER types=\(t) loc=\(loc)")
		onEnter?(CGPoint(x: loc.x, y: loc.y), t)
		return .copy
	}
	
	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		let loc = convert(sender.draggingLocation, from: nil)
		onUpdate?(CGPoint(x: loc.x, y: loc.y))
		return .copy
	}
	
	override func draggingExited(_ sender: NSDraggingInfo?) {
		onExit?()
	}
	
	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let loc = convert(sender.draggingLocation, from: nil)
		let pb = sender.draggingPasteboard
		Swift.print("🧲[\(name)] DROP types=\(pb.types?.map(\.rawValue) ?? []) loc=\(loc)")
		onDropHandler(pb, CGPoint(x: loc.x, y: loc.y))
		return true
	}
}
#endif
