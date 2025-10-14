//
//  LabelView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//

import SwiftUI
import AppKit

struct LabelView: View {
	@EnvironmentObject private var sessionManager: SessionManager
	
    @Binding var label: SessionLabel
    @Environment(\.canvasZoom) private var zoom     // you already have this in RackChassisView
    let onBeginDrag: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnd: () -> Void
    let onEdit: () -> Void
	let onDelete: () -> Void

	@State private var isEditingText = false
	@State private var draftText: String = ""
	@FocusState private var textFieldFocused: Bool
	
	private var hitPad: CGFloat {
		max(6, 12 / max(zoom, 0.001))
	}
	
	var body: some View {
		let s = label.style

		let font: Font = {
			if s.fontName.hasPrefix(".") {
				return .system(size: s.fontSize, weight: .medium, design: .rounded)
			}
			return .custom(s.fontName, size: s.fontSize)
		}()
		
		Group {
			if isEditingText {
				// Scale max width with font size, but keep it reasonable
				let maxWidth = max(120, min(s.fontSize * 15, 300))

				TextField("Label", text: $draftText, onCommit: commitEdit)
					.textFieldStyle(.plain)
					.foregroundStyle(.primary)
					.font(font)
					.focused($textFieldFocused)
					.onAppear {
						draftText = label.text
						textFieldFocused = true
					}
					.onExitCommand { cancelEdit() }
					.disableAutocorrection(true)
					.lineLimit(1)
					.truncationMode(.tail)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: maxWidth)
					.padding(.horizontal, s.paddingH)
					.padding(.vertical, s.paddingV)
					.background(
						RoundedRectangle(cornerRadius: s.cornerRadius)
							.fill(Color(nsColor: .textBackgroundColor))
							.overlay(
								RoundedRectangle(cornerRadius: s.cornerRadius)
									.stroke(Color.accentColor, lineWidth: 2)
							)
					)
					.clipShape(RoundedRectangle(cornerRadius: s.cornerRadius))
			} else {
				// Background with per-style opacity — text stays fully vector & crisp
				let background = RoundedRectangle(cornerRadius: s.cornerRadius)
					.fill(s.background.color.opacity(s.opacity))
					.overlay(
						RoundedRectangle(cornerRadius: s.cornerRadius)
							.stroke(s.borderColor.color, lineWidth: max(0, s.borderWidth))
					)
				
				Text(label.text)
					.font(font)
					.foregroundStyle(s.textColor.color)
					.padding(.horizontal, s.paddingH)
					.padding(.vertical,   s.paddingV)
					.background(background)
					.shadow(radius: (zoom <= 1.0 ? s.shadow : 0))
					.shadow(color: label.isNewlyCreated ? Color.accentColor.opacity(0.6) : .clear, radius: 12, x: 0, y: 0)
					.shadow(color: label.isNewlyCreated ? Color.accentColor.opacity(0.4) : .clear, radius: 24, x: 0, y: 0)
			}
		}
		.contentShape(Rectangle().inset(by: -hitPad))
		.background(Color.black.opacity(0.001))
		.onAppear {
			// Clear the newly-created flag after a delay so the glow fades
			if label.isNewlyCreated {
				DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
					label.isNewlyCreated = false
				}
			}
		}
		
		// DOUBLE-CLICK → inline edit (not the inspector)
		.highPriorityGesture(
			TapGesture(count: 2).onEnded {
				guard !label.isLocked else { return }
				startEdit()
			}
		)
		
		// DRAG (disabled while editing)
		.simultaneousGesture(label.isLocked || isEditingText ? nil : dragGesture)
		
		// CONTEXT MENU with human preset names
		.contextMenu {
			ForEach(LabelPreset.allCases) { p in
				Button("\(p.icon)  \(p.displayName)") { commitStyle(style: .preset(p), presetId: nil) }
			}
			Divider()
			let customs = LabelPresetStore.load()
			if !customs.isEmpty {
				Text("User Presets")
				ForEach(customs) { c in
					Button(c.name) { commitStyle(style: c.style, presetId: c.id) }
				}
			}
			Divider()
			Button(label.isLocked ? "Unlock" : "Lock") { label.isLocked.toggle() }
			Button("Edit…") { onEdit() }   // optional: still allow inspector
			Divider()
			Button(role: .destructive) { onDelete() } label: {
				Label("Delete Label", systemImage: "trash")
			}
		}
		.zIndex(100_000)
	}
	
	// MARK: - Inline edit helpers
	private func startEdit() {
		draftText = label.text
		isEditingText = true
	}
	private func commitEdit() {
		label.text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
		isEditingText = false
		sessionManager.saveSessions()
	}
	private func cancelEdit() {
		isEditingText = false
	}
	private func commitStyle(style: LabelStyleSpec, presetId: UUID?) {
		label.style = style
		label.linkedPresetId = presetId
		sessionManager.saveSessions()
	}
	
	
	private var dragGesture: some Gesture {
		// Give double-tap a chance to fire; 3-4 px should be ok on macOS.
		DragGesture(minimumDistance: 3)
			.onChanged { v in
				onBeginDrag()
				let d = v.translation
				let constrained = NSEvent.modifierFlags.contains(.shift)
				? (abs(d.width) > abs(d.height) ? CGSize(width: d.width, height: 0)
				   : CGSize(width: 0, height: d.height))
				: d
				onChanged(constrained)
			}
			.onEnded { _ in onEnd() }
	}
}
