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
	@EnvironmentObject var sessionManager: SessionManager
	
	@Binding var label: SessionLabel
	@Environment(\.dismiss) private var dismiss
	@Environment(\.canvasZoom) private var canvasZoom
	
	@State private var showSavePresetSheet = false
	@State private var newPresetName: String = ""
	@State private var families: [String] = NSFontManager.shared.availableFontFamilies.sorted()
	@FocusState private var textFocused: Bool
	
	// Work on a draft; commit on Done
	@State private var draft: SessionLabel = .init()
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			
			// Header
			Text("Label").font(.title2).bold()
			
			// Preview
			VStack(alignment: .leading, spacing: 6) {
				Text("Preview").font(.caption).foregroundStyle(.secondary)
				LabelStylePreview(
					text: draft.text,
					style: draft.style,
					scale: CGFloat(canvasZoom)
				)
				.accessibilityLabel("Label preview at \(Int((canvasZoom) * 100))%")
			}
			
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
						// Built-ins
						ForEach(LabelPreset.allCases) { p in
							Button {
								draft.style = .preset(p)
							} label: {
								PresetChip(title: p.displayName, style: .preset(p))
							}
							.buttonStyle(.bordered)
							.controlSize(.large)
						}
						
						// User presets
						let customs = LabelPresetStore.load()
						if !customs.isEmpty {
							Divider().frame(height: 22)
							ForEach(customs) { c in
								Button {
									draft.style = c.style
								} label: {
									PresetChip(title: c.name, style: c.style)
								}
								.buttonStyle(.borderedProminent)
								.controlSize(.large)
								.contextMenu {
									Button("Delete", role: .destructive) {
										LabelPresetStore.delete(id: c.id)
									}
								}
							}
						}
					}
					.frame(height: 44)
				}
				
				HStack(spacing: 8) {
					Button("Save Preset…") {
						// Pre-fill with label text if available, fallback to readable style name.
						newPresetName = draft.text.isEmpty ? "Preset \(Date().formatted(date: .numeric, time: .omitted))" : draft.text
						showSavePresetSheet = true
					}
					.buttonStyle(.bordered)
					
					Button("Use as Default") {
						LabelStyleDefaults.save(draft.style)
					}
					Button("Reset to App Default") {
						draft.style = LabelStyleDefaults.load()
					}
					.help("Reload the saved default; use Reset in app preferences to reset to system defaults")
					Spacer()
				}
			}
			.sheet(isPresented: $showSavePresetSheet) {
				VStack(alignment: .leading, spacing: 12) {
					Text("Save Label Preset").font(.title2).bold()
					TextField("Preset name", text: $newPresetName)
						.textFieldStyle(.roundedBorder)
						.frame(width: 300)
					HStack {
						Spacer()
						Button("Cancel") { showSavePresetSheet = false }
						Button("Save") {
							LabelPresetStore.add(name: newPresetName, style: draft.style)
							showSavePresetSheet = false
						}
						.keyboardShortcut(.defaultAction)
					}
				}
				.padding(20)
				.frame(minWidth: 360)
			}
			
			Spacer(minLength: 8)
			
			// Bottom actions: Cancel / Done
			HStack {
				Spacer()
				Button("Cancel") { dismiss() }
				Button("Done") {
					label = draft
					sessionManager.saveSessions()
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(16)
		.frame(minWidth: 440)
	}
}

private struct PresetChip: View {
	var title: String
	var style: LabelStyleSpec
	var body: some View {
		HStack(spacing: 6) {
			Text(title)
			RoundedRectangle(cornerRadius: 4)
				.fill(style.background.color)
				.overlay(RoundedRectangle(cornerRadius: 4).stroke(style.borderColor.color, lineWidth: max(1, style.borderWidth)))
				.overlay(Text("Aa").font(.system(size: 10)).foregroundStyle(style.textColor.color))
				.frame(width: 28, height: 16)
		}
	}
}

private struct LabelStylePreview: View {
	var text: String
	var style: LabelStyleSpec
	var scale: CGFloat = 1
	
	var body: some View {
		ZStack {
			Checkerboard(cell: 8)
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.stroke(Color.black.opacity(0.06), lineWidth: 1)
				)
			
			Text(text.isEmpty ? "Label" : text)
				.font(.custom(style.fontName, size: style.fontSize * scale))
				.foregroundStyle(style.textColor.color)
				.padding(.horizontal, style.paddingH * scale)
				.padding(.vertical, style.paddingV * scale)
				.background(style.background.color)
				.overlay(
					RoundedRectangle(cornerRadius: style.cornerRadius * scale)
						.stroke(style.borderColor.color, lineWidth: max(0, style.borderWidth) * scale)
				)
				.cornerRadius(style.cornerRadius * scale)
				.opacity(style.opacity)
				.shadow(radius: style.shadow * scale)
		}
		.frame(maxWidth: .infinity, minHeight: 90, maxHeight: 130)
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}
}

private struct Checkerboard: View {
	var cell: CGFloat = 8
	var light = Color(.sRGB, white: 0.92, opacity: 1)
	var dark  = Color(.sRGB, white: 0.82, opacity: 1)
	
	var body: some View {
		Canvas { context, size in
			let cols = Int(ceil(size.width  / cell))
			let rows = Int(ceil(size.height / cell))
			for r in 0..<rows {
				for c in 0..<cols {
					let isDark = (r + c) % 2 == 1
					let rect = CGRect(x: CGFloat(c) * cell,
									  y: CGFloat(r) * cell,
									  width: cell, height: cell)
					context.fill(Path(rect), with: .color(isDark ? dark : light))
				}
			}
		}
		.allowsHitTesting(false)
	}
}
