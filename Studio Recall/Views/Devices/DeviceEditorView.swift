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
	@State private var tempCategorySelection: Set<String> = []
	
	@FocusState private var nameFocused: Bool
	
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
			VStack(alignment: .leading, spacing: 18) {

				InspectorSection(title: "Device") {
					Grid(horizontalSpacing: 12, verticalSpacing: 10) {
						GridRow {
							FieldLabel("Device Name")
							TextField("Device Name", text: Binding(
								get: { editableDevice.device.name },
								set: { newValue in
									let old = editableDevice.device.name
									editableDevice.device.name = newValue
									undoManager?.registerUndo(withTarget: editableDevice) { $0.device.name = old }
								}
							))
							.textFieldStyle(.roundedBorder)
							.frame(maxWidth: 280, alignment: .leading)
							.focused($nameFocused)
						}
					}
				}
				
				InspectorSection(title: "Rack Size") {
					Grid(horizontalSpacing: 12, verticalSpacing: 10) {
						if editableDevice.device.type == .rack {
							// RACK
							GridRow {
								FieldLabel("Width")
								Picker("", selection: $editableDevice.device.rackWidth) {
									ForEach(RackWidth.allCases) { w in
										Text(w.label).tag(w)
									}
								}
								.labelsHidden()
								.frame(maxWidth: 220, alignment: .leading)
							}
							
							GridRow {
								FieldLabel("Height")
								Stepper(value: rackUnitsBinding, in: 1...10) {
									// Stable, left-aligned label next to the arrows
									Text("\(rackUnitsBinding.wrappedValue)U")
										.frame(width: 60, alignment: .leading)
								}
								.frame(maxWidth: 220, alignment: .leading)   // keeps it out of the far right
							}
						} else {
							// 500-SERIES (non-rack)
							GridRow {
								FieldLabel("Width")
								Stepper(value: slotWidthBinding, in: 1...10) {
									Text("\(slotWidthBinding.wrappedValue) slot\(slotWidthBinding.wrappedValue == 1 ? "" : "s")")
										.frame(width: 120, alignment: .leading)
								}
								.frame(maxWidth: 220, alignment: .leading)
							}
						}
					}
				}
				
				InspectorSection(title: "Categories") {
					// ORIGINAL vs PENDING
					let originals = Set(editableDevice.device.categories)
					let pending   = tempCategorySelection
					let allNames  = Array(originals.union(pending)).sorted {
						$0.localizedCaseInsensitiveCompare($1) == .orderedAscending
					}
					
					Grid(horizontalSpacing: 12, verticalSpacing: 10) {
						
						// Row 1: chips (two-row viewport with vertical scroll if needed)
						GridRow {
							FieldLabel("") // keep column alignment
							ScrollView(.vertical) {
								let chipShape = RoundedRectangle(cornerRadius: 6)
								LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
									ForEach(allNames, id: \.self) { name in
										let isAdded   =  pending.contains(name) && !originals.contains(name)
										let isRemoved =  originals.contains(name) && !pending.contains(name)
										
										let bg: Color = isAdded
										? Color.accentColor.opacity(0.18)
										: (isRemoved ? .clear : Color.gray.opacity(0.18))
										let strokeColor: Color = isAdded
										? .accentColor
										: (isRemoved ? Color.secondary.opacity(0.5) : .clear)
										let strokeWidth: CGFloat = (isAdded || isRemoved) ? 1 : 0
										let fg: Color = isAdded ? .accentColor : (isRemoved ? .secondary : .primary)
										
										Text(name)
											.font(.caption)
											.padding(.horizontal, 8).padding(.vertical, 3)
											.background(chipShape.fill(bg))
											.overlay(chipShape.stroke(strokeColor, lineWidth: strokeWidth))
											.foregroundStyle(fg)
											.opacity(isRemoved ? 0.7 : 1.0)
									}
								}
								.padding(.top, 2)
							}
							.scrollIndicators(.automatic)
							.frame(height: 60)                 // ≈ two chip rows; scrolls only if needed
							.frame(maxWidth: 280, alignment: .leading)
						}
						
						// Row 2: always-visible editor (aligned to the same right column)
						GridRow {
							FieldLabel("")
							CategoryEditorInline(selection: $tempCategorySelection)
								.environmentObject(library)
								.frame(maxWidth: 280, alignment: .leading)
								.onAppear {
									if tempCategorySelection.isEmpty {
										tempCategorySelection = Set(editableDevice.device.categories)
									}
								}
						}
					}
				}
				
				InspectorSection(title: "Controls") {
					HStack {
						Button("Edit Controls…") { showingControlEditor = true }
						Spacer()
					}
				}
			}
			.frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, alignment: .trailing)
			.padding(16)
			
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
		.onAppear {
			settings.parentInteracting = true
			nameFocused = true
		}
		.onDisappear { settings.parentInteracting = false }
		.toolbar {
			ToolbarItem(placement: .cancellationAction) {
				Button("Cancel") {
					// no category write-back; parent handles dismissal
					settings.parentInteracting = false
					onCancel()
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") {
					// 1) Commit the inline selection into the device
					let committed = Array(tempCategorySelection)
						.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
					editableDevice.device.categories = committed
					
					// 2) Hand the fully-updated Device back to the parent to persist
					onCommit(editableDevice.device)
					settings.parentInteracting = false
				}
				.buttonStyle(.borderedProminent)
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

private struct CategoryEditorInline: View {
	@Binding var selection: Set<String>
	@EnvironmentObject var library: DeviceLibrary
	
	@State private var query = ""
	
	private var allUniverse: [String] {
		// Union of every known source so "Add" shows up immediately.
		var set = Set(library.allCategories)
		set.formUnion(library.categories)
		set.formUnion(selection) // include in-flight user additions
		return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}
	
	private var visible: [String] {
		guard !query.isEmpty else { return allUniverse }
		return allUniverse.filter { $0.localizedCaseInsensitiveContains(query) }
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			VStack(spacing: 8) {
				TextField("Add or search categories", text: $query)
					.textFieldStyle(.roundedBorder)
					.onSubmit {
						newCategory(query)
						query = ""                      // show full list again
					}
				
				HStack(spacing: 8) {
					HStack {
						Button("Add") {
							newCategory(query)
							query = ""
							// Add category to library/selection immediately, device on save
						}
						.disabled(query.isEmpty)
										
						Button("Clear") {
							query = ""
						}
						.disabled(query.isEmpty)
					}
				}
			}
			
			// Native macOS selection (blue highlight, no checkmarks)
			List(visible, id: \.self, selection: $selection) { name in
				Text(name)
					.lineLimit(1)
					.truncationMode(.tail)
					.tag(name)
			}
			.listStyle(.inset)
			.alternatingRowBackgrounds()
			.border(Color.gray)
			.environment(\.defaultMinListRowHeight, 22)
			.frame(minHeight: 180, maxHeight: 240)
		}
//		.frame(width: 250)
		.frame(maxWidth: .infinity, alignment: .leading) // grid row clamps this to 280 above
		.padding(.top, 4)
	}
	
	private func newCategory(_ categoryToAdd: String) {
		let newCategory = categoryToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !newCategory.isEmpty else { return }
		selection.insert(newCategory)
		library.categories.insert(newCategory)
	}
}

private struct InspectorSection<Content: View>: View {
	let title: String
	@ViewBuilder var content: Content
	
	init(title: String, @ViewBuilder content: () -> Content) {
		self.title = title
		self.content = content()
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title.uppercased())
				.font(.caption)
				.fontWeight(.semibold)
				.foregroundStyle(.secondary)
				.textCase(.uppercase)
				.padding(.bottom, 2)
			
			content
				.frame(maxWidth: .infinity, alignment: .leading)
			
//			Divider().padding(.top, 8)
		}
	}
}

private struct FieldLabel: View {
	let text: String
	
	init(_ text: String) {
		self.text = text
	}
	
	var body: some View {
		Text(text)
			.foregroundStyle(.secondary)
			.frame(width: 96, alignment: .trailing)
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
