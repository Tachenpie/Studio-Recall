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
									// Two concentric square regions, forced to circle shape
									let outer = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.6),
													 y: max(0, binding.wrappedValue.y - s*0.6),
													 width: s*1.2, height: s*1.2),
										mapping: nil,
										shape: .circle
									)
									let inner = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.35),
													 y: max(0, binding.wrappedValue.y - s*0.35),
													 width: s*0.7, height: s*0.7),
										mapping: nil,
										shape: .circle
									)
									binding.regions.wrappedValue = [outer, inner]
								} else {
									let r = ImageRegion(
										rect: CGRect(x: max(0, binding.wrappedValue.x - s*0.5),
													 y: max(0, binding.wrappedValue.y - s*0.5),
													 width: s, height: s),
										mapping: nil,
										shape: .rect
									)
									binding.regions.wrappedValue = [r]
								}
								isEditingRegion = true
							}
						} else {
							ForEach(binding.regions.wrappedValue.indices, id: \.self) { idx in
								let regionBinding = Binding<ImageRegion>(
									get: { binding.regions.wrappedValue[idx] },
									set: { binding.regions.wrappedValue[idx] = $0 }
								)
								
								VStack(alignment: .leading, spacing: 6) {
									HStack {
										Toggle("Edit \(binding.wrappedValue.type == .concentricKnob ? (idx == 0 ? "Outer" : "Inner") : "Region \(idx+1)")",
											   isOn: $isEditingRegion)
										Spacer()
										Button("Delete") {
											binding.regions.wrappedValue.remove(at: idx)
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
								.padding(.vertical, 4)
							}
						}
					}
				}

				
				// MARK: Per-type configuration
				perTypeSection(binding: binding)
					.transition(.opacity.combined(with: .move(edge: .top)))
				
				// MARK: Mapping
				GroupBox("Image Mapping") {
					MappingEditor(control: binding)
				}
				
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

	// MARK: - Per-type section
	@ViewBuilder
	private func perTypeSection(binding: Binding<Control>) -> some View {
		switch binding.wrappedValue.type {
			case .knob:
				GroupBox("Knob") {
					VStack(alignment: .leading, spacing: 8) {
						// Min / Max
						HStack {
							Text("Range").frame(minWidth: 60, alignment: .leading)
							NumberField(value: Binding(
								get: { binding.knobMin.wrappedValue?.resolve(default: 0) ?? 0 },
								set: { binding.knobMin.wrappedValue = .finite($0) }
							))
							Text("…")
							NumberField(value: Binding(
								get: { binding.knobMax.wrappedValue?.resolve(default: 1) ?? 1 },
								set: { binding.knobMax.wrappedValue = .finite($0) }
							))
						}
						
						// Value editor (slider if finite)
						let lo = binding.knobMin.wrappedValue?.resolve(default: 0) ?? 0
						let hi = binding.knobMax.wrappedValue?.resolve(default: 1) ?? 1
						if hi > lo {
							VSliderRow(
								title: "Value",
								value: Binding(
									get: { binding.value.wrappedValue ?? lo },
									set: { binding.value.wrappedValue = min(max($0, lo), hi) }
								),
								range: lo...hi,
								step: (hi - lo) / 100
							)
						} else {
							HStack {
								Text("Value").frame(minWidth: 60, alignment: .leading)
								NumberField(value: Binding(
									get: { binding.value.wrappedValue ?? 0 },
									set: { binding.value.wrappedValue = $0 }
								))
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
							set: { binding.options.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
						))
						.textFieldStyle(.roundedBorder)
						
						HStack {
							Text("Index").frame(minWidth: 60, alignment: .leading)
							Stepper(value: Binding(
								get: { binding.stepIndex.wrappedValue ?? 0 },
								set: { binding.stepIndex.wrappedValue = $0 }
							), in: 0...(binding.options.wrappedValue?.count ?? 1)-1) {
								Text("\(binding.stepIndex.wrappedValue ?? 0)")
							}
						}
					}
				}
				
			case .multiSwitch:
				GroupBox("Multi-Switch") {
					VStack(alignment: .leading, spacing: 8) {
						Text("Labels").font(.caption)
						TextField("e.g. Slow, Fast", text: Binding(
							get: { (binding.options.wrappedValue ?? []).joined(separator: ", ") },
							set: { binding.options.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
						))
						.textFieldStyle(.roundedBorder)
						
						HStack {
							Text("Selected").frame(minWidth: 60, alignment: .leading)
							Stepper(value: Binding(
								get: { binding.selectedIndex.wrappedValue ?? 0 },
								set: { binding.selectedIndex.wrappedValue = $0 }
							), in: 0...(binding.options.wrappedValue?.count ?? 1)-1) {
								Text("\(binding.selectedIndex.wrappedValue ?? 0)")
							}
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
							Text("On Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.onColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.onColor.wrappedValue = $0 }
							))
						}
						HStack {
							Text("Off Color").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.offColor.wrappedValue ?? CodableColor(.gray) },
								set: { binding.offColor.wrappedValue = $0 }
							))
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
							NumberField(value: Binding(
								get: { binding.outerMin.wrappedValue?.resolve(default: 0) ?? 0 },
								set: { binding.outerMin.wrappedValue = .finite($0) }
							))
							Text("…")
							NumberField(value: Binding(
								get: { binding.outerMax.wrappedValue?.resolve(default: 1) ?? 1 },
								set: { binding.outerMax.wrappedValue = .finite($0) }
							))
						}
						
						HStack {
							Text("Inner Range").frame(minWidth: 60, alignment: .leading)
							NumberField(value: Binding(
								get: { binding.innerMin.wrappedValue?.resolve(default: 0) ?? 0 },
								set: { binding.innerMin.wrappedValue = .finite($0) }
							))
							Text("…")
							NumberField(value: Binding(
								get: { binding.innerMax.wrappedValue?.resolve(default: 1) ?? 1 },
								set: { binding.innerMax.wrappedValue = .finite($0) }
							))
						}
						
						VSliderRow(
							title: "Outer",
							value: Binding(
								get: { binding.outerValue.wrappedValue ?? 0 },
								set: { binding.outerValue.wrappedValue = $0 }
							),
							range: (binding.outerMin.wrappedValue?.resolve(default: 0) ?? 0)
							... (binding.outerMax.wrappedValue?.resolve(default: 1) ?? 1),
							step: 0.01
						)
						
						VSliderRow(
							title: "Inner",
							value: Binding(
								get: { binding.innerValue.wrappedValue ?? 0 },
								set: { binding.innerValue.wrappedValue = $0 }
							),
							range: (binding.innerMin.wrappedValue?.resolve(default: 0) ?? 0)
							... (binding.innerMax.wrappedValue?.resolve(default: 1) ?? 1),
							step: 0.01
						)
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
							Text("Lamp On").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.lampOnColor.wrappedValue ?? CodableColor(.green) },
								set: { binding.lampOnColor.wrappedValue = $0 }
							))
						}
						HStack {
							Text("Lamp Off").frame(minWidth: 60, alignment: .leading)
							CompactColorEditor(color: Binding(
								get: { binding.lampOffColor.wrappedValue ?? CodableColor(.gray) },
								set: { binding.lampOffColor.wrappedValue = $0 }
							))
						}
					}
				}
		}
	}
}

