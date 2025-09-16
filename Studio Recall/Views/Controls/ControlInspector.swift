//
//  ControlInspector.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ControlInspector: View {
	@ObservedObject var editableDevice: EditableDevice
	@Binding var selectedControlId: UUID?
	@Binding var isEditingRegion: Bool
	@Binding var activeRegionIndex: Int
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("Inspector").font(.headline)
			
			if let idx = selectedIndex {
				let binding = $editableDevice.device.controls[idx]
//				let control = binding.wrappedValue
				
				// MARK: Basics
				GroupBox("Basics") {
					VStack(alignment: .leading, spacing: 10) {
						HStack {
							Text("Name").frame(width: 80, alignment: .leading)
							TextField("Label", text: binding.name).textFieldStyle(.roundedBorder)
						}
						
						HStack {
							Picker("Type", selection: binding.type) {
								ForEach(ControlType.allCases, id: \.self) { t in
									Text(t.displayName).tag(t)
								}
							}
							.pickerStyle(.menu)   // dropdown, very compact

						}
					}
				}
				
				// MARK: Regions
				GroupBox("Regions") {
					VStack(alignment: .leading, spacing: 8) {
						if binding.regions.wrappedValue.isEmpty {
							Text("No region yet. Click Create to add one.")
								.font(.caption)
								.foregroundStyle(.secondary)
							
							Button("Create") {
								let s = ImageRegion.defaultSize
								if binding.wrappedValue.type == .concentricKnob {
									let outer = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.6),
													 y: max(0, binding.wrappedValue.y - s*0.6),
													 width: s*1.2, height: s*1.2),
										mapping: nil, shape: .circle
									)
									let inner = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.35),
													 y: max(0, binding.wrappedValue.y - s*0.35),
													 width: s*0.7, height: s*0.7),
										mapping: nil, shape: .circle
									)
									binding.regions.wrappedValue = [outer, inner]
								} else {
									let r = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.5),
													 y: max(0, binding.wrappedValue.y - s*0.5),
													 width: s, height: s),
										mapping: nil, shape: .circle
									)
									binding.regions.wrappedValue = [r]
								}
								isEditingRegion = true
							}
						} else {
							// Choose which ring to edit (concentric only)
							if binding.wrappedValue.type == .concentricKnob,
							   binding.regions.wrappedValue.count >= 2,
							   let pair = concentricPairIndices(binding.wrappedValue) {
								
								Picker("Edit region", selection: $activeRegionIndex) {
									Text("Outer").tag(pair.outer)
									Text("Inner").tag(pair.inner)
								}
								.pickerStyle(.segmented)
								.onAppear {
									// Default to “Outer” the first time (or after create/delete)
									if !binding.regions.wrappedValue.indices.contains(activeRegionIndex) {
										activeRegionIndex = pair.outer
									}
								}
								.onChange(of: binding.regions.wrappedValue) { _, _ in
									// Keep selection valid if regions are added/removed
									if !binding.regions.wrappedValue.indices.contains(activeRegionIndex) {
										activeRegionIndex = pair.outer
									}
								}
							}

							
							// Safety clamp (outer=0 or inner=1 if present)
							let idxSel = min(max(activeRegionIndex, 0), max(0, binding.regions.wrappedValue.count - 1))
							
							// Selected region binding
							let regionBinding = Binding<ImageRegion>(
								get: { binding.regions.wrappedValue[idxSel] },
								set: { binding.regions.wrappedValue[idxSel] = $0 }
							)
							
							HStack {
								Toggle("Edit", isOn: $isEditingRegion)
								Spacer()
								Button("Delete") {
									binding.regions.wrappedValue.remove(at: idxSel)
									activeRegionIndex = 0
								}
								.buttonStyle(.borderless)
							}
							
							Picker("Shape", selection: Binding(
								get: { regionBinding.wrappedValue.shape },
								set: { regionBinding.wrappedValue.shape = $0 }
							)) {
								Text("Rectangle").tag(ImageRegionShape.rect)
								Text("Circle").tag(ImageRegionShape.circle)
							}
							.pickerStyle(.segmented)
						}
					}
				}
				
				// MARK: Per-type configuration
				perTypeSection(binding: binding)
					.transition(.opacity.combined(with: .move(edge: .top)))
				
				// MARK: Mapping
				GroupBox("Image Mapping") {
					if isEditingRegion {
						VStack(alignment: .leading, spacing: 6) {
							Text("Turn off “Edit Region” to adjust mapping.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					} else {
						MappingEditor(control: binding, activeRegionIndex: $activeRegionIndex)
					}
				}
				.disabled(isEditingRegion)
				
				Spacer(minLength: 8)
				
				// MARK: Duplicate and Delete
				HStack {
					Button {
						// Duplicate selected control with a tiny offset and a fresh ID
						var copy = editableDevice.device.controls[idx]
						copy.id = UUID()
						copy.name = copy.name + " Copy"
						copy.x = min(1, copy.x + 0.02)
						copy.y = min(1, copy.y + 0.02)
						// Keep region if present (same rect is fine; user can adjust)
						editableDevice.device.controls.append(copy)
						selectedControlId = copy.id
					} label: {
						Label("Duplicate", systemImage: "plus.square.on.square")
					}
					.buttonStyle(.bordered)
					
					Spacer()
					
					Button(role: .destructive) {
						editableDevice.device.controls.remove(at: idx)
						selectedControlId = nil
					} label: {
						Label("Delete Control", systemImage: "trash")
					}
				}
			} else {
				Text("Select a control on the canvas.")
					.foregroundStyle(.secondary)
				Spacer()
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.layoutPriority(1)
		.padding()
#if os(macOS)
		.background(Color(NSColor.controlBackgroundColor))
#else
		.background(Color(UIColor.secondarySystemBackground))
#endif
	}
	
	private var selectedIndex: Int? {
		guard let id = selectedControlId else { return nil }
		return editableDevice.device.controls.firstIndex(where: { $0.id == id })
	}

	private func clampKnobValue(_ binding: Binding<Control>) {
		let minV = binding.knobMin.wrappedValue?.resolve(default: 0)
		let maxV = binding.knobMax.wrappedValue?.resolve(default: 1)
		guard let v = binding.value.wrappedValue, let lo = minV, let hi = maxV, hi > lo else { return }
		binding.value.wrappedValue = min(max(v, lo), hi)
	}
	
	func clampOuter(_ binding: Binding<Control>) {
		let lo = binding.outerMin.wrappedValue?.resolve(default: 0) ?? 0
		let hi = binding.outerMax.wrappedValue?.resolve(default: 1) ?? 1
		let v  = binding.outerValue.wrappedValue ?? lo
		binding.outerValue.wrappedValue = min(max(v, min(lo, hi)), max(lo, hi))
	}
	
	func clampInner(_ binding: Binding<Control>) {
		let lo = binding.innerMin.wrappedValue?.resolve(default: 0) ?? 0
		let hi = binding.innerMax.wrappedValue?.resolve(default: 1) ?? 1
		let v  = binding.innerValue.wrappedValue ?? lo
		binding.innerValue.wrappedValue = min(max(v, min(lo, hi)), max(lo, hi))
	}
	
	// MARK: - Per-type section
	@ViewBuilder
	private func perTypeSection(binding: Binding<Control>) -> some View {
		switch binding.wrappedValue.type {
			case .knob:
				GroupBox("Knob") {
					VStack(alignment: .leading, spacing: 8) {
						// Min / Max
						HStack {
							Text("Range").frame(width: 80, alignment: .leading)
							BoundField(bound: binding.knobMin, title: "Min", defaultFinite: 0)
							Text("…")
							BoundField(bound: binding.knobMax, title: "Max", defaultFinite: 1)
						}
						
						// VALUE (slider only if range is finite)
						do {
							let lo = binding.knobMin.wrappedValue?.resolve(default: 0) ?? 0
							let hi = binding.knobMax.wrappedValue?.resolve(default: 1) ?? 1
							let hasInf: Bool = {
								switch (binding.knobMin.wrappedValue, binding.knobMax.wrappedValue) {
									case (.some(.negInfinity), _), (.some(.posInfinity), _),
										(_, .some(.negInfinity)), (_, .some(.posInfinity)): return true
									default: return false
								}
							}()
							if hasInf || hi <= lo {
								HStack {
									Text("Value").frame(width: 80, alignment: .leading)
									NumberField(value: Binding(
										get: { binding.value.wrappedValue ?? lo },
										set: { binding.value.wrappedValue = $0 }
									))
								}
							} else {
								VSliderRow(
									title: "Value",
									value: Binding(
										get: { binding.value.wrappedValue ?? lo },
										set: { v in binding.value.wrappedValue = min(max(v, lo), hi) }
									),
									range: lo...hi,
									step: (hi - lo) / 100
								)
							}
						}
					}
				}
				
			case .steppedKnob:
				GroupBox("Stepped Knob") {
					VStack(alignment: .leading, spacing: 8) {
						HStack {
							Text("Steps").frame(minWidth: 60, alignment: .leading)
							Stepper(value: Binding(
								get: { max(2, (binding.options.wrappedValue?.count ?? 0)) },
								set: { newCount in
									var labels = binding.options.wrappedValue ?? Array(0..<newCount).map { "Step \($0)" }
									labels = Array(labels.prefix(newCount))
									binding.options.wrappedValue = labels
									binding.stepIndex.wrappedValue = min(binding.stepIndex.wrappedValue ?? 0, newCount-1)
								}
							), in: 2...24) {
								Text("\(binding.options.wrappedValue?.count ?? 0)")
							}
						}
						
						Text("Labels").font(.caption)
						TextField("e.g. 20Hz, 50Hz", text: Binding(
							get: { (binding.options.wrappedValue ?? []).joined(separator: ", ") },
							set: { text in
								let labels = text
									.split(separator: ",")
									.map { $0.trimmingCharacters(in: .whitespaces) }
									.filter { !$0.isEmpty }
								binding.options.wrappedValue = labels
								// Clamp step index to valid range (0…max(0, n-1))
								let n = labels.count
								let current = binding.stepIndex.wrappedValue ?? 0
								binding.stepIndex.wrappedValue = min(current, max(0, n - 1))
							}
						))
						.textFieldStyle(.roundedBorder)
						// Per-step table: Index • Label • Angle°
						VStack(spacing: 8) {
							HStack {
								Text("Index").font(.caption).foregroundStyle(.secondary)
									.frame(width: 44, alignment: .trailing)
								Text("Label").font(.caption).foregroundStyle(.secondary)
								Spacer()
								Text("Angle°").font(.caption).foregroundStyle(.secondary)
									.frame(width: 72, alignment: .trailing)
							}
							.padding(.horizontal, 6)
							
							// Hoist locals
							let labelArray = binding.options.wrappedValue ?? []
							let angleArray = binding.stepAngles.wrappedValue ?? []
							let count = max(labelArray.count, angleArray.count)
							
							ForEach(0..<count, id: \.self) { i in
								HStack {
									Text("\(i)")
										.frame(width: 44, alignment: .trailing)
										.monospacedDigit()
									
									// Label at index i
									TextField("Label #\(i)", text: Binding(
										get: {
											let labels = binding.options.wrappedValue ?? []
											return (i < labels.count) ? labels[i] : ""      // PURE: no writes here
										},
										set: { new in
											var labels = binding.options.wrappedValue ?? []
											if i >= labels.count {                          // grow only on SET
												labels += Array(repeating: "", count: i - labels.count + 1)
											}
											labels[i] = new
											binding.options.wrappedValue = labels          // <- safe: called from user event
										}
									))
									
									// Angle at index i
									TextField("0", value: Binding<Double>(
										get: {
											let angles = binding.stepAngles.wrappedValue ?? []
											return (i < angles.count) ? angles[i] : 0.0     // PURE: no writes here
										},
										set: { (new: Double) in
											var angles = binding.stepAngles.wrappedValue ?? []
											if i >= angles.count {
												angles += Array(repeating: 0.0, count: i - angles.count + 1)
											}
											angles[i] = new
											binding.stepAngles.wrappedValue = angles        // <- safe: user event
										}
									), formatter: angleFormatter)
									.frame(width: 72)
									.multilineTextAlignment(.trailing)
								}
								.padding(.horizontal, 6)
							}

						}
						.padding(.vertical, 4)

						HStack {
							Text("Value").frame(minWidth: 60, alignment: .leading)
							Stepper(value: Binding(
								get: { binding.stepIndex.wrappedValue ?? 0 },
								set: { binding.stepIndex.wrappedValue = $0 }
							), in: safeIndexRange(binding.options.wrappedValue)) {
								Text("\(binding.stepIndex.wrappedValue ?? 0)")
							}
							
//							let skLabels = binding.options.wrappedValue ?? []
//							Picker("Value", selection: Binding(
//								get: { binding.stepIndex.wrappedValue ?? 0 },
//								set: { binding.stepIndex.wrappedValue = $0 }
//							)) {
//								ForEach(skLabels.indices, id: \.self) { i in
//									Text(skLabels[i].isEmpty ? "#\(i)" : skLabels[i]).tag(i)
//								}
//							}
//							.pickerStyle(.menu)
							
							let labels = binding.options.wrappedValue ?? []
							Text("Current: \((labels.indices.contains(binding.stepIndex.wrappedValue ?? -1) ? labels[binding.stepIndex.wrappedValue ?? 0] : "#\(binding.stepIndex.wrappedValue ?? 0)"))")
							.font(.caption)
							.foregroundStyle(.secondary)

						}
						
					}
				}
				
			case .multiSwitch:
				GroupBox("Multi-Switch") {
					VStack(alignment: .leading, spacing: 8) {
						Text("Labels").font(.caption)
						TextField("e.g. Slow, Fast", text: Binding(
							get: { (binding.options.wrappedValue ?? []).joined(separator: ", ") },
							set: { text in
								let labels = text
									.split(separator: ",")
									.map { $0.trimmingCharacters(in: .whitespaces) }
									.filter { !$0.isEmpty }
								binding.options.wrappedValue = labels
								// Clamp selected index to valid range (0…max(0, n-1))
								let n = labels.count
								let current = binding.selectedIndex.wrappedValue ?? 0
								binding.selectedIndex.wrappedValue = min(current, max(0, n - 1))
							}
						))
						.textFieldStyle(.roundedBorder)
						
						HStack {
							Text("Selected").frame(minWidth: 60, alignment: .leading)
							Stepper(value: Binding(
								get: { binding.selectedIndex.wrappedValue ?? 0 },
								set: { binding.selectedIndex.wrappedValue = $0 }
							), in: safeIndexRange(binding.options.wrappedValue)) {
								Text("\(binding.selectedIndex.wrappedValue ?? 0)")
							}
							
							let msLabels = binding.options.wrappedValue ?? []
							
							Text("Current: \((msLabels.indices.contains(binding.selectedIndex.wrappedValue ?? -1) ? msLabels[binding.selectedIndex.wrappedValue ?? 0] : "#\(binding.selectedIndex.wrappedValue ?? 0)"))")
							.font(.caption)
							.foregroundStyle(.secondary)
						}
					}
				}
				
			case .button:
				GroupBox("Button") {
					Toggle("Pressed", isOn: Binding(
						get: { binding.isPressed.wrappedValue ?? false },
						set: { binding.isPressed.wrappedValue = $0 }
					))
				}
				
			case .light:
				GroupBox("Status Light") {
					VStack(alignment: .leading, spacing: 8) {
						Toggle("Manual On", isOn: Binding(
							get: { binding.isPressed.wrappedValue ?? false },
							set: { binding.isPressed.wrappedValue = $0 }
						))
						
						HStack {
							// small preview swatch
							RoundedRectangle(cornerRadius: 4)
								.fill((binding.onColor.wrappedValue ?? CodableColor(.green)).color)
								.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 1))
								.frame(width: 22, height: 14)
								.accessibilityHidden(true)
							
							Text("On Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.onColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.onColor.wrappedValue = $0 }
							))
						}
						HStack {
							// small preview swatch
							RoundedRectangle(cornerRadius: 4)
								.fill((binding.offColor.wrappedValue ?? CodableColor(.green)).color)
								.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 1))
								.frame(width: 22, height: 14)
								.accessibilityHidden(true)
							
							Text("Off Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.offColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.offColor.wrappedValue = $0 }
							))
						}
						// Link this light to another control
						Picker("Follow Control", selection: Binding(
							get: { binding.linkTarget.wrappedValue ?? UUID?.none as UUID? },
							set: { binding.linkTarget.wrappedValue = $0 }
						)) {
							Text("None").tag(UUID?.none as UUID?)
							ForEach(editableDevice.device.controls.filter { $0.id != binding.wrappedValue.id }) { c in
								Text(c.name.isEmpty ? c.type.displayName : c.name)
									.tag(Optional.some(c.id))
							}
						}
						.labelsHidden()
						.pickerStyle(.menu)
						
						// Optional: only for multi-switch sources, choose which position turns the light on
						if let target = editableDevice.device.controls.first(where: { $0.id == binding.linkTarget.wrappedValue }),
						   target.type == .multiSwitch {
							Picker("On when option", selection: Binding(
								get: { binding.linkOnIndex.wrappedValue ?? 0 },
								set: { binding.linkOnIndex.wrappedValue = $0 }
							)) {
								let labels = target.options ?? []
								ForEach(labels.indices, id: \.self) { i in
									Text(labels[i].isEmpty ? "#\(i)" : labels[i]).tag(i)
								}
							}
							.pickerStyle(.menu)
						}

						Toggle("Invert Link", isOn: Binding(
							get: { binding.linkInverted.wrappedValue ?? false },
							set: { binding.linkInverted.wrappedValue = $0 }
						))
					}
				}
				
			case .concentricKnob:
				GroupBox("Concentric Knob") {
					VStack(alignment: .leading, spacing: 8) {
						HStack {
							Text("Outer").frame(minWidth: 60, alignment: .leading)
							TextField("Gain", text: Binding(
								get: { binding.outerLabel.wrappedValue ?? "Gain" },
								set: { binding.outerLabel.wrappedValue = $0 }
							))
							.textFieldStyle(.roundedBorder)
						}
						HStack {
							Text("Inner").frame(minWidth: 60, alignment: .leading)
							TextField("Q", text: Binding(
								get: { binding.innerLabel.wrappedValue ?? "Q" },
								set: { binding.innerLabel.wrappedValue = $0 }
							))
							.textFieldStyle(.roundedBorder)
						}
						
						HStack {
							Text("Outer Range").frame(minWidth: 60, alignment: .leading)
							BoundField(bound: binding.outerMin,
									   title: "Min", defaultFinite: 0)
							Text("…")
							BoundField(bound: binding.outerMax,
									   title: "Max", defaultFinite: 1)
						}
						.onChange(of: binding.outerMin.wrappedValue) { _, _ in clampOuter(binding) }
						.onChange(of: binding.outerMax.wrappedValue) { _, _ in clampOuter(binding) }
						
						HStack {
							Text("Inner Range").frame(minWidth: 60, alignment: .leading)
							BoundField(bound: binding.innerMin,
									   title: "Min", defaultFinite: 0)
							Text("…")
							BoundField(bound: binding.innerMax,
									   title: "Max", defaultFinite: 1)
						}
						.onChange(of: binding.innerMin.wrappedValue) { _, _ in clampInner(binding) }
						.onChange(of: binding.innerMax.wrappedValue) { _, _ in clampInner(binding) }
						
						// OUTER value editor
						do {
							let lo = binding.outerMin.wrappedValue?.resolve(default: 0) ?? 0
							let hi = binding.outerMax.wrappedValue?.resolve(default: 1) ?? 1
							let hasInf = isInfinite(binding.outerMin.wrappedValue) || isInfinite(binding.outerMax.wrappedValue)
							if hasInf || hi <= lo {
								HStack {
									Text("Outer").frame(width: 80, alignment: .leading)
									NumberField(value: Binding(
										get: { binding.outerValue.wrappedValue ?? lo },
										set: { binding.outerValue.wrappedValue = $0 }
									))
								}
							} else {
								VSliderRow(
									title: "Outer",
									value: Binding(
										get: { binding.outerValue.wrappedValue ?? lo },
										set: { v in binding.outerValue.wrappedValue = min(max(v, lo), hi) }
									),
									range: lo...hi,
									step: (hi - lo) / 100
								)
							}
						}
						
						// INNER value editor
						do {
							let lo = binding.innerMin.wrappedValue?.resolve(default: 0) ?? 0
							let hi = binding.innerMax.wrappedValue?.resolve(default: 1) ?? 1
							let hasInf = isInfinite(binding.innerMin.wrappedValue) || isInfinite(binding.innerMax.wrappedValue)
							if hasInf || hi <= lo {
								HStack {
									Text("Inner").frame(width: 80, alignment: .leading)
									NumberField(value: Binding(
										get: { binding.innerValue.wrappedValue ?? lo },
										set: { binding.innerValue.wrappedValue = $0 }
									))
								}
							} else {
								VSliderRow(
									title: "Inner",
									value: Binding(
										get: { binding.innerValue.wrappedValue ?? lo },
										set: { v in binding.innerValue.wrappedValue = min(max(v, lo), hi) }
									),
									range: lo...hi,
									step: (hi - lo) / 100
								)
							}
						}
					}
				}
				
			case .litButton:
				GroupBox("Lit Button") {
					VStack(alignment: .leading, spacing: 8) {
						Toggle("Pressed", isOn: Binding(
							get: { binding.isPressed.wrappedValue ?? false },
							set: { binding.isPressed.wrappedValue = $0 }
						))
						Toggle("Lamp follows Press", isOn: Binding(
							get: { binding.lampFollowsPress.wrappedValue ?? true },
							set: { binding.lampFollowsPress.wrappedValue = $0 }
						))
						
						HStack {
							// small preview swatch
							RoundedRectangle(cornerRadius: 4)
								.fill((binding.lampOnColor.wrappedValue ?? CodableColor(.green)).color)
								.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 1))
								.frame(width: 22, height: 14)
								.accessibilityHidden(true)
							
							Text("On Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.lampOnColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.lampOnColor.wrappedValue = $0 }
							))
						}
						HStack {
							// small preview swatch
							RoundedRectangle(cornerRadius: 4)
								.fill((binding.lampOffColor.wrappedValue ?? CodableColor(.green)).color)
								.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 1))
								.frame(width: 22, height: 14)
								.accessibilityHidden(true)
							
							Text("Off Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.lampOffColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.lampOffColor.wrappedValue = $0 }
							))
						}
						// Link this light to another control
						Picker("Follow Control", selection: Binding(
							get: { binding.linkTarget.wrappedValue ?? UUID?.none as UUID? },
							set: { binding.linkTarget.wrappedValue = $0 }
						)) {
							Text("None").tag(UUID?.none as UUID?)
							ForEach(editableDevice.device.controls.filter { $0.id != binding.wrappedValue.id }) { c in
								Text(c.name.isEmpty ? c.type.displayName : c.name)
									.tag(Optional.some(c.id))
							}
						}
						.labelsHidden()
						.pickerStyle(.menu)
						
						// Optional: only for multi-switch sources, choose which position turns the light on
						if let target = editableDevice.device.controls.first(where: { $0.id == binding.linkTarget.wrappedValue }),
						   target.type == .multiSwitch {
							Picker("On when option", selection: Binding(
								get: { binding.linkOnIndex.wrappedValue ?? 0 },
								set: { binding.linkOnIndex.wrappedValue = $0 }
							)) {
								let labels = target.options ?? []
								ForEach(labels.indices, id: \.self) { i in
									Text(labels[i].isEmpty ? "#\(i)" : labels[i]).tag(i)
								}
							}
							.pickerStyle(.menu)
						}

					}
				}
		}
	}
	
}

