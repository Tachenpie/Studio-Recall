//
//  ControlPalette.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

// MARK: - Top-level
private let EXISTING_LEADING_WIDTH: CGFloat = 220

struct ControlPalette: View {
	@ObservedObject var editableDevice: EditableDevice
	@Binding var selectedControlId: UUID?
	
	@State private var searchText: String = ""
	
	let isWideFaceplate: Bool
	var focusNameForId: UUID? = nil
	
	@FocusState private var focusedRowId: UUID?
	
	var body: some View {
		ScrollViewReader { outerProxy in
			Group {
				if isWideFaceplate {
					HStack(alignment: .top, spacing: 12) {
						VStack {
							SectionHeader(title: "New Controls")
							NewControlsGrid() // simple grid of tiles
						}
						Divider().opacity(0.1).padding(.leading, 6)
						VStack {
							SectionHeader(title: "Controls on Faceplate")
							// Anchor so the OUTER scroll view can snap to the list section
							Color.clear.frame(height: 0).id("existing-list")
							SearchField(text: $searchText)
							
							ExistingControlsList(
								controls: filtered(editableDevice.device.controls, by: $searchText.wrappedValue),
								selectedId: $selectedControlId,
								focused: $focusedRowId,
								onDelete: deleteControl,
								onRename: { id, newName in
									if let i = editableDevice.device.controls.firstIndex(where: { $0.id == id }) {
										editableDevice.device.controls[i].name = newName
									}
								}
							)
						}
					}
					.padding(12)
				} else {
					VStack(spacing: 12) {
						SectionHeader(title: "New Controls")
						NewControlsGrid() // simple grid of tiles
						
						Divider().opacity(0.1).padding(.top, 6)
						
						SectionHeader(title: "Controls on Faceplate")
						// Anchor for the OUTER scroll view
						Color.clear.frame(height: 0).id("existing-list")
						SearchField(text: $searchText)
						
						ExistingControlsList(
							controls: filtered(editableDevice.device.controls, by: $searchText.wrappedValue),
							selectedId: $selectedControlId,
							focused: $focusedRowId,
							onDelete: deleteControl,
							onRename: { id, newName in
								if let i = editableDevice.device.controls.firstIndex(where: { $0.id == id }) {
									editableDevice.device.controls[i].name = newName
								}
							}
						)
					}
					.padding(12)
				}
			}
#if os(macOS)
			.background(Color(NSColor.controlBackgroundColor))
#else
			.background(Color(UIColor.secondarySystemBackground))
#endif
			.onChange(of: focusNameForId) { _, req in
				guard let req else { return }
				searchText = ""
				selectedControlId = req
				focusedRowId = req
				withAnimation(.easeInOut(duration: 0.2)) {
					outerProxy.scrollTo("existing-list", anchor: .top)
				}
			}
		}
	}
	
	// Filtering kept simple & explicit (helps type-checker)
	private func filtered(_ items: [Control], by query: String) -> [Control] {
		let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if q.isEmpty {
			return items                 // ← keep device order (stable while editing)
		} else {
			let filtered = items.filter { c in
				let name = (c.name.isEmpty ? c.type.displayName : c.name).lowercased()
				return name.contains(q)
			}
			return filtered.sorted { a, b in
				let an = a.name.isEmpty ? a.type.displayName : a.name
				let bn = b.name.isEmpty ? b.type.displayName : b.name
				return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
			}
		}
	}
	
	private func deleteControl(_ id: UUID) {
		if let i = editableDevice.device.controls.firstIndex(where: { $0.id == id }) {
			_ = editableDevice.device.controls.remove(at: i)
			if selectedControlId == id { selectedControlId = nil }
		}
	}
	
	private func renameControl(_ id: UUID, to newName: String) {
		if let i = editableDevice.device.controls.firstIndex(where: { $0.id == id }) {
			editableDevice.device.controls[i].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		}
	}
}

// MARK: - Section header (tiny, typed)

private struct SectionHeader: View {
	let title: String
	var body: some View {
		HStack(spacing: 8) {
			Text(title.uppercased())
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
			Rectangle().fill(.separator.opacity(0.35)).frame(height: 1)
		}
		.frame(maxWidth: .infinity)
		.padding(.horizontal, 2)
	}
}

// MARK: - Search field

private struct SearchField: View {
	@Binding var text: String
	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
			TextField("Search controls…", text: $text)
				.textFieldStyle(.plain)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color.secondary.opacity(0.15))
		)
#if os(macOS)
		.onSubmit(of: .text) { }
#endif
	}
}

// MARK: - New controls grid

private struct NewControlsGrid: View {
	private let cols: [GridItem] = [
		GridItem(.adaptive(minimum: 100), spacing: 10)   // ← uniform-ish
	]
	
	var body: some View {
		LazyVGrid(columns: cols, spacing: 10) {
			ForEach(ControlType.allCases, id: \.self) { type in
				NewControlTile(type: type)
			}
		}
		.padding(.horizontal, 8)
	}
}

private struct NewControlTile: View {
	let type: ControlType
	@State private var isHovering: Bool = false
	
	var body: some View {
		VStack(spacing: 6) {
			ControlView(
				control: .constant(Control(name: type.displayName, type: type, x: 0.5, y: 0.5))
			)
			.frame(width: 34, height: 34)
			.allowsHitTesting(false)
			
			Text(type.displayName)
				.font(.caption2)
				.lineLimit(1)
				.foregroundStyle(.primary)
		}
		.frame(width: 100, height: 68)  // ← fixed footprint
		.padding(6)
		.background(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.fill(Color.gray.opacity(isHovering ? 0.25 : 0.15))
				.overlay(
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.stroke(.separator.opacity(isHovering ? 0.9 : 0.35))
				)
		)
#if os(macOS)
		.help("Drag onto the faceplate")
		.onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovering = h } }
