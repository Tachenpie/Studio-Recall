//
//  DeviceEditorView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct DeviceEditorView: View {
	@Environment(\.undoManager) private var undoManager
	@EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var settings: AppSettings
	
	@ObservedObject var editableDevice: EditableDevice
	var onCommit: (Device) -> Void
	var onCancel: () -> Void
	
	@State private var showingImagePicker = false
	@State private var showingControlEditor = false
	
	// Bindings to bridge optional Ints to Steppers/ImagePicker
	private var rackUnitsBinding: Binding<Int> {
		Binding(
			get: { editableDevice.device.rackUnits ?? 1 },
			set: { new in editableDevice.device.rackUnits = new }
		)
	}
	private var slotWidthBinding: Binding<Int> {
		Binding(
			get: { editableDevice.device.slotWidth ?? 1 },
			set: { new in editableDevice.device.slotWidth = new }
		)
	}
	
	private var targetSize: CGSize {
		let ppi = settings.pointsPerInch
		if editableDevice.device.type == .rack {
			return CGSize(
				width: 19 * ppi,
				height: CGFloat(rackUnitsBinding.wrappedValue) * 1.75 * ppi
			)
		} else {
			return CGSize(
				width: CGFloat(slotWidthBinding.wrappedValue) * 1.5 * ppi,
				height: 5.25 * ppi
			)
		}
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			
			// Name
			TextField("Device Name", text: Binding(
				get: { editableDevice.device.name },
				set: { newValue in
					let old = editableDevice.device.name
					editableDevice.device.name = newValue
					undoManager?.registerUndo(withTarget: editableDevice) { $0.device.name = old }
				}
			))
			.textFieldStyle(.roundedBorder)
			.padding(.horizontal)
			
			// Size controls (single set; removed duplicates)
			if editableDevice.device.type == .rack {
				Stepper("Height: \(rackUnitsBinding.wrappedValue)U", value: rackUnitsBinding, in: 1...24)
					.padding(.horizontal)
			} else {
				Stepper("Width: \(slotWidthBinding.wrappedValue) slot\(slotWidthBinding.wrappedValue == 1 ? "" : "s")",
						value: slotWidthBinding, in: 1...10)
				.padding(.horizontal)
			}
			
			// Faceplate
			Section("Faceplate") {
				Group {
					if let data = editableDevice.device.imageData,
					   let image = platformImage(from: data) {
						image
							.resizable()
							.scaledToFit()
					} else {
						ZStack {
							RoundedRectangle(cornerRadius: 8)
								.fill(Color.gray.opacity(0.12))
							Text("No image selected").foregroundColor(.secondary)
						}
					}
				}
				.frame(width: max(360, targetSize.width / 3),
					   height: max(180, targetSize.height / 3))
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 0.5))
				.animation(.default, value: rackUnitsBinding.wrappedValue)
				.animation(.default, value: slotWidthBinding.wrappedValue)				
				ImagePicker(
					imageData: $editableDevice.device.imageData, isRack: editableDevice.device.type == .rack, rackUnits: rackUnitsBinding, slotWidth: slotWidthBinding, ppi: settings.pointsPerInch
				)
				
			}
			.padding(.horizontal)
			
			// Categories etc. (your existing editors can stay here)
			CategoryEditor(editableDevice: editableDevice)
				.padding(.horizontal)
			
			// Controls editor launcher
			Button("Edit Controls…") { showingControlEditor = true }
				.padding(.horizontal)
				.sheet(isPresented: $showingControlEditor) {
					ControlEditorWindow(editableDevice: editableDevice)
				}
			
			Spacer()
		}
		.padding(.vertical)
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") { onCancel() }
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { onCommit(editableDevice.device) }
					.keyboardShortcut(.defaultAction)
			}
		}
	}
	
	// MARK: Platform image helper
	private func platformImage(from data: Data) -> Image? {
#if os(iOS)
		if let uiImage = UIImage(data: data) { return Image(uiImage: uiImage) }
#elseif os(macOS)
		if let nsImage = NSImage(data: data) { return Image(nsImage: nsImage) }
#endif
		return nil
	}
}



#if DEBUG
import AppKit // for NSImage -> Data conversion

struct DeviceEditorView_Previews: PreviewProvider {
	static var previews: some View {
		let library = DeviceLibrary()
		let settings = AppSettings()
		
		// --- Rack Device (19" wide, 1U tall) ---
		var rackDevice = Device(
			name: "dbx 160A",
			type: .rack,
			rackUnits: 1,
			categories: ["Compressor"]
		)
		
		// 19" × 1.75" per U → scale to ~100 px per inch for preview
		let rackSize = CGSize(width: 19 * 100, height: 1.75 * 100 * CGFloat(rackDevice.rackUnits ?? 1))
		let rackImg = NSImage(size: rackSize)
		rackImg.lockFocus()
		NSColor.systemBlue.setFill()
		NSBezierPath(rect: CGRect(origin: .zero, size: rackSize)).fill()
		rackImg.unlockFocus()
		rackDevice.imageData = rackImg.pngData()
		
//		library.add(rackDevice)
		
		// --- 500-Series Module (1.5" wide × 5.25" tall) ---
		var moduleDevice = Device(
			name: "API 512c",
			type: .series500,
			slotWidth: 1,
			categories: ["Preamp"]
		)
		
		let moduleSize = CGSize(width: 1.5 * 100 * CGFloat(moduleDevice.slotWidth ?? 1),
								height: 5.25 * 100)
		let moduleImg = NSImage(size: moduleSize)
		moduleImg.lockFocus()
		NSColor.systemGreen.setFill()
		NSBezierPath(rect: CGRect(origin: .zero, size: moduleSize)).fill()
		moduleImg.unlockFocus()
		moduleDevice.imageData = moduleImg.pngData()
		
//		library.add(moduleDevice)
		
		return Group {
			DeviceEditorView(
				editableDevice: EditableDevice(device: rackDevice),
				onCommit: { _ in },
				onCancel: {}
			)
			.environmentObject(library)
			.environmentObject(settings)
			.frame(minWidth: 700, minHeight: 500)
			.previewDisplayName("Rack Device")
			
			DeviceEditorView(
				editableDevice: EditableDevice(device: moduleDevice),
				onCommit: { _ in },
				onCancel: {}
			)
			.environmentObject(library)
			.environmentObject(settings)
			.frame(minWidth: 700, minHeight: 500)
			.previewDisplayName("500-Series Module")
		}
	}
}
#endif