// MARK: - Mapping editor

private struct MappingEditor: View {
	@Binding var control: Control
	@Binding var activeRegionIndex: Int
	
	private enum Kind: String, CaseIterable, Identifiable {
		case none = "None"
		case rotate = "Rotate"
		case brightness = "Brightness"
		case opacity = "Opacity"
		case translate = "Translate"
		case flip3D = "Flip (3D)"
		case sprite = "Sprite (Poses)"
		var id: String { rawValue }
	}
	
	private var hasRegions: Bool { !(control.regions.isEmpty) }
	
	private var regionIndexSafe: Int {
		min(max(activeRegionIndex, 0), max(0, control.regions.count - 1))
	}
	
	private var regionBinding: Binding<ImageRegion> {
		Binding<ImageRegion>(
			get: {
				if control.regions.indices.contains(regionIndexSafe) {
					return control.regions[regionIndexSafe]
				} else {
					// create a default region if missing
					let s: CGFloat = 0.10
					var r = CGRect(x: max(0, control.x - s*0.5),
								   y: max(0, control.y - s*0.5),
								   width: s, height: s)
					r.origin.x = min(r.origin.x, 1 - r.size.width)
					r.origin.y = min(r.origin.y, 1 - r.size.height)
					let new = ImageRegion(rect: r, mapping: nil, shape: .rect)
					var c = control; if c.regions.isEmpty { c.regions = [new] } else { c.regions.append(new) }
					control = c
					return control.regions[regionIndexSafe]
				}
			},
			set: { new in
				var c = control
				if c.regions.indices.contains(regionIndexSafe) { c.regions[regionIndexSafe] = new }
				control = c
			}
		)
	}
	
