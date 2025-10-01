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
	
	var body: some View {
		let s = label.style
		let z = max(CGFloat(zoom), 0.0001)

		let font: Font = {
			if s.fontName.hasPrefix(".") {
				return .system(size: s.fontSize, weight: .medium, design: .rounded)
			}
			return .custom(s.fontName, size: s.fontSize)
		}()
		
		Group {
			if isEditingText {
				// Cap editor to ~220 px *on screen*, converted to local coords.
				// Clamp to a safe finite range so minWidth ≤ maxWidth.
				let cap = max(80, min(220 / z, 1200))        // 80…1200 local points
				let minW = min(120, cap)                     // never larger than cap

				TextField("Label", text: $draftText, onCommit: commitEdit)
					.textFieldStyle(.roundedBorder)
					.foregroundStyle(.primary)
					.font(font)
					.focused($textFieldFocused)
					.onAppear {
						draftText = label.text
						textFieldFocused = true
					}
					.onExitCommand { cancelEdit() }     // ESC to cancel
					.disableAutocorrection(true)
					.lineLimit(1)
					.truncationMode(.tail)              // show ellipsis rather than expanding
					.fixedSize(horizontal: false, vertical: true)
					.frame(minWidth: minW, maxWidth: cap)
					.padding(.horizontal, 8)
					.padding(.vertical, 6)
					.background(
						RoundedRectangle(cornerRadius: 8)
							.fill(Color(nsColor: .textBackgroundColor))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
							)
					)
					.clipShape(RoundedRectangle(cornerRadius: 8))
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
			}
		}
		.contentShape(Rectangle())
		
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
				Button("\(p.icon)  \(p.displayName)") { commitStyle(style: .preset(p)) }//label.style = .preset(p) }
			}
			Divider()
			let customs = LabelPresetStore.load()
			if !customs.isEmpty {
				Text("User Presets")
				ForEach(customs) { c in
					Button(c.name) { commitStyle(style: c.style) } //label.style = c.style }
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
	private func commitStyle(style: LabelStyleSpec) {
		label.style = style
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
