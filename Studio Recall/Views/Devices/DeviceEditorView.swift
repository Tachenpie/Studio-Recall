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
		HStack(spacing: 0) {
			// LEFT: Form
			Form {
				Section("Identity") {
					TextField("Device Name", text: Binding(
						get: { editableDevice.device.name },
						set: { newValue in
							let old = editableDevice.device.name
							editableDevice.device.name = newValue
							undoManager?.registerUndo(withTarget: editableDevice) { $0.device.name = old }
						}
					))
				}
				
				Section("Rack Size") {
					if editableDevice.device.type == .rack {
						Picker("Width", selection: $editableDevice.device.rackWidth) {
							ForEach(RackWidth.allCases) { w in
								Text(w.label).tag(w)
							}
						}
						Stepper("Height: \(rackUnitsBinding.wrappedValue)U",
								value: rackUnitsBinding, in: 1...24)
						
						// Live readout
						#if DEBUG
						let sr = sizingReadout
						Group {
						LabeledContent("Span (in)") { Text(String(format: "%.2f", sr.span)) }
						LabeledContent("Body (in)") { Text(String(format: "%.2f", sr.body)) }
							LabeledContent("Wings (in)") {
								Text("L \(String(format: "%.2f", sr.leftWing)) • R \(String(format: "%.2f", sr.rightWing))")
							}
						}
						.font(.caption)
#endif
					} else {
						Stepper("Width: \(slotWidthBinding.wrappedValue) slot\(slotWidthBinding.wrappedValue == 1 ? "" : "s")",
								value: slotWidthBinding, in: 1...10)
						Text("Height: 5.25 in")
							.foregroundStyle(.secondary)
					}
				}
				
				Section("Categories") {
					CategoryEditor(editableDevice: editableDevice)
				}
				
				Section("Controls") {
					Button("Edit Controls…") { showingControlEditor = true }
				}
			}
			.frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
			.padding()
			
			Divider()
			
			// RIGHT: Preview panel
			VStack(alignment: .center, spacing: 12) {
				Text("Faceplate Preview")
					.font(.headline)
				
				ZStack {
					RoundedRectangle(cornerRadius: 8)
						.fill(Color.gray.opacity(0.06))
					
					Group {
						if let data = editableDevice.device.imageData,
						   let image = platformImage(from: data) {
							image.resizable().scaledToFit()
						} else {
							Text("No image selected").foregroundColor(.secondary)
						}
					}
					.frame(width: max(360, previewSize.width/3),
						   height: max(180, previewSize.height/3))
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary, lineWidth: 0.5))
					.animation(.default, value: rackUnitsBinding.wrappedValue)
					.animation(.default, value: editableDevice.device.rackWidth)
				}
				.padding(.horizontal)
				
				ImagePicker(
					imageData: $editableDevice.device.imageData,
					isRack: editableDevice.device.type == .rack,
					rackUnits: rackUnitsBinding,
					slotWidth: slotWidthBinding,
					ppi: settings.pointsPerInch
				)
				
				Spacer()
			}
			.frame(minWidth: 380)
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
		.sheet(isPresented: $showingControlEditor) {
			ControlEditorWindow(editableDevice: editableDevice)
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
	
	private var previewSize: CGSize {
		let ppi = settings.pointsPerInch
		
		if editableDevice.device.type == .rack {
			// Faceplate art uses the BODY width (19 / 8.5 / 5.5 in), not the span.
			let wIn = DeviceMetrics.bodyInches(for: editableDevice.device.rackWidth)
			let hIn = 1.75 * CGFloat(rackUnitsBinding.wrappedValue)
			return CGSize(
				width:  DeviceMetrics.points(fromInches: wIn, ppi: ppi),
				height: DeviceMetrics.points(fromInches: hIn, ppi: ppi)
			)
		} else {
			// 500-series (keep your constants unless you also expose them via DeviceMetrics)
			let wIn = 1.5 * CGFloat(slotWidthBinding.wrappedValue)  // or DeviceMetrics.series500SlotWidthInches
			let hIn = 5.25                                          // or DeviceMetrics.series500HeightInches
			return CGSize(
				width:  DeviceMetrics.points(fromInches: wIn, ppi: ppi),
				height: DeviceMetrics.points(fromInches: hIn, ppi: ppi)
			)
		}
	}

	private var sizingReadout: (span: CGFloat, body: CGFloat, leftWing: CGFloat, rightWing: CGFloat) {
		guard editableDevice.device.type == .rack else { return (0,0,0,0) }
		
		let w = editableDevice.device.rackWidth
		let spanIn  = DeviceMetrics.spanInches(for: w)     // 19, 9.5, 19/3
		let bodyIn  = DeviceMetrics.bodyInches(for: w)     // 19, 8.5, 5.5
//		let leftover = max(0, spanIn - bodyIn)
		
		// Nominal per-edge wings shown in the editor (independent of neighbors at runtime)
		let (leftWing, rightWing): (CGFloat, CGFloat) = {
			switch w {
				case .full:
					return (0, 0)                 // full-width art already includes ears
				case .half, .third:
					return (1.0, 1.0)             // show 1" on both sides in the editor
			}
		}()
		
		return (spanIn, bodyIn, leftWing, rightWing)
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
		.frame(width: 800, height: 480)
	}
		
}
#endif
