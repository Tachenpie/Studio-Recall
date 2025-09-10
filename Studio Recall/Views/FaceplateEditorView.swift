//
//  FaceplateEditorView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct FaceplateEditorView: View {
	// ORIGINAL image bytes (we never resample/overwrite them)
	let originalImageData: Data
	
	// Size controls
	let isRack: Bool
	@Binding var rackUnits: Int
	@Binding var slotWidth: Int
	let ppi: CGFloat
	
	// Callbacks
	let onSave: (Data) -> Void
	let onCancel: () -> Void
	
#if os(macOS)
	@State private var workingImage: NSImage?
#endif
	
	// Live target size computed from current U/slots + PPI
	private var targetSize: CGSize {
		if isRack {
			return CGSize(width: 19 * ppi, height: CGFloat(rackUnits) * 1.75 * ppi)
		} else {
			return CGSize(width: CGFloat(slotWidth) * 1.5 * ppi, height: 5.25 * ppi)
		}
	}
	
	var body: some View {
		VStack(spacing: 12) {
			// Preview (scaled for comfort)
			Group {
#if os(macOS)
				if let img = workingImage {
					Image(nsImage: img)
						.resizable()
						.scaledToFit()
				} else {
					Color.gray.opacity(0.15)
				}
#else
				if let uiImage = UIImage(data: originalImageData) {
					Image(uiImage: uiImage)
						.resizable()
						.scaledToFit()
				} else {
					Color.gray.opacity(0.15)
				}
#endif
			}
			.frame(width: max(320, targetSize.width / 2),
				   height: max(180, targetSize.height / 2))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 0.5))
			
			// Live size controls (update both the preview and the caller via bindings)
			if isRack {
				Stepper("Height: \(rackUnits)U", value: $rackUnits, in: 1...24)
			} else {
				Stepper("Width: \(slotWidth) slot\(slotWidth == 1 ? "" : "s")", value: $slotWidth, in: 1...10)
			}
			
			Spacer()
			
			HStack {
				Button("Cancel", role: .cancel) { onCancel() }
				Spacer()
				Button("Save") {
					// Save the ORIGINAL bytes
					onSave(originalImageData)
				}
				.buttonStyle(.borderedProminent)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(minWidth: max(420, targetSize.width / 2 + 80),
			   minHeight: max(320, targetSize.height / 2 + 140))
#if os(macOS)
		.onAppear {
			workingImage = NSImage(data: originalImageData)
		}
#endif
	}
}