	// Two-way binding to the *selected region’s* mapping kind
	private var kindBinding: Binding<Kind> {
		Binding(
			get: {
				let m = regionBinding.wrappedValue.mapping
				guard let m else { return .none }
				switch m.kind {
					case .rotate:     return .rotate
					case .brightness: return .brightness
					case .opacity:    return .opacity
					case .translate:  return .translate
					case .flip3D:     return .flip3D
					case .sprite:     return .sprite
				}
			},
			set: { new in
				var region = regionBinding.wrappedValue
				let current = region.mapping?.kind
				switch new {
					case .none:
						region.mapping = nil
						
					case .rotate:
						if current != .rotate {
							region.mapping = .rotate(
								min: -135, max: 135,
								pivot: CGPoint(x: 0.5, y: 0.5),
								taper: .linear
							)
						}
						
					case .brightness:
						if current != .brightness {
							region.mapping = .brightness(RangeD(lower: 0.0, upper: 0.7))
						}
						
					case .opacity:
						if current != .opacity {
							region.mapping = .opacity(RangeD(lower: 0.25, upper: 1.0))
						}
						
					case .translate:
						region.mapping = .translate(from: CGPoint(x: -0.15, y: 0),
													to:   CGPoint(x:  0.15, y: 0))
						
					case .flip3D:
						region.mapping = .flip3D()
						
					case .sprite:
						if region.mapping == nil {
							region.mapping = VisualMapping.sprite(
								atlasPNG: nil,
								cols: (control.type == .multiSwitch || control.type == .button) ? 2 : 1,
								rows: 1,
								pivot: CGPoint(x: 0.5, y: 0.88),
								spritePivot: CGPoint(x: 0.5, y: 0.92),
								scale: 1.0,
								mode: .frames
							)
						}

				}
				regionBinding.wrappedValue = region
			}
		)
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if !hasRegions {
				Text("Create a region first, then choose a mapping.")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				HStack {
					Text("Kind").frame(width: 80, alignment: .leading)
					Picker("", selection: kindBinding) {
						ForEach(Kind.allCases) { k in Text(k.rawValue).tag(k) }
					}
					.labelsHidden()
				}
				
				if let m = regionBinding.wrappedValue.mapping {
					switch m.kind {
						case .rotate:
							VStack(alignment: .leading, spacing: 8) {
								// keep the sub-editor for Taper / Min° / Max° / Pivot
								RotateEditor(mapping: Binding(
									get: { regionBinding.wrappedValue.mapping! },
									set: { var r = regionBinding.wrappedValue; r.mapping = $0; regionBinding.wrappedValue = r }
								))
								
								Divider().padding(.vertical, 4)
								
								// NEW: Preview buttons (we are in MappingEditor so we have `control` and `activeRegionIndex`)
								HStack(spacing: 8) {
									Text("Preview").frame(width: 80, alignment: .leading)
									
									Button("Min") {
										if control.type == .concentricKnob {
											if regionIndexSafe == 0 {
												let lo = control.outerMin?.resolve(default: 0) ?? 0
												control.outerValue = lo
											} else {
												let lo = control.innerMin?.resolve(default: 0) ?? 0
												control.innerValue = lo
											}
										} else { // regular knob
											let lo = control.knobMin?.resolve(default: 0) ?? 0
											control.value = lo
										}
									}
									
									Button("Max") {
										if control.type == .concentricKnob {
											if regionIndexSafe == 0 {
												let hi = control.outerMax?.resolve(default: 1) ?? 1
												control.outerValue = hi
											} else {
												let hi = control.innerMax?.resolve(default: 1) ?? 1
												control.innerValue = hi
											}
										} else {
											let hi = control.knobMax?.resolve(default: 1) ?? 1
											control.value = hi
										}
									}
									
									Button("Center") {
										if control.type == .concentricKnob {
											if regionIndexSafe == 0 {
												let lo = control.outerMin?.resolve(default: 0) ?? 0
												let hi = control.outerMax?.resolve(default: 1) ?? 1
												control.outerValue = (lo + hi) / 2
											} else {
												let lo = control.innerMin?.resolve(default: 0) ?? 0
												let hi = control.innerMax?.resolve(default: 1) ?? 1
												control.innerValue = (lo + hi) / 2
											}
										} else {
											let lo = control.knobMin?.resolve(default: 0) ?? 0
											let hi = control.knobMax?.resolve(default: 1) ?? 1
											control.value = (lo + hi) / 2
										}
									}
								}
								.buttonStyle(.bordered)
							}
						case .brightness, .opacity:
							ScalarEditor(mapping: Binding(
								get: { regionBinding.wrappedValue.mapping! },
								set: { var r = regionBinding.wrappedValue; r.mapping = $0; regionBinding.wrappedValue = r }
							))
						case .translate:
							TranslateEditor(mapping: Binding(
								get: { regionBinding.wrappedValue.mapping! },
								set: { var r = regionBinding.wrappedValue; r.mapping = $0; regionBinding.wrappedValue = r }
							))
						case .flip3D:
							FlipEditor(mapping: Binding(
								get: { regionBinding.wrappedValue.mapping! },
								set: { var r = regionBinding.wrappedValue; r.mapping = $0; regionBinding.wrappedValue = r }
							), control: $control)
						case .sprite:
							SpriteEditor(region: regionBinding, control: $control)
					}
					
					HStack {
						Button("Preset: Knob (Rotate)") { kindBinding.wrappedValue = .rotate }
						Button("Preset: Lamp (Opacity)") { kindBinding.wrappedValue = .opacity }
						Button("Preset: Flip Toggle (3D)") { kindBinding.wrappedValue = .flip3D }
					}
					.buttonStyle(.bordered)
				}
			}
		}
		.onAppear { migrateIfNeeded() }
		.onChange(of: control.id) { _, _ in migrateIfNeeded() }
	}
	
	// Migrate any embedded sprites in the *selected* region
	private func migrateIfNeeded() {
		if var m = regionBinding.wrappedValue.mapping,
		   (m.spriteAtlasPNG != nil) || ((m.spriteFrames?.isEmpty == false)) {
			SpriteLibrary.shared.migrateEmbeddedSprites(in: &m, suggestedName: control.name)
			var r = regionBinding.wrappedValue; r.mapping = m; regionBinding.wrappedValue = r
		}
	}
}

