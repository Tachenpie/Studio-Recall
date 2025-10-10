//
//  ControlEditorWindow.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

// ControlEditorWindow.swift
import SwiftUI

enum ControlSidebarTab: String, CaseIterable, Identifiable {
	case detect = "Detect"
	case palette = "Palette"
	case inspector = "Inspector"
	var id: String { rawValue }
}

enum LayoutPref: String, CaseIterable { case auto, horizontal, vertical }

struct ControlEditorWindow: View {
	@ObservedObject var editableDevice: EditableDevice
	@Environment(\.dismiss) private var dismiss
	
	@State private var layoutPref: LayoutPref = .auto
	@State private var selectedControlId: UUID? = nil
	@State private var isEditingRegion: Bool = false
	@State private var activeRegionIndex: Int = 0
	@State private var sidebarTab: ControlSidebarTab = .palette
	@State private var zoom: CGFloat = 1.0
	@State private var pan:  CGSize  = .zero
	@State private var isPanning: Bool = false
	@State private var showDetectSheet = false
	@State private var zoomFocusN: CGPoint? = nil
//	@State private var focusNameRequest: UUID? = nil
	@State private var focusNameInPalette: UUID? = nil
	@State private var previewStyle: RenderStyle = .photoreal
	
	// Detect tab shared state
	@State private var pendingDrafts: [ControlDraft] = [] // existing; keep it here
	@State private var detectSelectedIDs: Set<UUID> = []
	@State private var detectSelectedID: UUID? = nil
	@State private var detectLassoRectCanvas: CGRect? = nil // lasso in canvas coordinates
	@State private var detectLassoMode: Bool = false
	@State private var focusedDraftId: UUID? = nil

	// Persistence
	@State private var originalDevice: Device? = nil
	@State private var didCancel: Bool = false
	var onSave: ((Device) -> Void)? = nil
	
	private let detectPaneGutter: CGFloat = 14          // gap between canvas and pane
	private let detectSidebarMin: CGFloat  = 320        // min width for tall layout
	private let detectSidebarMax: CGFloat  = 520        // max width for tall layout
	private let detectContentMax: CGFloat  = 560        // cap inner content width (rows)

