//
//  ControlEditorWindow.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

// ControlEditorWindow.swift
import SwiftUI

enum ControlSidebarTab: String, CaseIterable, Identifiable {
	case palette = "Palette"
	case inspector = "Inspector"
	var id: String { rawValue }
}

struct ControlEditorWindow: View {
	@ObservedObject var editableDevice: EditableDevice
	@Environment(\.dismiss) private var dismiss
	
	@State private var selectedControlId: UUID? = nil
	@State private var isEditingRegion: Bool = false
	@State private var sidebarTab: ControlSidebarTab = .palette
	@State private var zoom: CGFloat = 1.0
	@State private var pan:  CGSize  = .zero
	@State private var isPanning: Bool = false
	
	var body: some View {
		NavigationStack {
			HStack(spacing: 0) {
				// Canvas
				FaceplateCanvas(
					editableDevice: editableDevice,
					selectedControlId: $selectedControlId,
					isEditingRegion: $isEditingRegion,
					zoom: $zoom,
					pan: $pan
				)
				.frame(minWidth: 400, minHeight: 400)
				.background(Color.black.opacity(0.9))
				.environment(\.isPanMode, isPanning)
				
				Divider()
				
				// Sidebar: Palette or Inspector
				VStack(spacing: 0) {
					HStack {
						Picker("", selection: $sidebarTab) {
							ForEach(ControlSidebarTab.allCases) { tab in
								Text(tab.rawValue).tag(tab)
							}
						}
						.pickerStyle(.segmented)
						
						Spacer()
						
						// Zoom slider
						HStack(spacing: 6) {
							Button(
								action: { zoom = max(0.5, zoom / 1.25) }
							) {
								Image(systemName: "minus.magnifyingglass")
							}
							Slider(value: $zoom, in: 0.5...8, step: 0.01).frame(width: 120)
							Button(
								action: { zoom = min(8, zoom * 1.25) }
							) {
								Image(systemName: "plus.magnifyingglass")
							}
						}
					}
					.padding(.horizontal)
					.padding(.top, 8)
					
					Divider()
					
					Group {
						switch sidebarTab {
							case .palette:
								ScrollView { ControlPalette(
									editableDevice: editableDevice,
									selectedControlId: $selectedControlId
								).padding() }
									.frame(maxWidth: .infinity, maxHeight: .infinity)
							case .inspector:
								ScrollView {
									ControlInspector(
										editableDevice: editableDevice,
										selectedControlId: $selectedControlId,
										isEditingRegion: $isEditingRegion,
										activeRegionIndex: $activeRegionIndex
									)
									.frame(maxWidth: .infinity, alignment: .leading)
								}
								.frame(maxWidth: .infinity, maxHeight: .infinity)
						}
					}

				}
				.frame(width: 450)
			}
			.navigationTitle("Edit Controls")
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button(action: { isPanning.toggle() }) {
						Image(systemName: isPanning ? "hand.draw.fill" : "hand.draw")
					}
					.help("Pan view (\(isPanning ? "On" : "Hold ⌘ to pan"))")
				}
				
				ToolbarItem(placement: .primaryAction) {
					Button(action: { zoom = 1.0; pan = .zero }) {
						Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
					}
					.help("Reset zoom & pan")
				}
				// Quick Add menu for keyboard-only users
				ToolbarItem(placement: .primaryAction) {
					Menu {
						ForEach(ControlType.allCases, id: \.self) { t in
							Button(t.rawValue.capitalized) {
								addControl(of: t)
							}
						}
					} label: {
						Label("Add Control", systemImage: "plus")
					}
				}
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
		.frame(minWidth: 900, minHeight: 560)
	}
	
	private func addControl(of type: ControlType) {
		var c = Control(
			name: type.displayName,
			type: type,
			x: 0.5, y: 0.5
		)
		// snap to your 5% grid
		c.x = (c.x / 0.05).rounded() * 0.05
		c.y = (c.y / 0.05).rounded() * 0.05
		
		editableDevice.device.controls.append(c)
		selectedControlId = c.id
		sidebarTab = .inspector
	}
}