private func safeIndexRange(_ options: [String]?) -> ClosedRange<Int> {
	let n = max(1, options?.count ?? 0)   // empty → 1 so range becomes 0...0
	return 0...(n - 1)
}

private func concentricPairIndices(_ c: Control) -> (outer: Int, inner: Int)? {
	guard c.type == .concentricKnob, c.regions.count >= 2 else { return nil }
	// Pick the two largest regions and call the larger one “outer”
	let sorted = c.regions.enumerated()
		.sorted { ($0.element.rect.width * $0.element.rect.height) >
			($1.element.rect.width * $1.element.rect.height) }
	let first = sorted[0].offset
	let second = sorted[1].offset
	// outer = bigger, inner = the other of the first two
	return (outer: first, inner: second)
}

private let angleFormatter: NumberFormatter = {
	let f = NumberFormatter()
	f.numberStyle = .decimal
	f.maximumFractionDigits = 2
	return f
}()

private extension Array {
	subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Sub-editors

// In MappingEditor, inside the `if let m = control.region?.mapping { switch m.kind { case .rotate: ... } }` block,
// update the RotateEditor to include a taper picker:

private struct RotateEditor: View {
	@Binding var mapping: VisualMapping
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			// NEW: taper selector
			HStack {
				Text("Taper").frame(width: 80, alignment: .leading)
				Picker("", selection: Binding(
					get: { mapping.taper ?? .linear },
					set: { mapping.taper = $0 }
				)) {
					Text("Linear").tag(ValueTaper.linear)
					Text("Decibels (−∞…0 dB)").tag(ValueTaper.decibel)
				}
				.labelsHidden()
			}
			