	private var isWideFaceplate: Bool {
		switch layoutPref {
			case .auto:
				if let data = editableDevice.device.imageData,
				   let img = NSImage(data: data),
				   let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
					let imageSize = CGSize(width: cg.width, height: cg.height)
					let ar = imageSize.width / max(1, imageSize.height)
					return ar >= 1.6
				} else { return true }
			case .horizontal: return false
			case .vertical: return true
		}
	}
	
	var body: some View {
		NavigationStack {
			Group {
				if isWideFaceplate {
					// Wide 19" gear: stack sidebar UNDER the canvas
					VStack(spacing: 0) {
						faceplateArea
							.frame(minWidth: 480, minHeight: 420)
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
						
						Divider()
						
						sidebar
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
							.padding(.horizontal, 12)
					}
				} else {
					// Tall 500-series: place sidebar to the RIGHT of the canvas
					HStack(alignment: .top, spacing: detectPaneGutter) {
						faceplateArea
							.frame(minWidth: 360)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
						
						Divider()
						
						sidebar
							.frame(maxWidth: .infinity, alignment: .topLeading)
							.padding(.trailing, detectPaneGutter)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					//					}
				}
			}
			.navigationTitle("Edit Controls")
			.toolbarRole(.editor)
			.toolbar {
				// RIGHT: Detect, Add, Done — keep these as separate trailing actions
				ToolbarItem(placement: .primaryAction) {
					Button { sidebarTab = .detect } label: {
						Label("Auto-Detect Controls", systemImage: "wand.and.stars")
					}
				}
				ToolbarItem(placement: .primaryAction) {
					Menu {
						ForEach(ControlType.allCases, id: \.self) { t in
							Button(t.rawValue.capitalized) { addControl(of: t) }
								.onChange(of: selectedControlId) { _, _ in updateZoomFocusFromSelection() }
						}
					} label: { Label("Add Control", systemImage: "plus") }
				}
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						if let snap = originalDevice {
							editableDevice.device = snap
						}
						didCancel = true
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						onSave?(editableDevice.device)
						dismiss()
					}
				}
			}

		}
		.frame(minWidth: 900, minHeight: 560)
		.onAppear {
			if originalDevice == nil {
				originalDevice = editableDevice.device
			}
		}
	}
	
	private var faceplateArea: some View {
		GeometryReader { geo in
			ZStack {
				// We render the faceplate ONCE, and inject the detect overlay into its viewport.
				FaceplateCanvas(
					editableDevice: editableDevice,
					selectedControlId: $selectedControlId,
					isEditingRegion: $isEditingRegion,
					activeRegionIndex: $activeRegionIndex,
					zoom: $zoom,
					pan: $pan,
					zoomFocusN: $zoomFocusN,
					renderStyle: previewStyle,
					externalOverlay: { parentSize, canvasSize, zoom, pan in
						// If we don’t have an image, skip.
						guard let data = editableDevice.device.imageData,
							  let img = NSImage(data: data),
							  let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
							return AnyView(EmptyView())
						}
						let pixelSize = CGSize(width: cg.width, height: cg.height)
						return AnyView(
							DetectDraftsOverlay(
								drafts: $pendingDrafts,
								selectedIDs: $detectSelectedIDs,
								selectedID: $detectSelectedID,
								lassoRectCanvas: $detectLassoRectCanvas,
								isLassoActive: detectLassoMode,
								focusedDraftID: focusedDraftId,
								parentSize: parentSize,
								canvasSize: canvasSize,
								zoom: zoom,
								pan: pan,
								imagePixelSize: pixelSize
							)
						)
					},
					onNewControlDropped: { id in
						selectedControlId = id
						focusNameInPalette = id
					}
				)
				.id(previewStyle == .representative ? "rep-\(editableDevice.revision)" : "photo")
				
				VStack {
					Spacer()
					LeadingToolbarStrip(
						zoom: $zoom,
						isPanning: $isPanning,
						previewStyle: $previewStyle,
						reset: { zoom = 1.0; pan = .zero; zoomFocusN = nil },
						zoomOut: {
							updateZoomFocusFromSelection()
							zoom = max(0.5, zoom / 1.25)
						},
						zoomIn:  {
							updateZoomFocusFromSelection()
							zoom = min(8,   zoom * 1.25)
						}
					)
				}
				.allowsHitTesting(true)
			}
			.clipped()
			.background(Color.black.opacity(0.9))
			.environment(\.isPanMode, isPanning)
		}
	}
	
	private var sidebar: some View {
		VStack(spacing: 0) {
			HStack {
				Picker("", selection: $sidebarTab) {
					ForEach(ControlSidebarTab.allCases) { tab in
						Text(tab.rawValue).tag(tab)
					}
				}
				.pickerStyle(.segmented)
			}
			.frame(maxWidth: 520)
			.padding(.horizontal)
			.padding(.top, 8)
			
			Divider()
				.padding(.vertical, 8)
			
			Group {
				switch sidebarTab {
					case .detect:
						Group {
							if let data = editableDevice.device.imageData,
							   let img  = NSImage(data: data),
							   let cg   = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
								
								DetectReviewView(
									image: img,
									imagePixelSize: CGSize(width: cg.width, height: cg.height),
									drafts: $pendingDrafts,
									// share selection + lasso with the canvas overlay
									selectedIDs: $detectSelectedIDs,
									selectedID:  $detectSelectedID,
									lassoMode:   $detectLassoMode,
									focusedDraftID: $focusedDraftId,
									onCancel: { sidebarTab = .palette },
									onAccept: { accepted in
										let size = CGSize(width: cg.width, height: cg.height)
										let controls  = accepted.makeControlsForDevice(imageSize: size)
										editableDevice.device.controls.append(contentsOf: controls)
										pendingDrafts.removeAll()
										detectSelectedIDs.removeAll()
										detectSelectedID = nil
										detectLassoMode = false
										sidebarTab = .palette
									},
									isWideFaceplate: isWideFaceplate
								)
								.frame(maxWidth: .infinity, maxHeight: .infinity)
								.onChange(of: detectSelectedID) { _, _ in updateZoomFocusFromSelection() }
								.onChange(of: detectSelectedIDs) { _, _ in updateZoomFocusFromSelection() }
							} else {
								ContentUnavailableView("No faceplate image",
													   systemImage: "rectangle.portrait.on.rectangle.portrait")
							}
						}
					case .palette:
						ScrollView {
							ControlPalette(
							editableDevice: editableDevice,
							selectedControlId: $selectedControlId,
							isWideFaceplate: isWideFaceplate,
							focusNameForId: focusNameInPalette
							)
							.padding()
							.onChange(of: selectedControlId) { _, _ in updateZoomFocusFromSelection() }
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
					case .inspector:
						ScrollView {
							ControlInspector(
								editableDevice: editableDevice,
								selectedControlId: $selectedControlId,
								isEditingRegion: $isEditingRegion,
								activeRegionIndex: $activeRegionIndex,
								isWideFaceplate: isWideFaceplate
							)
							.frame(maxWidth: .infinity, alignment: .leading)
							.onChange(of: selectedControlId) { _, _ in updateZoomFocusFromSelection() }
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
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
		focusNameInPalette = c.id
	}
	
	private func updateZoomFocusFromSelection() {
		if let id = selectedControlId,
		   let c  = editableDevice.device.controls.first(where: { $0.id == id }) {
			// prefer the control center
			zoomFocusN = CGPoint(x: max(0,min(1,c.x)), y: max(0,min(1,c.y)))
			return
		}
		// fallback to Detect selection (unchanged)
		guard let data = editableDevice.device.imageData,
			  let img  = NSImage(data: data),
			  let cg   = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
			zoomFocusN = nil
			return
		}
		let px = CGSize(width: cg.width, height: cg.height)
		if let id = detectSelectedID ?? detectSelectedIDs.first,
		   let d  = pendingDrafts.first(where: { $0.id == id }) {
			zoomFocusN = CGPoint(x: max(0, min(1, d.center.x / px.width)),
								 y: max(0, min(1, d.center.y / px.height)))
		} else {
			zoomFocusN = nil
		}
	}
}

private struct LeadingToolbarStrip: View {
	@Binding var zoom: CGFloat
	@Binding var isPanning: Bool
	@Binding var previewStyle: RenderStyle
	var reset: () -> Void
	var zoomOut: () -> Void
	var zoomIn: () -> Void
	
	var body: some View {
		HStack(spacing: 10) {
			// Reset zoom/pan
			Button(action: reset) {
				Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
			}
			.help("Reset zoom & pan")
			
			// Pan toggle
			Button { isPanning.toggle() } label: {
				Image(systemName: isPanning ? "hand.draw.fill" : "hand.draw")
			}
			.help("Pan view (\(isPanning ? "On" : "Hold ⌘ to pan"))")
			
			// Zoom controls (kept compact)
			HStack(spacing: 6) {
				Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
				Slider(value: $zoom, in: 0.5...8, step: 0.01)
					.frame(width: 140)
				Button(action: zoomIn)  { Image(systemName: "plus.magnifyingglass") }
			}
			
			Divider().frame(height: 18)
			
			// Preview style (Photo / Rep)
			Picker("Preview", selection: $previewStyle) {
				Text("Photo").tag(RenderStyle.photoreal)
				Text("Rep").tag(RenderStyle.representative)
			}
			.pickerStyle(.segmented)
			.frame(width: 160)
			.help("Preview controls using representative glyphs")
		}
		.padding(.horizontal, 10).padding(.vertical, 6)
		.background(.ultraThinMaterial, in: Capsule())
	}
}

	// MARK: - DraftsCanvasOverlay (Detect overlay drawn on top of FaceplateCanvas)
	private struct DraftsCanvasOverlay: View {
		@Binding var drafts: [ControlDraft]
		@Binding var selectedIDs: Set<UUID>
		@Binding var selectedID: UUID?
		@Binding var lassoRect: CGRect?
		@Binding var isLassoActive: Bool
		
		let canvasSize: CGSize           // actual on-screen canvas size
		let imagePixelSize: CGSize       // faceplate image size in pixels
		
		var body: some View {
			// We assume FaceplateCanvas renders the faceplate to fill the canvas rect.
			// Draft.rect is in TL pixel coords; scale to canvas-space 1:1.
			ZStack(alignment: .topLeading) {
				// Interaction layer (for lasso)
				Color.clear
					.contentShape(Rectangle())
					.gesture(lassoGesture)
				
				// Draft boxes (force value iteration)
				ForEach(drafts.indices, id: \.self) { i in
					let d = drafts[i]
					let rectV = pxRectToCanvas(d.rect)
					let isSel = selectedIDs.contains(d.id) || (selectedID == d.id)
					
					ZStack(alignment: .topLeading) {
						Rectangle()
							.stroke(isSel ? Color.accentColor : .yellow,
									style: StrokeStyle(lineWidth: isSel ? 3 : 2, dash: [6,4]))
							.frame(width: rectV.width, height: rectV.height)
							.position(x: rectV.midX, y: rectV.midY)
						
						Circle()
							.stroke(isSel ? Color.accentColor : .yellow, lineWidth: 2)
							.frame(width: 10, height: 10)
							.position(x: rectV.midX, y: rectV.midY)
					}
					.contentShape(Rectangle())
					.onTapGesture {
						selectedID = d.id
#if os(macOS)
						if NSEvent.modifierFlags.contains(.command) || isLassoActive {
							if selectedIDs.contains(d.id) { selectedIDs.remove(d.id) } else { selectedIDs.insert(d.id) }
						} else {
							selectedIDs = [d.id]
						}
#else
						if isLassoActive {
							if selectedIDs.contains(d.id) { selectedIDs.remove(d.id) } else { selectedIDs.insert(d.id) }
						} else {
							selectedIDs = [d.id]
						}
#endif
					}
				}

				// Lasso rect drawing
				if let rect = lassoRect, isLassoActive {
					Rectangle()
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5,3]))
						.background(Color.accentColor.opacity(0.10))
						.frame(width: rect.width, height: rect.height)
						.position(x: rect.midX, y: rect.midY)
				}
			}
			.frame(width: canvasSize.width, height: canvasSize.height)
			.allowsHitTesting(isLassoActive) // only capture drags when lasso is on
		}
		
		// Scale TL pixel rect to canvas-space rect
		private func pxRectToCanvas(_ px: CGRect) -> CGRect {
			let sx = canvasSize.width  / max(1, imagePixelSize.width)
			let sy = canvasSize.height / max(1, imagePixelSize.height)
			return CGRect(x: px.origin.x * sx,
						  y: px.origin.y * sy,
						  width:  px.width  * sx,
						  height: px.height * sy)
		}
		
		// Compute drafts intersecting a view-space rect
		private func hitDrafts(in viewRect: CGRect) -> Set<UUID> {
			var hits: Set<UUID> = []
			for d in drafts {
				if pxRectToCanvas(d.rect).intersects(viewRect) { hits.insert(d.id) }
			}
			return hits
		}
		
		private var lassoGesture: some Gesture {
			DragGesture(minimumDistance: 0)
				.onChanged { value in
					guard isLassoActive else { return }
					let x0 = max(0, min(value.startLocation.x, value.location.x))
					let y0 = max(0, min(value.startLocation.y, value.location.y))
					let x1 = min(canvasSize.width,  max(value.startLocation.x, value.location.x))
					let y1 = min(canvasSize.height, max(value.startLocation.y, value.location.y))
					lassoRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
					
					if let rect = lassoRect {
						selectedIDs = hitDrafts(in: rect)
					}
				}
				.onEnded { _ in }
		}
	}

