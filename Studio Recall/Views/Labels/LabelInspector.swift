//
//  LabelInspector.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//
// LabelInspector.swift
import SwiftUI
import AppKit

struct LabelInspector: View {
	@Binding var label: SessionLabel
	@Environment(\.dismiss) private var dismiss
	@State private var families: [String] = NSFontManager.shared.availableFontFamilies.sorted()
	@FocusState private var textFocused: Bool
	
	// Work on a draft; commit on Done
	@State private var draft: SessionLabel = .init()
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			
			// Header
			Text("Label").font(.title2).bold()
			
			// Text
			VStack(alignment: .leading, spacing: 6) {
				Text("Text").font(.caption).foregroundStyle(.secondary)
				TextField("Label text", text: $draft.text)
					.textFieldStyle(.roundedBorder)
					.focused($textFocused)
					.onAppear {
						draft = label
						textFocused = true
					}
					.frame(minWidth: 320)
			}
			
			// Font family + size
			VStack(alignment: .leading, spacing: 6) {
				Text("Font").font(.caption).foregroundStyle(.secondary)
				HStack(alignment: .firstTextBaseline, spacing: 8) {
					Picker("", selection: $draft.style.fontName) {
						if !families.contains(draft.style.fontName) {
							Text(draft.style.fontName).tag(draft.style.fontName)
							Divider()
						}
						ForEach(families, id: \.self) { fam in
							Text(fam).tag(fam)
						}
					}
					.labelsHidden()
					.frame(width: 240)
					
					Stepper(value: $draft.style.fontSize, in: 8...64, step: 1) {
						Text("\(Int(draft.style.fontSize)) pt").monospacedDigit()
					}
					.frame(minWidth: 120, alignment: .leading)
				}
			}
			
			// Colors
			VStack(alignment: .leading, spacing: 8) {
				Text("Colors").font(.caption).foregroundStyle(.secondary)
				HStack {
					ColorPicker("Text", selection: Binding(
						get:{ draft.style.textColor.color },
						set:{ draft.style.textColor = .init($0) }))
					ColorPicker("Background", selection: Binding(
						get:{ draft.style.background.color },
						set:{ draft.style.background = .init($0) }))
					ColorPicker("Border", selection: Binding(
						get:{ draft.style.borderColor.color },
						set:{ draft.style.borderColor = .init($0) }))
				}
			}
			
			// Shape / Border / Padding
			VStack(alignment: .leading, spacing: 6) {
				Text("Shape & Layout").font(.caption).foregroundStyle(.secondary)
				HStack {
					HStack(spacing: 6) {
						Text("Corner").frame(width: 56, alignment: .leading)
						Slider(value: $draft.style.cornerRadius, in: 0...12)
						Text("\(Int(draft.style.cornerRadius))").monospacedDigit()
							.frame(width: 32, alignment: .trailing)
					}
					HStack(spacing: 6) {
						Text("Border").frame(width: 48, alignment: .leading)
						Slider(value: $draft.style.borderWidth, in: 0...4)
						Text(String(format: "%.1f", draft.style.borderWidth)).monospacedDigit()
							.frame(width: 32, alignment: .trailing)
					}
				}
				HStack {
					HStack(spacing: 6) {
						Text("Padding H").frame(width: 72, alignment: .leading)
						Slider(value: $draft.style.paddingH, in: 0...24)
						Text("\(Int(draft.style.paddingH))").monospacedDigit()
							.frame(width: 32, alignment: .trailing)
					}
					HStack(spacing: 6) {
						Text("Padding V").frame(width: 72, alignment: .leading)
						Slider(value: $draft.style.paddingV, in: 0...16)
						Text("\(Int(draft.style.paddingV))").monospacedDigit()
							.frame(width: 32, alignment: .trailing)
					}
				}
			}
			
			// Effects & Behavior — grid layout for better line rhythm
			VStack(alignment: .leading, spacing: 6) {
				Text("Effects & Behavior").font(.caption).foregroundStyle(.secondary)
				
				Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
					GridRow {
						Toggle("Scales with zoom", isOn: $draft.style.scalesWithZoom)
						Toggle("Locked", isOn: $draft.isLocked)
					}
					GridRow {
						HStack {
							Text("Opacity")
							Slider(value: $draft.style.opacity, in: 0.2...1)
							Text(String(format: "%.0f%%", draft.style.opacity * 100))
								.monospacedDigit().frame(width: 44, alignment: .trailing)
						}
						HStack {
							Text("Shadow")
							Slider(value: $draft.style.shadow, in: 0...6)
							Text(String(format: "%.1f", draft.style.shadow))
								.monospacedDigit().frame(width: 40, alignment: .trailing)
						}
					}
				}
			}
			
			// Presets row (taller so buttons don’t clip)
			VStack(alignment: .leading, spacing: 6) {
				Text("Presets").font(.caption).foregroundStyle(.secondary)
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(LabelPreset.allCases) { p in
							Button("\(p.icon)  \(p.displayName)") {
								draft.style = .preset(p)
							}
							.buttonStyle(.bordered)
							.controlSize(.large)
						}
					}
					.frame(height: 44)
				}
			}
			
			Spacer(minLength: 8)
			
			// Bottom actions: Cancel / Done
			HStack {
				Spacer()
				Button("Cancel") { dismiss() }
				Button("Done") {
					label = draft
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(16)
		.frame(minWidth: 440)
	}
}