// MARK: - Mapping editor

private struct MappingEditor: View {
	@Binding var control: Control
	
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
	
	// Two-way binding to the persisted mapping kind
	private var kindBinding: Binding<Kind> {
		Binding(
			get: {
				guard let m = control.region?.mapping else { return .none }
				switch m.kind {
					case .rotate:     return .rotate
					case .brightness: return .brightness
					case .opacity:    return .opacity
					case .translate:  return .translate
					case .flip3D:     return .flip3D
					case .sprite:	  return .sprite
				}
			},
			set: { new in
				ensureRegion()
				let current = control.region?.mapping?.kind
				// Only create a default mapping if the kind actually changed
				switch new {
					case .none:
						control.region?.mapping = nil
					case .rotate:
						if current != .rotate {
							control.region?.mapping = .rotate(
								min: -135, max: 135, pivot: CGPoint(x: 0.5, y: 0.5),
								taper: (control.knobMin == .negInfinity ? .decibel : .linear)
							)
						}
					case .brightness:
						if current != .brightness {
							control.region?.mapping = .brightness(RangeD(lower: 0.0, upper: 0.7))
						}
					case .opacity:
						if current != .opacity {
							control.region?.mapping = .opacity(RangeD(lower: 0.25, upper: 1.0))
						}
					case .translate:
						ensureRegion()
						// sensible default: small horizontal travel
						control.region?.mapping = .translate(from: CGPoint(x: -0.15, y: 0),
															 to:   CGPoint(x:  0.15, y: 0))
					case .flip3D:
						ensureRegion()
						control.region?.mapping = .flip3D()  // defaults: axis .x, pivot at bottom-center
					case .sprite:
						ensureRegion()
						if current != .sprite {
							// Sensible defaults:
							// - 2×1 grid (typical 2-position switch)
							// - region pivot near the hinge
							// - sprite pivot near the bottom of the lever
							var m = VisualMapping.sprite(
								atlasPNG: nil,                 // user will choose an image in the editor
								cols: (control.type == .multiSwitch || control.type == .button) ? 2 : 1,
								rows: 1,
								pivot: CGPoint(x: 0.5, y: 0.88),          // region (crop) pivot
								spritePivot: CGPoint(x: 0.5, y: 0.92),    // pivot inside a sprite frame
								scale: 1.0
							)
							// Optional: if it's a multiswitch and you want an explicit map,
							// prefill indices 0..N-1 (renderer also works when this is nil).
							if let n = control.options?.count, n > 0 {
								m.spriteIndices = Array(0..<n)
							}
							control.region?.mapping = m
						}

				}
			}
		)
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text("Kind").frame(width: 80, alignment: .leading)
				Picker("", selection: kindBinding) {
					ForEach(Kind.allCases) { k in Text(k.rawValue).tag(k) }
				}
				.labelsHidden()
			}
			