#endif
		.draggable(type.rawValue) {
			ControlView(control: .constant(Control(name: type.displayName, type: type, x: 0.5, y: 0.5)))
				.frame(width: 40, height: 40)
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
		}
	}
}


// MARK: - Existing controls list
private struct ExistingControlsList: View {
	let controls: [Control]
	@Binding var selectedId: UUID?
	
	var focused: FocusState<UUID?>.Binding
	var onDelete: (UUID) -> Void
	var onRename: (UUID, String) -> Void
	
	var body: some View {
		if controls.isEmpty {
			Text("No controls yet")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.vertical, 8)
		} else {
			ScrollViewReader { proxy in
				// Cap height so it scrolls instead of expanding forever
				ScrollView {
					LazyVStack(spacing: 0) {
						ForEach(controls) { c in
							VStack(spacing: 0) {
								ExistingRow(
									control: c,
									isSelected: c.id == selectedId,
									focused: focused,
									onSelect: { selectedId = c.id },
									onDelete: { onDelete(c.id) },
									onRename: { newName in onRename(c.id, newName) }
								)
								Divider().opacity(0.08).padding(.leading, 26)
							}
							.id(c.id)
						}
					}
					.padding(4)
				}
				.frame(maxHeight: 240)
				.onChange(of: selectedId) { _, target in
						guard let target else { return }
					// Defer one tick so the row exists in the stack before scrolling
					DispatchQueue.main.async {
						withAnimation(.easeInOut(duration: 0.2)) {
							proxy.scrollTo(target, anchor: .center)
						}
					}
				}
				.background(
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(.thinMaterial.opacity(0.2))
						.overlay(
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.stroke(.separator.opacity(0.35), lineWidth: 1)
						)
				)
			}
		}
	}
}

private struct ExistingRow: View {
	let control: Control
	let isSelected: Bool
	let focused: FocusState<UUID?>.Binding
	let onSelect: () -> Void
	let onDelete: () -> Void
	let onRename: (String) -> Void
	
	@State private var isHovering = false
	
	private var nameBinding: Binding<String> {
		Binding(
			get: {
				let display = control.name.isEmpty ? control.type.displayName : control.name
				return display
			},
			set: { onRename($0) }
		)
	}
	
	var body: some View {
		HStack(spacing: 8) {
			// Leading "badge" area (fixed width so names line up)
			HStack(spacing: 8) {
				Image(systemName: iconForType(control.type))
					.frame(width: 18, alignment: .leading)

				TextField("Name", text: nameBinding)
					.textFieldStyle(.roundedBorder)
					.onSubmit { onRename(nameBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
					.lineLimit(1)
					.truncationMode(.tail)
					.focused(focused, equals: control.id)
					.font(.callout)
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.frame(width: EXISTING_LEADING_WIDTH, alignment: .leading)
			.background(
				ZStack {
					// Constant style; toggle opacity only (type-stable)
					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.fill(Color.accentColor)
						.opacity((isSelected || isHovering) ? 0.12 : 0.0)

					RoundedRectangle(cornerRadius: 6, style: .continuous)
						.stroke(.separator.opacity(0.35), lineWidth: 1)
				}
			)

			Spacer()

			// Actions
			Button {
				onDelete()
			} label: {
				Image(systemName: "trash")
					.imageScale(.medium)
					.opacity(0.9)
					.padding(6)
			}
			.buttonStyle(.plain)
			.help("Delete")
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 4)
		.contentShape(Rectangle())
		.onTapGesture {
			onSelect()
			// Immediately focus the textfield when selecting
			DispatchQueue.main.async {
				focused.wrappedValue = control.id
			}
		}
		.onChange(of: isSelected) { _, now in
			// When selected (from anywhere), focus the textfield
			if now {
				DispatchQueue.main.async {
					focused.wrappedValue = control.id
				}
			}
		}
#if os(macOS)
		.onHover { isHovering = $0 }
#endif
	}
	
	private func displayName(_ c: Control) -> String {
		c.name.isEmpty ? c.type.displayName : c.name
	}
}


private struct PaletteTile: View {
	let title: String
	let systemImage: String
	let action: () -> Void
	
	var body: some View {
		Button(action: action) {
			VStack(spacing: 6) {
				Image(systemName: systemImage).font(.title3)
				Text(title).font(.caption).lineLimit(1).truncationMode(.tail)
			}
			.frame(width: 120, height: 68)       // ← UNIFORM footprint
			.contentShape(RoundedRectangle(cornerRadius: 8))
		}
		.buttonStyle(.plain)
		.padding(6)
		.hoverTile()                             // ← uses HoverEffectView.swift
		.help(title)
	}
}

// MARK: - Icon helper (explicit switch keeps type-checker happy)

private func iconForType(_ t: ControlType) -> String {
	switch t {
		case .knob:           return "dial.medium"
		case .steppedKnob:    return "dial.low"
		case .multiSwitch:    return "switch.2"
		case .button:         return "circle.circle"
		case .light:          return "lightbulb"
		case .concentricKnob: return "dial.high"
		case .litButton:      return "light.beacon.max"
	}
}