// MARK: - DetectDraftsOverlay (draws detection boxes/labels/lasso in parent-space)
private struct DetectDraftsOverlay: View {
	@Binding var drafts: [ControlDraft]
	@Binding var selectedIDs: Set<UUID>
	@Binding var selectedID: UUID?
	@Binding var lassoRectCanvas: CGRect?
	let isLassoActive: Bool
	
	// who is focused in the list TextField
	let focusedDraftID: UUID?
	
	let parentSize: CGSize    // the whole viewport
	let canvasSize: CGSize    // unscaled canvas
	let zoom: CGFloat
	let pan: CGSize
	let imagePixelSize: CGSize
	
	private var draftItems: [ControlDraft] { drafts }
	
	// pulse used for the focused “target” ring
	@State private var pulse: Bool = false
	
	var body: some View {
		ZStack(alignment: .topLeading) {
			Color.clear
				.contentShape(Rectangle())
				.gesture(lassoGesture)
			
			// Boxes + labels (iterate elements directly to avoid Binding ForEach overload)
			ForEach(draftItems, id: \.id) { d in
				let rectCanvas = pxRectToCanvas(d.rect)
				let rectParent = canvasRectToParent(rectCanvas)
				
				let isSel = selectedIDs.contains(d.id) || selectedID == d.id
				let isFocused = (focusedDraftID == d.id)
				
				let strokeBase: Color = d.kind.tint
				let strokeColor: Color = isSel ? .accentColor : strokeBase
				let trimmed = d.label.trimmingCharacters(in: .whitespacesAndNewlines)
				let name = trimmed.isEmpty ? displayName(for: d, within: draftItems) : trimmed
				
				ZStack(alignment: .topLeading) {
					// Focus glow (below everything)
					if isFocused {
						Rectangle()
							.fill(Color.accentColor.opacity(0.12))
							.frame(width: rectParent.width, height: rectParent.height)
							.position(x: rectParent.midX, y: rectParent.midY)
							.blur(radius: 1.0)
							.shadow(color: .accentColor.opacity(0.50), radius: 10, x: 0, y: 0)
					}
					
					// Selection/fallback stroke
					Rectangle()
						.stroke(strokeColor, style: StrokeStyle(lineWidth: isSel ? 3 : 2, dash: [6,4]))
						.frame(width: rectParent.width, height: rectParent.height)
						.position(x: rectParent.midX, y: rectParent.midY)
					
					// Crisp inner hairline when focused
					if isFocused {
						Rectangle()
							.stroke(Color.white.opacity(0.9), lineWidth: 1)
							.frame(width: rectParent.width - 2, height: rectParent.height - 2)
							.position(x: rectParent.midX, y: rectParent.midY)
					}
					
					// Center “target” ring (pulses if focused)
					Circle()
						.stroke(isFocused ? Color.accentColor : strokeColor, lineWidth: 2)
						.frame(width: isFocused ? 14 : 10, height: isFocused ? 14 : 10)
						.scaleEffect(isFocused && pulse ? 1.10 : 1.0)
						.opacity(isFocused ? 0.95 : 1.0)
						.position(x: rectParent.midX, y: rectParent.midY)
						.animation(isFocused ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse)
					
					// Label pill near top-left of the box (single line, compact)
					Text(name)
						.font(.system(size: 11, weight: .semibold, design: .rounded))
						.lineLimit(1)
						.truncationMode(.tail)
						.fixedSize(horizontal: true, vertical: true) // never wrap/grow
						.padding(.horizontal, 6).padding(.vertical, 2)
						.background(
							Capsule().fill(isFocused ? Color.accentColor.opacity(0.18)
										   : Color.black.opacity(0.35))
						)
						.foregroundColor(isFocused ? .accentColor : strokeColor)
						.shadow(color: .black.opacity(0.65), radius: 1, x: 0, y: 1)
						.offset(x: rectParent.minX, y: rectParent.minY - 18)
				}
				.contentShape(Rectangle())
				.onTapGesture {
#if os(macOS)
					if NSEvent.modifierFlags.contains(.command) {
						if selectedIDs.contains(d.id) { selectedIDs.remove(d.id) } else { selectedIDs.insert(d.id) }
						selectedID = d.id
					} else {
						selectedIDs = [d.id]
						selectedID = d.id
					}
#else
					selectedIDs = [d.id]
					selectedID = d.id
#endif
				}
			}
			
			// Lasso
			if let rCanvas = lassoRectCanvas, isLassoActive {
				let rParent = canvasRectToParent(rCanvas)
				Rectangle()
					.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5,3]))
					.background(Color.accentColor.opacity(0.10))
					.frame(width: rParent.width, height: rParent.height)
					.position(x: rParent.midX, y: rParent.midY)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.allowsHitTesting(isLassoActive)
		.onAppear {
			withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
				pulse = true
			}
		}
	}
	
	// MARK: mapping (pixels → canvas → parent)
	private func pxRectToCanvas(_ px: CGRect) -> CGRect {
		let sx = canvasSize.width  / max(1, imagePixelSize.width)
		let sy = canvasSize.height / max(1, imagePixelSize.height)
		return CGRect(x: px.origin.x * sx,
					  y: px.origin.y * sy,
					  width:  px.width  * sx,
					  height: px.height * sy)
	}
	private func canvasPointToParent(_ p: CGPoint) -> CGPoint {
		let originX = (parentSize.width  - canvasSize.width)  * 0.5
		let originY = (parentSize.height - canvasSize.height) * 0.5
		let shiftX  = canvasSize.width  * 0.5 * (1 - zoom)
		let shiftY  = canvasSize.height * 0.5 * (1 - zoom)
		return CGPoint(x: p.x * zoom + originX + shiftX + pan.width,
					   y: p.y * zoom + originY + shiftY + pan.height)
	}
	private func canvasRectToParent(_ r: CGRect) -> CGRect {
		let o = canvasPointToParent(r.origin)
		return CGRect(origin: o, size: CGSize(width: r.width * zoom, height: r.height * zoom))
	}
	private func parentPointToCanvas(_ p: CGPoint) -> CGPoint {
		let originX = (parentSize.width  - canvasSize.width)  * 0.5
		let originY = (parentSize.height - canvasSize.height) * 0.5
		let shiftX  = canvasSize.width  * 0.5 * (1 - zoom)
		let shiftY  = canvasSize.height * 0.5 * (1 - zoom)
		return CGPoint(
			x: (p.x - originX - shiftX - pan.width)  / zoom,
			y: (p.y - originY - shiftY - pan.height) / zoom
		).clampedPoint(to: CGRect(origin: .zero, size: canvasSize))
	}
	private var lassoGesture: some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { value in
				guard isLassoActive else { return }
				let a = parentPointToCanvas(value.startLocation)
				let b = parentPointToCanvas(value.location)
				let x0 = min(a.x, b.x), y0 = min(a.y, b.y)
				let x1 = max(a.x, b.x), y1 = max(a.y, b.y)
				lassoRectCanvas = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
				if let rect = lassoRectCanvas {
					selectedIDs = Set(draftItems.compactMap { d in
						let rC = pxRectToCanvas(d.rect)
						return rC.intersects(rect) ? d.id : nil
					})
				}
			}
			.onEnded { _ in }
	}
	
	// MARK: naming rule (same as list)
	private func baseName(for kind: ControlType) -> String {
		switch kind {
			case .knob, .steppedKnob, .concentricKnob: return "Knob"
			case .button, .litButton: return "Button"
			case .multiSwitch: return "Switch"
			case .light: return "Lamp"
		}
	}
	private func displayName(for d: ControlDraft, within all: [ControlDraft]) -> String {
		let base = baseName(for: d.kind)
		let tolY: CGFloat = 16
		let peers = all.filter { $0.kind == d.kind }.sorted {
			if abs($0.center.y - $1.center.y) > tolY { return $0.center.y < $1.center.y }
			return $0.center.x < $1.center.x
		}
		if let i = peers.firstIndex(where: { $0.id == d.id }) { return "\(base) \(i+1)" }
		return base
	}
}