			HStack {
				Text("Min°").frame(width: 80, alignment: .leading)
				NumberField(value: Binding(
					get: { mapping.degMin ?? -135 },
					set: { mapping.degMin = $0 }
				))
				Text("Max°").frame(width: 60, alignment: .trailing)
				NumberField(value: Binding(
					get: { mapping.degMax ?? 135 },
					set: { mapping.degMax = $0 }
				))
			}

			HStack {
				Text("Pivot X").frame(width: 80, alignment: .leading)
				NumberField(value: Binding(
					get: { Double(mapping.pivot?.x ?? 0.5) },
					set: { mapping.pivot = CGPoint(x: CGFloat($0), y: CGFloat(mapping.pivot?.y ?? 0.5)) }
				))
				Text("Y").frame(width: 20, alignment: .trailing)
				NumberField(value: Binding(
					get: { Double(mapping.pivot?.y ?? 0.5) },
					set: { mapping.pivot = CGPoint(x: CGFloat(mapping.pivot?.x ?? 0.5), y: CGFloat($0)) }
				))
			}
		}
	}
}


private struct ScalarEditor: View {
	@Binding var mapping: VisualMapping
	
	var body: some View {
		HStack {
			Text("Range").frame(width: 80, alignment: .leading)
			NumberField(value: Binding(
				get: { mapping.scalarRange?.lower ?? 0 },
				set: { mapping.scalarRange = RangeD(lower: $0, upper: mapping.scalarRange?.upper ?? 1) }
			))
			Text("…").foregroundStyle(.secondary)
			NumberField(value: Binding(
				get: { mapping.scalarRange?.upper ?? 1 },
				set: { mapping.scalarRange = RangeD(lower: mapping.scalarRange?.lower ?? 0, upper: $0) }
			))
		}
	}
}
	
	private struct TranslateEditor: View {
		@Binding var mapping: VisualMapping
		var body: some View {
			VStack(alignment: .leading, spacing: 6) {
				Text("Translate (region-local, −1…+1 of region size)").font(.caption)
				
				HStack {
					Text("From X").frame(width: 80, alignment: .leading)
					NumberField(value: Binding(
						get: { Double(mapping.transStart?.x ?? 0) },
						set: { x in
							var m = mapping; m.transStart = CGPoint(x: CGFloat(x), y: m.transStart?.y ?? 0); mapping = m
						}
					))
					Text("Y")
					NumberField(value: Binding(
						get: { Double(mapping.transStart?.y ?? 0) },
						set: { y in
							var m = mapping; m.transStart = CGPoint(x: m.transStart?.x ?? 0, y: CGFloat(y)); mapping = m
						}
					))
				}
				
				HStack {
					Text("To X").frame(width: 80, alignment: .leading)
					NumberField(value: Binding(
						get: { Double(mapping.transEnd?.x ?? 0) },
						set: { x in
							var m = mapping; m.transEnd = CGPoint(x: CGFloat(x), y: m.transEnd?.y ?? 0); mapping = m
						}
					))
					Text("Y")
					NumberField(value: Binding(
						get: { Double(mapping.transEnd?.y ?? 0) },
						set: { y in
							var m = mapping; m.transEnd = CGPoint(x: m.transEnd?.x ?? 0, y: CGFloat(y)); mapping = m
						}
					))
				}
				
				HStack {
					Button("Preset: Horizontal 3-pos") {
						var m = mapping; m.transStart = CGPoint(x: -0.18, y: 0); m.transEnd = CGPoint(x: 0.18, y: 0); mapping = m
					}
					Button("Preset: Vertical 3-pos") {
						var m = mapping; m.transStart = CGPoint(x: 0, y: -0.18); m.transEnd = CGPoint(x: 0, y: 0.18); mapping = m
					}
				}
			}
		}
	}
	
private struct FlipEditor: View {
	@Binding var mapping: VisualMapping
	@Binding var control: Control   // for option labels / selected index (multiswitch)
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			// A short how-to for Flip (3D)
			Text("Flip (3D) tips: Crop mostly the lever; set the Pivot at its hinge; for multiswitches, enter Tilts per option and pick which option the photo shows (Reference).")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.bottom, 2)
			// Core flip parameters
			HStack {
				Text("Min°").frame(width: 80, alignment: .leading)
				NumberField(value: Binding(
					get: { mapping.tiltMin ?? -22 },
					set: { v in mapping.tiltMin = v }
				))
				Text("Max°").frame(width: 60, alignment: .trailing)
				NumberField(value: Binding(
					get: { mapping.tiltMax ?? 22 },
					set: { v in mapping.tiltMax = v }
				))
			}
			HStack {
				Text("Hinge").frame(width: 80, alignment: .leading)
				Picker("", selection: Binding(
					get: { mapping.tiltAxis ?? .x },
					set: { mapping.tiltAxis = $0 }
				)) {
					Text("Up/Down").tag(VisualMapping.Axis3D.x)
					Text("Left/Right").tag(VisualMapping.Axis3D.y)
				}
				.labelsHidden()
			}
			// Pivot row (inside FlipEditor)
			// Toggle gizmo
			Toggle("Show pivot gizmo", isOn: Binding(
				get: { mapping.showGizmo ?? false },
				set: { mapping.showGizmo = $0 }
			))
			HStack {
				Text("Pivot X").frame(width: 80, alignment: .leading)
				NumberField(value: Binding(
					get: { Double(mapping.pivot?.x ?? 0.5) },
					set: { x in var p = mapping.pivot ?? CGPoint(x: 0.5, y: 0.85); p.x = CGFloat(x); mapping.pivot = p }
				))
				.help("0 = left edge of the cropped patch, 1 = right edge. Place where the hinge sits horizontally.")
				
				Text("Y").frame(width: 20, alignment: .trailing)
				NumberField(value: Binding(
					get: { Double(mapping.pivot?.y ?? 0.85) },
					set: { y in var p = mapping.pivot ?? CGPoint(x: 0.5, y: 0.85); p.y = CGFloat(y); mapping.pivot = p }
				))
				.help("0 = top of the patch, 1 = bottom. Set near the lever’s hinge vertically (e.g. 0.85–0.92).")
			}
			HStack {
				Text("Perspective").frame(width: 80, alignment: .leading)
				Slider(value: Binding(
					get: { mapping.perspective ?? 0.6 },
					set: { mapping.perspective = $0 }
				), in: 0...1)
				Text(String(format: "%.2f", mapping.perspective ?? 0.6))
					.monospacedDigit()
					.frame(width: 44, alignment: .trailing)
			}
			
			// Multiswitch-specific: per-option tilts + reference pose
			if control.type == .multiSwitch {
				Divider().padding(.vertical, 4)
				Text("If you enter Tilts, those exact angles (relative to the Reference option = 0°) are used for each position. Min°/Max° are only used as a fallback curve when Tilts are empty (or for non-multiswitch controls).")
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
				HStack(alignment: .firstTextBaseline) {
					Text("Tilts (°, by option)").frame(width: 120, alignment: .leading)
					TextField("", text: Binding(
						get: {
							let list = mapping.tiltByIndex ?? []
							return list.map { String(format: "%.1f", $0) }.joined(separator: ", ")
						},
						set: { s in
							let nums = s
								.split(separator: ",")
								.map { $0.trimmingCharacters(in: .whitespaces) }
								.compactMap(Double.init)
							mapping.tiltByIndex = nums
						}
					))
					.textFieldStyle(.roundedBorder)
				}
				
				HStack {
					Text("Reference option").frame(width: 120, alignment: .leading)
					Picker("", selection: Binding(
						get: { mapping.tiltRefIndex ?? 0 },
						set: { mapping.tiltRefIndex = $0 }
					)) {
						let labels = control.options ?? []
						ForEach(labels.indices, id: \.self) { i in
							Text(labels[i]).tag(i)
						}
					}
					.labelsHidden()
					
					Button("Use current") {
						mapping.tiltRefIndex = control.selectedIndex ?? 0
					}
					.buttonStyle(.bordered)
					.help("Sets the photographed faceplate pose (0°) to the currently selected option.")
				}
			}
		}
	}
}

private struct SpriteEditor: View {
	@Binding var region: ImageRegion
	@Binding var control: Control
	
	@State private var showOpen = false
	@State private var showLibrarySheet = false
	
