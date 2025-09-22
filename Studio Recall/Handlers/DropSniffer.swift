//
//  DropSniffer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/18/25.
//


#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropSniffer: NSViewRepresentable {
    var name: String
	private let types: [NSPasteboard.PasteboardType] = [
		NSPasteboard.PasteboardType(UTType.deviceDragPayload.identifier),
		NSPasteboard.PasteboardType(UTType.data.identifier),
		NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
		.string // (nice to have)
	]

    func makeNSView(context: Context) -> NSView {
        let v = SnifferView(name: name)
        v.registerForDraggedTypes(types)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SnifferView: NSView {
    let name: String
    init(name: String) { self.name = name; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let t = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        Swift.print("🧲[\(name)] draggingEntered types=", t)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Swift.print("🧲[\(name)] draggingUpdated @", sender.draggingLocation)
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Swift.print("🧲[\(name)] performDragOperation")
        return false // non-consuming; lets SwiftUI still handle it
    }
}
#endif