			if let m = control.region?.mapping {
				switch m.kind {
					case .rotate:
						RotateEditor(mapping: Binding(
							get: { control.region!.mapping! },
							set: { control.region!.mapping = $0 }
						))
					case .brightness, .opacity:
						ScalarEditor(mapping: Binding(
							get: { control.region!.mapping! },
							set: { control.region!.mapping = $0 }
						))
					case .translate:
						TranslateEditor(mapping: Binding(
							get: { control.region!.mapping! },
							set: { control.region!.mapping = $0 }
						))
					case .flip3D:
						FlipEditor(mapping: Binding(
							get: { control.region!.mapping! },
							set: { control.region!.mapping = $0 }
						), control: $control)
					case .sprite:
						SpriteEditor(mapping: Binding(
							get: { control.region!.mapping! },
							set: { control.region!.mapping = $0 }
						), control: $control)
				}
				
				HStack {
					Button("Preset: Knob (Rotate)") {
						kindBinding.wrappedValue = .rotate
					}
					Button("Preset: Lamp (Opacity)") {
						kindBinding.wrappedValue = .opacity
					}
					Button("Preset: Flip Toggle (3D)") {
						kindBinding.wrappedValue = .flip3D
					}
				}
				.buttonStyle(.bordered)
			}
		}
		.onAppear { migrateIfNeeded() }
		.onChange(of: control.id) { _, _ in migrateIfNeeded() }
	}
	
	private func ensureRegion() {
		if control.region == nil {
			var r = CGRect(x: max(0, control.x - 0.05),
						   y: max(0, control.y - 0.05),
						   width: 0.10, height: 0.10)
			r.origin.x = min(r.origin.x, 1 - r.size.width)
			r.origin.y = min(r.origin.y, 1 - r.size.height)
			control.region = ImageRegion(rect: r, mapping: nil)
		}
	}
	
	private func migrateIfNeeded() {
		if var m = control.region?.mapping,
		   (m.spriteAtlasPNG != nil) || ((m.spriteFrames?.isEmpty == false)) {
			SpriteLibrary.shared.migrateEmbeddedSprites(in: &m, suggestedName: control.name)
			control.region?.mapping = m
		}
	}
}

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
	@Binding var mapping: VisualMapping
	@Binding var control: Control
	
	@State private var showOpen = false
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Sprites show a pose image per switch position using a grid-based atlas. Set the pivot where the hinge meets the lever, then align the sprite’s pivot so the image sits correctly.")
				.font(.caption).foregroundStyle(.secondary)
			HStack {
				Text("Source").frame(width: 80, alignment: .leading)
				// Library picker
				HStack {
					Text("Library").frame(width: 80, alignment: .leading)
					Picker("", selection: Binding(
						get: { mapping.spriteAssetId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
						set: { newId in mapping.spriteAssetId = newId }
					)) {
						Text("— none —").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
						ForEach(SpriteLibrary.shared.allAssets()) { asset in
							Text(asset.name).tag(asset.id)
						}
					}
					.labelsHidden()
				}
				Picker("", selection: Binding(
					get: { mapping.spriteMode ?? .atlasGrid },
					set: { mapping.spriteMode = $0 }
				)) {
					Text("Grid Atlas").tag(VisualMapping.SpriteMode.atlasGrid)
					Text("Individual Frames").tag(VisualMapping.SpriteMode.frames)
				}.labelsHidden()
			}
			
			if (mapping.spriteMode ?? .atlasGrid) == .atlasGrid {
				// Atlas loader (macOS)
				HStack {
					Text("Atlas").frame(width: 80, alignment: .leading)
					Button(mapping.spriteAssetId == nil ? "Choose Image…" : "Replace Image…") {
#if os(macOS)
						let p = NSOpenPanel()
						if #available(macOS 11.0, *) {
							p.allowedContentTypes = [UTType.png]
						} else {
							p.allowedFileTypes = ["png"]
						}
						p.allowsMultipleSelection = false
						if p.runModal() == .OK, let url = p.url, let d = try? Data(contentsOf: url) {
							if let asset = try? SpriteLibrary.shared.importAtlas(name: url.deletingPathExtension().lastPathComponent,
																				 data: d,
																				 cols: mapping.spriteCols ?? 2,
																				 rows: mapping.spriteRows ?? 1) {
								mapping.spriteAssetId = asset.id
								mapping.spriteAtlasPNG = nil   // clear embedded
							}
						}
#endif
					}
				}

				
				HStack {
					Text("Grid").frame(width: 80, alignment: .leading)
					Stepper("Cols: \(mapping.spriteCols ?? 1)", value: Binding(get: { mapping.spriteCols ?? 1 }, set: { mapping.spriteCols = $0 }), in: 1...16)
					Stepper("Rows: \(mapping.spriteRows ?? 1)", value: Binding(get: { mapping.spriteRows ?? 1 }, set: { mapping.spriteRows = $0 }), in: 1...16)
				}
				
				if control.type == .multiSwitch {
					HStack(alignment: .firstTextBaseline) {
						Text("Frame map").frame(width: 80, alignment: .leading)
						TextField("e.g. 0, 1, 2", text: Binding(
							get: {
								let m = mapping.spriteIndices ?? []
								return m.map(String.init).joined(separator: ", ")
							},
							set: { s in
								let arr = s.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
								mapping.spriteIndices = arr
							}
						))
						.textFieldStyle(.roundedBorder)
						.help("Optional: map each option to a frame index; otherwise Selected index is used as the frame.")
					}
				}
				
				HStack {
					Text("Scale").frame(width: 80, alignment: .leading)
					Slider(value: Binding(get: { mapping.spriteScale ?? 1.0 }, set: { mapping.spriteScale = $0 }), in: 0.2...2.0)
					Text(String(format: "%.2f", mapping.spriteScale ?? 1.0)).monospacedDigit().frame(width: 44, alignment: .trailing)
				}
				
				// Pivots: region vs sprite
				HStack {
					Text("Rotate").frame(width: 80, alignment: .leading)
					Picker("", selection: Binding(
						get: { (mapping.spriteQuarterTurns ?? 0) % 4 },
						set: { mapping.spriteQuarterTurns = $0 % 4 }
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
					NumberField(value: Binding(get: { Double(mapping.pivot?.x ?? 0.5) }, set: { x in var p = mapping.pivot ?? CGPoint(x: 0.5, y: 0.85); p.x = CGFloat(x); mapping.pivot = p }))
					Text("Y")
					NumberField(value: Binding(get: { Double(mapping.pivot?.y ?? 0.85) }, set: { y in var p = mapping.pivot ?? CGPoint(x: 0.5, y: 0.85); p.y = CGFloat(y); mapping.pivot = p }))
				}
				.help("Region Pivot: 0…1 within the cropped patch (where the real hinge sits).")
				
				HStack {
					Text("Sprite Pivot").frame(width: 100, alignment: .leading)
					NumberField(value: Binding(get: { Double(mapping.spritePivot?.x ?? 0.5) }, set: { x in var p = mapping.spritePivot ?? CGPoint(x: 0.5, y: 0.9); p.x = CGFloat(x); mapping.spritePivot = p }))
					Text("Y")
					NumberField(value: Binding(get: { Double(mapping.spritePivot?.y ?? 0.9) }, set: { y in var p = mapping.spritePivot ?? CGPoint(x: 0.5, y: 0.9); p.y = CGFloat(y); mapping.spritePivot = p }))
				}
				.help("Sprite Pivot: 0…1 within a single frame image (e.g., bottom of lever). Make these two pivots coincide.")
				
				Text("Rotation happens around the Sprite Pivot. If the lever ‘walks’ when you rotate, move the Sprite Pivot onto the hinge.")
					.font(.caption)
					.foregroundStyle(.secondary)

				// Tiny live preview (optional)
				if let data = mapping.spriteAtlasPNG,
				   let ns = NSImage(data: data) {
					HStack {
						Text("Preview").frame(width: 80, alignment: .leading)
						Image(nsImage: ns).resizable().scaledToFit().frame(height: 48)
					}
				}
			}
			else {
				// Frames mode: add + list
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
							let frames = p.urls.compactMap { try? Data(contentsOf: $0) }
							if let asset = try? SpriteLibrary.shared.importFrames(name: "Frames \(Date().timeIntervalSince1970)",
																				  frames: frames) {
								mapping.spriteAssetId = asset.id
								mapping.spriteFrames = nil
							}
						}
#endif
					}
				}

				if let frames = mapping.spriteFrames, !frames.isEmpty {
					ScrollView(.horizontal) {
						HStack(spacing: 8) {
							ForEach(Array(frames.enumerated()), id:\.0) { (i, d) in
								if let ns = NSImage(data: d) {
									VStack(spacing: 4) {
										Image(nsImage: ns).resizable().interpolation(.high).frame(width: 48, height: 48).border(.separator)
										HStack(spacing: 6) {
											Button("↑") {
												var f = mapping.spriteFrames!; guard i>0 else { return }
												f.swapAt(i, i-1); mapping.spriteFrames = f
											}.buttonStyle(.plain)
											Button("↓") {
												var f = mapping.spriteFrames!; guard i < f.count-1 else { return }
												f.swapAt(i, i+1); mapping.spriteFrames = f
											}.buttonStyle(.plain)
											Button("–") {
												var f = mapping.spriteFrames!; f.remove(at: i); mapping.spriteFrames = f
											}.buttonStyle(.plain)
										}
									}
								}
							}
						}.frame(height: 70)
					}
				}
			}
		}
	}
}


// MARK: - Small reusable controls

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
								  y: CGFloat(1 - h) * H)
						.allowsHitTesting(false)
				}
				.contentShape(Rectangle())
				.gesture(
					DragGesture(minimumDistance: 0).onChanged { g in
						let y = max(0, min(H, g.location.y))
						h = H == 0 ? 0 : 1 - Double(y / H)
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
