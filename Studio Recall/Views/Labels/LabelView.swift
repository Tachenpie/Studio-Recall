//
//  LabelView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

struct LabelView: View {
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
		let font: Font = {
			if s.fontName.hasPrefix(".") { return .system(size: s.fontSize, weight: .medium, design: .rounded) }
			return .custom(s.fontName, size: s.fontSize)
		}()
		let scale: CGFloat = (s.scalesWithZoom ? 1 : (1 / max(zoom, 0.0001)))
		
		Group {
			if isEditingText {
				// inside `if isEditingText { ... }`
				let screenCap: CGFloat = 260            // desired max on-screen width
				let scale: CGFloat = (label.style.scalesWithZoom ? 1 : (1 / max(zoom, 0.0001)))
				let localCap = screenCap / scale        // convert to local space (pre-scale)
				
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
					.lineLimit(1)
					.truncationMode(.tail)              // show ellipsis rather than expanding
					.fixedSize(horizontal: false, vertical: true)
					.frame(minWidth: 120, maxWidth: localCap)   // ← cap in local coords
					.padding(.horizontal, 6)
					.padding(.vertical, 4)
			} else {
				Text(label.text)
					.font(font)
					.foregroundStyle(s.textColor.color)
					.padding(.horizontal, s.paddingH)
					.padding(.vertical, s.paddingV)
					.background(
						RoundedRectangle(cornerRadius: s.cornerRadius)
							.fill(s.background.color)
							.overlay(
								RoundedRectangle(cornerRadius: s.cornerRadius)
									.stroke(s.borderColor.color, lineWidth: max(0, s.borderWidth))
							)
					)
					.opacity(s.opacity)
					.shadow(radius: s.shadow)
			}
		}
		.scaleEffect(scale, anchor: .topLeading)
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
				Button("\(p.icon)  \(p.displayName)") { label.style = .preset(p) }
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
	}
	private func cancelEdit() {
		isEditingText = false
	}
	
	private var dragGesture: some Gesture {
		DragGesture(minimumDistance: 0)
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