private extension CGPoint {
	func clampedPoint(to rect: CGRect) -> CGPoint {
		CGPoint(x: max(rect.minX, min(rect.maxX, x)),
				y: max(rect.minY, min(rect.maxY, y)))
	}
}

private extension ControlType {
	var tint: Color {
		switch self {
			case .knob: .green
			case .steppedKnob: .teal
			case .concentricKnob: .mint
			case .button: .blue
			case .litButton: .purple
			case .multiSwitch: .orange
			case .light: .red
		}
	}
}

private extension CGPoint {
	func clamped(to rect: CGRect) -> CGPoint {
		CGPoint(x: max(rect.minX, min(rect.maxX, x)),
				y: max(rect.minY, min(rect.maxY, y)))
	}
}

private extension Array where Element == ControlDraft {
	/// Return a copy where any empty label is filled with a row-major unique name per-kind:
	/// top→bottom (with small Y tolerance), then left→right.
	func seededDefaultLabels() -> [ControlDraft] {
		func baseName(for kind: ControlType) -> String {
			switch kind {
				case .knob, .steppedKnob, .concentricKnob: return "Knob"
				case .button, .litButton: return "Button"
				case .multiSwitch: return "Switch"
				case .light: return "Lamp"
			}
		}
		func displayName(for d: ControlDraft, within all: [ControlDraft]) -> String {
			let base = baseName(for: d.kind)
			let tolY: CGFloat = 16
			let peers = all.filter { $0.kind == d.kind }.sorted {
				if abs($0.center.y - $1.center.y) > tolY { return $0.center.y < $1.center.y }
				return $0.center.x < $1.center.x
			}
			if let i = peers.firstIndex(where: { $0.id == d.id }) { return "\(base) \(i+1)" }
			return base
		}
		return self.map { d in
			var c = d
			if c.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				c.label = displayName(for: c, within: self)
			}
			return c
		}
	}
	
	/// Mutating convenience.
	mutating func seedDefaultLabelsInPlace() {
		self = self.seededDefaultLabels()
	}
}