	// Derived binding to mapping
	var mapping: Binding<VisualMapping> {
		Binding(
			get: { region.mapping ?? VisualMapping.sprite(
				atlasPNG: nil,
				cols: 1,
				rows: 1,
				pivot: CGPoint(x: 0.5, y: 0.88),
				spritePivot: CGPoint(x: 0.5, y: 0.92),
				scale: 1.0,
				mode: .frames
			) },
			set: { region.mapping = $0 }
		)
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			SourcePicker(mapping: mapping, showLibrarySheet: $showLibrarySheet)
			
			if mapping.wrappedValue.spriteMode == .atlasGrid {
				AtlasEditor(mapping: mapping, control: $control)
			} else {
				FramesEditor(mapping: mapping, control: $control)
			}
			
			SpritePivotEditor(mapping: mapping)
		}
	}
}

// MARK: - SourcePicker
private struct SourcePicker: View {
	var mapping: Binding<VisualMapping>
	@Binding var showLibrarySheet: Bool
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Picker("Source", selection: Binding(
					get: { mapping.wrappedValue.spriteMode },
					set: { mapping.wrappedValue.spriteMode = $0 }
				)) {
					Text("Grid Atlas").tag(VisualMapping.SpriteMode.atlasGrid)
					Text("Individual Frames").tag(VisualMapping.SpriteMode.frames)
				}
				.labelsHidden()
			}
			.frame(width: 160)
			
			Text("Sprites show a pose image per switch position using a grid-based atlas. Set the pivot where the hinge meets the lever, then align the sprite’s pivot so the image sits correctly.")
				.font(.caption)
				.foregroundStyle(.secondary)
			
			HStack {
				Text("Library").frame(width: 80, alignment: .leading)
				Picker("", selection: Binding(
					get: { mapping.wrappedValue.spriteAssetId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
					set: { newId in mapping.wrappedValue.spriteAssetId = newId }
				)) {
					Text("— none —").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
					ForEach(SpriteLibrary.shared.allAssets()) { asset in
						Text(asset.name).tag(asset.id)
					}
				}
				.labelsHidden()
				
				Button("Browse…") { showLibrarySheet = true }
					.buttonStyle(.bordered)
					.help("Choose from pre-installed and imported sprites")
					.sheet(isPresented: $showLibrarySheet) {
						LibraryBrowserSheet { assetId in
							mapping.wrappedValue.spriteAssetId = assetId
							showLibrarySheet = false
						}
						.frame(width: 560, height: 420)
					}
			}
		}
	}
}
	
// MARK: - AtlasEditor
private struct AtlasEditor: View {
	var mapping: Binding<VisualMapping>
	@Binding var control: Control
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			// Atlas loader (macOS)
			HStack {
				Text("Atlas").frame(width: 80, alignment: .leading)
				Button(mapping.wrappedValue.spriteAssetId == nil ? "Choose Image…" : "Replace Image…") {
#if os(macOS)
					let p = NSOpenPanel()
					if #available(macOS 11.0, *) {
						p.allowedContentTypes = [UTType.png]
					} else {
						p.allowedFileTypes = ["png"]
					}
					p.allowsMultipleSelection = false
					if p.runModal() == .OK, let url = p.url, let d = try? Data(contentsOf: url) {
						mapping.wrappedValue.spriteMode = .atlasGrid
						if let asset = try? SpriteLibrary.shared.importAtlasGrid(
							name: url.deletingPathExtension().lastPathComponent,
							data: d,
							cols: mapping.wrappedValue.spriteCols ?? 1,
							rows: mapping.wrappedValue.spriteRows ?? 1
						) {
							mapping.wrappedValue.spriteAssetId = asset.id
							mapping.wrappedValue.spriteAtlasPNG = d
							
						}
					}
					
#endif
				}
			}
			
			Divider()
			
			HStack {
				Text("Layout").frame(width: 80, alignment: .leading)
				Picker("", selection: $control.spriteLayout) {
					Text("Vertical").tag(Control.SpriteLayout.vertical)
					Text("Horizontal").tag(Control.SpriteLayout.horizontal)
				}
				.pickerStyle(.segmented)
			}
			if let frameCount = mapping.wrappedValue.spriteFrames?.count, frameCount > 0 {
				FrameMappingEditor(frameCount: frameCount, mapping: mapping.wrappedValue, control: $control)
			}
			
			HStack {
				Text("Grid").frame(width: 80, alignment: .leading)
				Stepper("Cols: \(mapping.wrappedValue.spriteCols ?? 1)",
						value: Binding(get: { mapping.wrappedValue.spriteCols ?? 1 },
									   set: { mapping.wrappedValue.spriteCols = $0 }),
						in: 1...16)
				Stepper("Rows: \(mapping.wrappedValue.spriteRows ?? 1)",
						value: Binding(get: { mapping.wrappedValue.spriteRows ?? 1 },
									   set: { mapping.wrappedValue.spriteRows = $0 }),
						in: 1...16)
			}
		}
	}
}

// MARK: - FramesEditor
private struct FramesEditor: View {
	var mapping: Binding<VisualMapping>
	@Binding var control: Control
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Frames").frame(width: 80, alignment: .leading)
					Button("Add…") {
#if os(macOS)
						let p = NSOpenPanel()
						if #available(macOS 11.0, *) {
							p.allowedContentTypes = [UTType.png, UTType.jpeg, UTType.tiff, UTType.heic]
						} else {
							p.allowedFileTypes = ["png","jpg","jpeg","tiff"]
						}
						p.allowsMultipleSelection = true
						if p.runModal() == .OK {
							let newFrames = p.urls.compactMap { try? Data(contentsOf: $0) }
							if !newFrames.isEmpty, let firstURL = p.urls.first {
								do {
									let asset = try SpriteLibrary.shared.importFrames(
										name: firstURL.deletingPathExtension().lastPathComponent,
										frames: newFrames
									)
									mapping.wrappedValue.spriteMode = .frames
									mapping.wrappedValue.spriteAssetId = asset.id
									mapping.wrappedValue.spriteFrames = SpriteLibrary.shared.loadFrameData(for: asset)
									mapping.wrappedValue.spritePivot = asset.spritePivot
									mapping.wrappedValue.normalizeSpriteIndices()
									mapping.wrappedValue.ensureSpriteOffsets()
									print("Uploaded \(newFrames.count) frames → asset \(asset.id)")
								} catch {
									print("❌ Failed to import frames: \(error)")
								}
							}
						}
#endif
					}
					
					
					Button("Clear Frames") {
						mapping.wrappedValue.spriteFrames = []
						mapping.wrappedValue.spriteIndices = []
					}
					.buttonStyle(.bordered)
				}
				
				if mapping.wrappedValue.spriteMode == .frames,
				   let frames = mapping.wrappedValue.spriteFrames, !frames.isEmpty {
					ScrollView(.horizontal, showsIndicators: true) {
						HStack(spacing: 12) {
							ForEach(frames.indices, id: \.self) { idx in
								FrameEditor(idx: idx, mapping: mapping, frames: frames, control: $control)
							}
						}
						.padding(.horizontal, 4)
					}
					.frame(height: 160)
				}
			}
		}
	}

// MARK: - FrameEditor
private struct FrameEditor: View {
	let idx: Int
	var mapping: Binding<VisualMapping>
	let frames: [Data]
	@Binding var control: Control
	
	var body: some View {
		VStack(spacing: 6) {
			// Thumbnail
			if let nsImage = NSImage(data: frames[idx]) {
				Image(nsImage: nsImage)
					.resizable()
					.interpolation(.high)
					.antialiased(true)
					.frame(width: 48, height: 48)
				//													.border(Color.gray, width: 1)
					.clipShape(RoundedRectangle(cornerRadius: 4))
			} else {
				Rectangle()
					.fill(Color.gray.opacity(0.2))
					.frame(width: 48, height: 48)
					.overlay(Text("?"))
			}
			
			// Value field
			TextField("Index",
				value: Binding(
					get: { mapping.wrappedValue.spriteIndices?[idx] ?? idx },
					set: { newVal in
						if mapping.wrappedValue.spriteIndices == nil {
							mapping.wrappedValue.normalizeSpriteIndices()
							mapping.wrappedValue.spriteIndices = Array(0..<frames.count)
						}
						mapping.wrappedValue.spriteIndices?[idx] = newVal
					}),
				formatter: NumberFormatter())
			.frame(width: 50)
			
			HStack(spacing: 4) {
				Text("X")
				Stepper("", value: Binding(
					get: { Int((mapping.wrappedValue.spriteOffsets?[idx].x ?? 0) * 100) },
					set: { newVal in
						mapping.wrappedValue.ensureSpriteOffsets()
						mapping.wrappedValue.spriteOffsets?[idx].x = CGFloat(newVal) / 100.0
					}), in: -50...50)
				Text("Y")
				Stepper("", value: Binding(
					get: { Int((mapping.wrappedValue.spriteOffsets?[idx].y ?? 0) * 100) },
					set: { newVal in
						mapping.wrappedValue.ensureSpriteOffsets()
						mapping.wrappedValue.spriteOffsets?[idx].y = CGFloat(newVal) / 100.0
					}), in: -50...50)
			}
			.font(.caption)
		}
		.padding(6)
		.background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor)))
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke(
					(control.selectedIndex == (mapping.wrappedValue.spriteIndices?[idx] ?? idx))
					? Color.accentColor : Color.gray.opacity(0.3),
					lineWidth: (control.selectedIndex == (mapping.wrappedValue.spriteIndices?[idx] ?? idx)) ? 2 : 1
				)
		)
	}
}

// MARK: - SpritePivotEditor
private struct SpritePivotEditor: View {
	var mapping: Binding<VisualMapping>
	
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			// Pivots: region vs sprite
			HStack {
				Text("Rotate").frame(width: 80, alignment: .leading)
				Picker("", selection: Binding(
					get: { (mapping.wrappedValue.spriteQuarterTurns ?? 0) % 4 },
					set: { mapping.wrappedValue.spriteQuarterTurns = $0 % 4 }
				)) {
					Text("0°").tag(0)
					Text("90°").tag(1)
					Text("180°").tag(2)
					Text("270°").tag(3)
				}
				.pickerStyle(.segmented)
			}
			.help("Rotates the sprite around the Sprite Pivot by 90° steps. Use 90°/270° for horizontal switches.")
			
			HStack {
				Text("Region Pivot").frame(width: 100, alignment: .leading)
				NumberField(value: Binding(get: { Double(mapping.wrappedValue.pivot?.x ?? 0.5) },
										   set: { mapping.wrappedValue.pivot?.x = CGFloat($0) }))
				Text("Y")
				NumberField(value: Binding(get: { Double(mapping.wrappedValue.pivot?.y ?? 0.85) },
										   set: { mapping.wrappedValue.pivot?.y = CGFloat($0) }))
			}
			.help("Region Pivot: 0…1 within the cropped patch (where the real hinge sits).")
			
			HStack {
				Text("Sprite Pivot").frame(width: 100, alignment: .leading)
				NumberField(value: Binding(get: { Double(mapping.wrappedValue.spritePivot?.x ?? 0.5) },
										   set: { mapping.wrappedValue.spritePivot?.x = CGFloat($0) }))
				Text("Y")
				NumberField(value: Binding(get: { Double(mapping.wrappedValue.spritePivot?.y ?? 0.9) },
										   set: { mapping.wrappedValue.spritePivot?.y = CGFloat($0) }))
			}
			.help("Sprite Pivot: 0…1 within a single frame image (e.g., bottom of lever). Make these two pivots coincide.")
		}
	}
}
			
//											// Reorder / delete
//											HStack(spacing: 6) {
//												Button("↑") {
//													guard idx > 0 else { return }
//													var f = mapping.wrappedValue.spriteFrames!
//													f.swapAt(idx, idx - 1)
//													mapping.wrappedValue.spriteFrames = f
//													mapping.wrappedValue.normalizeSpriteIndices()
//													mapping.wrappedValue.spriteOffsets?.swapAt(idx, idx - 1)
//												}.buttonStyle(.plain)
//												
//												Button("↓") {
//													guard idx < frames.count - 1 else { return }
//													var f = mapping.wrappedValue.spriteFrames!
//													f.swapAt(idx, idx + 1)
//													mapping.wrappedValue.spriteFrames = f
//													mapping.wrappedValue.normalizeSpriteIndices()
//													mapping.wrappedValue.spriteOffsets?.swapAt(idx, idx + 1)
//												}.buttonStyle(.plain)
//												
//												Button("–") {
//													var f = mapping.wrappedValue.spriteFrames!
//													f.remove(at: idx)
//													mapping.wrappedValue.spriteFrames = f
//													mapping.wrappedValue.normalizeSpriteIndices()
//													mapping.wrappedValue.spriteOffsets?.remove(at: idx)
//												}.buttonStyle(.plain)
//											}
//											// Pivot nudges for this frame
//											VStack(alignment: .leading, spacing: 2) {
//												HStack {
//													Text("Nudge X")
//													Stepper(
//														"X: \(Int((mapping.wrappedValue.spriteOffsets?[idx].x ?? 0) * 100))%",
//														value: Binding(
//															get: { Int((mapping.wrappedValue.spriteOffsets?[idx].x ?? 0) * 100) },
//															set: { newVal in
//																ensureOffsets()
//																mapping.wrappedValue.spriteOffsets?[idx].x = CGFloat(newVal) / 100.0
//															}
//														),
//														in: -50...50
//													) {
//														Text("X")
//													}
//												}
//												HStack {
//													Text("Nudge Y")
//													Stepper(
//														"Y: \(Int((mapping.wrappedValue.spriteOffsets?[idx].y ?? 0) * 100))%",
//														value: Binding(
//															get: { Int((mapping.wrappedValue.spriteOffsets?[idx].y ?? 0) * 100) },
//															set: { newVal in
//																ensureOffsets()
//																mapping.wrappedValue.spriteOffsets?[idx].y = CGFloat(newVal) / 100.0
//															}
//														),
//														in: -50...50
//													) {
//														Text("Y")
//													}
//												}
//											}
//											.font(.caption)
//
//										}
//										.padding(6)
//										.background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.windowBackgroundColor)))
//										.overlay(
//											RoundedRectangle(cornerRadius: 6)
//												.stroke(
//													(control.selectedIndex == (mapping.wrappedValue.spriteIndices?[idx] ?? idx))
//													? Color.accentColor
//													: Color.gray.opacity(0.3),
//													lineWidth: (control.selectedIndex == (mapping.wrappedValue.spriteIndices?[idx] ?? idx)) ? 2 : 1
//												)
//										)
//
//									}
//								}
//								.padding(.horizontal, 4)
//							}
//							.frame(height: 180)
//						}
//					}
//
//				}
//
//				
//				
//				Text("Rotation happens around the Sprite Pivot. If the lever ‘walks’ when you rotate, move the Sprite Pivot onto the hinge.")
//					.font(.caption)
//					.foregroundStyle(.secondary)
//				
//				// Tiny live preview (optional)
//				if let data = mapping.wrappedValue.spriteAtlasPNG,
//				   let ns = NSImage(data: data) {
//					HStack {
//						Text("Preview").frame(width: 80, alignment: .leading)
//						Image(nsImage: ns).resizable().scaledToFit().frame(height: 48)
//					}
//				}
//			}
//		}
//}

private struct FrameMappingEditor: View {
	let frameCount: Int
	let mapping: VisualMapping
	@Binding var control: Control
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Frame Mapping")
				.font(.caption)
				.foregroundStyle(.secondary)
			
			ForEach(0..<frameCount, id: \.self) { frameIndex in
				FrameMappingRow(frameIndex: frameIndex,
								control: $control,
								mapping: mapping
				)
			}
		}
	}
}

private struct FrameMappingRow: View {
	let frameIndex: Int
	@Binding var control: Control
	var mapping: VisualMapping
	
	private var binding: Binding<Int> {
		Binding<Int>(
			get: { control.frameMapping?[frameIndex] ?? frameIndex },
			set: { newVal in
				if control.frameMapping == nil { control.frameMapping = [:] }
				control.frameMapping?[frameIndex] = newVal
			}
		)
	}
	
	var body: some View {
		HStack {
			Text("Frame \(frameIndex)")
				.frame(width: 80, alignment: .leading)
			
			let valueCount = control.options?.count ?? (mapping.spriteFrames?.count ?? 0)
			Picker("Value", selection: binding) {
				ForEach(0..<valueCount, id: \.self) { val in
					Text("Value \(val)").tag(val)
				}
			}
			.frame(maxWidth: 150)
		}
	}
}




// MARK: - Small reusable controls
private struct LibraryBrowserSheet: View {
	@Environment(\.dismiss) private var dismiss
	
	var onPick: (UUID) -> Void
	@State private var search = ""
	let lib = SpriteLibrary.shared
	private let cols = [GridItem(.adaptive(minimum: 120), spacing: 12)]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Sprite Library").font(.headline)
				Spacer()
				Button("Cancel") { dismiss() }
					.keyboardShortcut(.cancelAction)
				TextField("Search", text: $search).textFieldStyle(.roundedBorder)
					.frame(width: 220)
			}
			ScrollView {
				LazyVGrid(columns: cols, spacing: 12) {
					ForEach(filtered(), id: \.id) { asset in
						Button {
							onPick(asset.id)
						} label: {
							VStack(spacing: 6) {
								ZStack {
									Rectangle().fill(Color(nsColor: .windowBackgroundColor))
										.cornerRadius(8)
									if let thumb = firstFrame(of: asset) {
										Image(nsImage: thumb).resizable().scaledToFit().padding(10)
									}
								}
								.frame(height: 120)
								Text(asset.name).lineLimit(1)
									.font(.caption)
							}
						}
						.buttonStyle(.plain)
						.contextMenu {
							if asset.isBuiltin { Text("Built-in") }
							if !asset.tags.isEmpty { Text(asset.tags.joined(separator: ", ")) }
						}
					}
				}
				.padding(.top, 4)
			}
		}
		.padding(16)
	}
	
	private func filtered() -> [SpriteAsset] {
		let assets = lib.allAssets()
		guard !search.isEmpty else { return assets }
		return assets.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.tags.joined().localizedCaseInsensitiveContains(search) }
	}
	
	private func firstFrame(of a: SpriteAsset) -> NSImage? {
		if let cg = lib.cgImage(forFrame: 0, in: a.id) {
			return NSImage(cgImage: cg, size: .zero)
		}
		return nil
	}
}


private struct VSliderRow: View {
	let title: String
	@Binding var value: Double
	let range: ClosedRange<Double>
	let step: Double
	
	var body: some View {
		HStack {
			Text(title).frame(width: 80, alignment: .leading)
			Slider(value: $value, in: range, step: step)
			Text(String(format: "%.2f", value))
				.monospacedDigit()
				.frame(width: 48, alignment: .trailing)
		}
	}
}

private struct NumberField: View {
	@Binding var value: Double
	var body: some View {
		HStack(spacing: 4) {
			TextField("", value: $value, format: .number.precision(.fractionLength(0...3)))
				.textFieldStyle(.roundedBorder)
				.frame(width: 80)
		}
	}
}

private struct CompactColorEditor: View {
	@Binding var color: CodableColor       // uses your RGBA store directly
	@State private var h: Double = 0       // 0...1
	@State private var s: Double = 0       // 0...1
	@State private var v: Double = 1       // 0...1
	
	var body: some View {
		HStack(spacing: 8) {
			// S/V square
			GeometryReader { geo in
				let w = geo.size.width, hgt = geo.size.height
				ZStack {
					// Base = value (vertical), overlay hue-tinted gradient for saturation (horizontal)
					LinearGradient(stops: [
						.init(color: .white, location: 0),
						.init(color: Color(hue: h, saturation: 1, brightness: 1), location: 1),
					], startPoint: .leading, endPoint: .trailing)
					.mask(
						LinearGradient(colors: [.white, .black], startPoint: .top, endPoint: .bottom)
					)
					
					// Crosshair
					Circle()
						.strokeBorder(.black, lineWidth: 1)
						.background(Circle().fill(.white))
						.frame(width: 10, height: 10)
						.position(x: CGFloat(s) * w,
								  y: CGFloat(1 - v) * hgt)
						.allowsHitTesting(false)
				}
				.contentShape(Rectangle())
				.gesture(
					DragGesture(minimumDistance: 0).onChanged { g in
						let p = CGPoint(x: max(0,min(w, g.location.x)), y: max(0,min(hgt, g.location.y)))
						s = w == 0 ? 0 : Double(p.x / w)
						v = hgt == 0 ? 1 : 1 - Double(p.y / hgt)
						pushToBinding()
					}
				)
			}
			.aspectRatio(1, contentMode: .fit)
			.frame(minWidth: 100, minHeight: 100)
			
			// Hue slider
			GeometryReader { geo in
				let H = geo.size.height
				ZStack {
					LinearGradient(
						gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map {
							Color(hue: $0, saturation: 1, brightness: 1)
						}),
						startPoint: .top, endPoint: .bottom
					)
					Rectangle()
						.strokeBorder(.white, lineWidth: 2).opacity(0.8)
						.frame(height: 2)
						.position(x: geo.size.width/2,
								  y: CGFloat(h) * H)
						.allowsHitTesting(false)
				}
				.contentShape(Rectangle())
				.gesture(
					DragGesture(minimumDistance: 0).onChanged { g in
						let y = max(0, min(H, g.location.y))
						h = H == 0 ? 0 : Double(y / H)
						pushToBinding()
					}
				)
			}
			.frame(width: 18)
		}
		.frame(height: 120)
		.onAppear { pullFromBinding() }
		.onChange(of: color) { _, _ in pullFromBinding() }  // external changes sync in
	}
	
	private func pushToBinding() {
		let (r,g,b) = hsv2rgb(h, s, v)
		color.r = r; color.g = g; color.b = b; color.a = 1
	}
	private func pullFromBinding() {
		let (hh, ss, vv) = rgb2hsv(color.r, color.g, color.b)
		h = hh; s = ss; v = vv
	}
	
	// MARK: - HSV <-> RGB
	private func hsv2rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
		if s <= 1e-9 { return (v, v, v) }
		let i = floor(h * 6)
		let f = h * 6 - i
		let p = v * (1 - s)
		let q = v * (1 - s * f)
		let t = v * (1 - s * (1 - f))
		switch Int(i) % 6 {
			case 0: return (v, t, p)
			case 1: return (q, v, p)
			case 2: return (p, v, t)
			case 3: return (p, q, v)
			case 4: return (t, p, v)
			default: return (v, p, q)
		}
	}
	private func rgb2hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
		let mx = max(r, max(g, b)), mn = min(r, min(g, b))
		let d = mx - mn
		var h = 0.0
		if d > 1e-9 {
			if mx == r { h = ( (g - b) / d ).truncatingRemainder(dividingBy: 6) }
			else if mx == g { h = ( (b - r) / d ) + 2 }
			else { h = ( (r - g) / d ) + 4 }
			h /= 6
			if h < 0 { h += 1 }
		}
		let s = mx <= 1e-9 ? 0 : d / mx
		let v = mx
		return (h, s, v)
	}
}

private struct Checkerboard: View {
	var body: some View {
		GeometryReader { geo in
			let s: CGFloat = 6
			let cols = Int(ceil(geo.size.width / s))
			let rows = Int(ceil(geo.size.height / s))
			Path { p in
				for r in 0..<rows {
					for c in 0..<cols where (r + c) % 2 == 0 {
						p.addRect(CGRect(x: CGFloat(c)*s, y: CGFloat(r)*s, width: s, height: s))
					}
				}
			}
			.fill(Color.black.opacity(0.15))
		}
		.frame(height: 16)
		.clipped()
	}
}

private struct ColorSwatch: View {
	var color: Color
	var body: some View {
		ZStack {
			Checkerboard().cornerRadius(6)
			RoundedRectangle(cornerRadius: 6, style: .continuous)
				.fill(color)
				.overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
		}
		.frame(width: 40, height: 40)
	}
}

// Lets the user choose Finite/−∞/+∞; shows a number field when "Finite" is selected.
private struct BoundField: View {
	@Binding var bound: Bound?
	var title: String
	var defaultFinite: Double
	
	private var currentFinite: Double {
		bound?.resolve(default: defaultFinite) ?? defaultFinite
	}
	
	private var isInfinite: Bool {
		switch bound ?? .finite(defaultFinite) {
			case .negInfinity, .posInfinity: return true
			case .finite: return false
		}
	}
	
	var body: some View {
		HStack(spacing: 6) {
			Menu(title) {
				Button("Finite") { bound = .finite(currentFinite) }
				Button("−∞")     { bound = .negInfinity }
				Button("+∞")     { bound = .posInfinity }
			}
			.menuStyle(.borderlessButton)
			
			NumberField(
				value: Binding(
					get: { currentFinite },
					set: { bound = .finite($0) }
				)
			)
			.disabled(isInfinite)
			.opacity(isInfinite ? 0.5 : 1)
		}
	}
}

private func isInfinite(_ b: Bound?) -> Bool {
	switch b {
		case .negInfinity?: return true
		case .posInfinity?: return true
		default:            return false
	}
}
