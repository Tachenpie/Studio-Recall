//
//  RackChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI
import AppKit

struct RackChassisSlotView: View {
	let row: Int
	let col: Int
	let instance: DeviceInstance?
	/// If provided, this view renders *entirely* from the prelayout (no GeometryReader).
	let prelayout: SlotPrelayout?
	
	private let railWidth: CGFloat = 24
	private let thinRailWidth: CGFloat = 4
	private let hoverRevealWidth: CGFloat = 12
	
	@Binding var slots: [[DeviceInstance?]]
	@EnvironmentObject var settings: AppSettings
	@EnvironmentObject var library: DeviceLibrary
	@EnvironmentObject var sessionManager: SessionManager
	
	@Environment(\.isInteracting) private var isInteracting
	@Environment(\.canvasLOD) private var lod
	@Environment(\.renderStyle) private var renderStyle
	@Environment(\.canvasZoom) private var canvasZoom
	
	@Binding var hoveredIndex: Int?
	@Binding var hoveredValid: Bool
	@Binding var hoveredRange: Range<Int>?
	@Binding var hoveredRows:  Range<Int>?
	
	@State private var hoverLeft = false
	@State private var hoverRight = false
	@State private var editingDevice: Device?
	@State private var isPresentingEditor = false
	@State private var hoverBubbleActive = false
	
	@State private var showHitRects: Bool = true
	
	var body: some View {
		Group {
			if let instance, let device = library.device(for: instance.deviceID) {
				deviceView(device, instance: instance)
			} else {
				EmptyView()
			}
		}
	}
	
	// MARK: - Device view (prelayout-driven if available)
	private func deviceView(_ device: Device, instance: DeviceInstance) -> some View {
		guard let anchor = anchorOfInstance(instance) else { return AnyView(EmptyView()) }
		let instanceBinding = binding(for: device, instance: instance, at: anchor)
		
		if let L = prelayout {
			// MARK: sizes
			let rowWidthPts = settings.pointsPerInch * 19.0
			let railEps: CGFloat = 0.25
			
			let slotH = L.heightPts
			let faceW = L.faceWidthPts
			let isPartial = (device.rackWidth != .full)
			let showHoverRails = !isPartial  // full-width only

			// Wings are already correctly calculated in prelayout - use them directly
			let wingL_eff = L.leftWingPts
			let wingR_eff = L.rightWingPts

			// MARK: face metrics (single source of truth)
			let metrics = DeviceMetrics.faceRenderMetrics(
				faceWidthPts: faceW,
				slotHeightPts: slotH,
				imageData: device.imageData
			)
			
			// MARK: face + controls (aligned to rendered face)
			let faceGroup = ZStack(alignment: .topLeading) {
				Group {
					if renderStyle == .representative {
						// Fast path: vector face, no PNG
						DeviceView(device: device, metrics: metrics)
					} else {
						if let data = device.imageData, let nsimg = NSImage(data: data) {
							let key = device.id.uuidString + "#" + String(data.count)

							switch lod {
								case .full:
									// Original resolution: > 125% zoom
									Image(nsImage: nsimg)
										.resizable()
										.interpolation(.high)
										.antialiased(true)
										.aspectRatio(nsimg.size, contentMode: .fit)

								case .level1:
									// 1/2 resolution: 75-125% zoom
									// For a 2000x500 image → 1000px max
									let original = max(nsimg.size.width, nsimg.size.height)
									let target = original * 0.5
									if let down = nsimg.lodImage(maxPixel: target, cacheKey: key) {
										Image(nsImage: down)
											.resizable()
											.interpolation(.medium)
											.aspectRatio(down.size, contentMode: .fit)
									} else {
										Image(nsImage: nsimg)
											.resizable()
											.interpolation(.medium)
											.aspectRatio(nsimg.size, contentMode: .fit)
									}

								case .level2:
									// 1/4 resolution: 40-75% zoom
									// For a 2000x500 image → 500px max
									let original = max(nsimg.size.width, nsimg.size.height)
									let target = original * 0.25
									if let down = nsimg.lodImage(maxPixel: target, cacheKey: key) {
										Image(nsImage: down)
											.resizable()
											.interpolation(.medium)
											.aspectRatio(down.size, contentMode: .fit)
									} else {
										Rectangle().fill(Color.secondary.opacity(0.12))
									}

								case .level3:
									// 1/8 resolution: < 40% zoom
									// For a 2000x500 image → 250px max
									let original = max(nsimg.size.width, nsimg.size.height)
									let target = original * 0.125
									if let tiny = nsimg.lodImage(maxPixel: target, cacheKey: key) {
										Image(nsImage: tiny)
											.resizable()
											.interpolation(.low)
											.aspectRatio(tiny.size, contentMode: .fit)
									} else {
										Rectangle().fill(Color.secondary.opacity(0.12))
									}

								// Legacy compatibility
								case .medium:
									// Redirect to level2 (1/4 resolution)
									let original = max(nsimg.size.width, nsimg.size.height)
									let target = original * 0.25
									if let down = nsimg.lodImage(maxPixel: target, cacheKey: key) {
										Image(nsImage: down)
											.resizable()
											.interpolation(.medium)
											.aspectRatio(down.size, contentMode: .fit)
									} else {
										Rectangle().fill(Color.secondary.opacity(0.12))
									}

								case .low:
									// Redirect to level3 (1/8 resolution)
									let original = max(nsimg.size.width, nsimg.size.height)
									let target = original * 0.125
									if let tiny = nsimg.lodImage(maxPixel: target, cacheKey: key) {
										Image(nsImage: tiny)
											.resizable()
											.interpolation(.low)
											.aspectRatio(tiny.size, contentMode: .fit)
									} else {
										Rectangle().fill(Color.secondary.opacity(0.12))
									}
							}
						} else {
							DeviceView(device: device)
								.modifier(ConditionalDrawingGroup(active: isInteracting || settings.parentInteracting))
						}
					}
				}
				.frame(width: metrics.size.width, height: metrics.size.height)
				.allowsHitTesting(false)

//				if renderStyle == .representative || lod == .full {
					RuntimeControlsOverlay(
						device: device,
						instance: instanceBinding,
						prelayout: L,
						faceMetrics: metrics
					)
					.frame(width: metrics.size.width, height: metrics.size.height)
					.environment(\.isRegionEditing, false)
					.zIndex(1)
					
//				}
				
				
				
				if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
					let session = $sessionManager.sessions[i]
					LabelCanvas(
						labels: session.labels,
						anchor: .deviceInstance(instance.id),
						parentOrigin: .zero
					)
					.allowsHitTesting(true)
				}

			}
			
			// MARK: content stack (LEFT-side interactors live here)
			let base = ZStack(alignment: .topLeading) {
				// face centered vertically once
				faceGroup
//					.offset(x: L.leftWingPts + L.leftRailPts, y: metrics.vOffset)
					.offset(x: wingL_eff + L.leftRailPts, y: metrics.vOffset)
//				#if DEBUG
//					.overlay(alignment: .topLeading) {
//						if showHitRects {
//							GeometryReader { g in
//								let faceSize = g.size
//								ZStack(alignment: .topLeading) {
//									ForEach(device.controls) { def in
//										let r = def.bounds(in: faceSize)
//										Path { p in
//											p.addRect(r)
//										}
//										.stroke(.red.opacity(0.65), lineWidth: 1)
//										.overlay(
//											Text(def.name)
//												.font(.system(size: 9, weight: .medium, design: .rounded))
//												.padding(2)
//												.background(.black.opacity(0.5))
//												.foregroundStyle(.white)
//												.clipShape(RoundedRectangle(cornerRadius: 3))
//												.position(x: r.minX + 4 + 24, y: r.minY - 8) // tiny tag near the rect
//										)
//									}
//								}
//							}
//							.allowsHitTesting(false)
//						}
//					}
//				#endif
				// LEFT wing (partials only)
				if isPartial, wingL_eff > 0 {
					WingPlate()
						.frame(width: wingL_eff, height: slotH)
						.contentShape(Rectangle())
						.zIndex(50)
						.background(Rectangle().fill(Color.black.opacity(0.001))) // reliable hit target
						.onDrag {
							deviceDragProvider(instance: instance, device: device)
						} preview: {
							devicePreviewView(device: device, layout: L, metrics: metrics)
						}
						.deviceMenu(
							onEdit: { startEditing(device) },
							onRemove: { removeInstance(instance, device: device) }
						)
						.zIndex(50)
				}
				
				// LEFT thin rail (only when partial is in the middle)
				if isPartial, wingL_eff == 0, L.leftRailPts > railEps {
					let w = L.leftRailPts
					ThinRailHandle(
						width: w,
						onDragProvider: { deviceDragProvider(instance: instance, device: device) },
						onRemove: { removeInstance(instance, device: device) },
						onEdit: { startEditing(device) },
						preview: { devicePreviewView(device: device, layout: L, metrics: metrics)}
					)
					.frame(width: w, height: slotH)
					.contentShape(Rectangle().inset(by: -((max(w, 9) - w) / 2)))
					.zIndex(60)
				}
			}
				.frame(width: L.totalWidthPts, height: slotH, alignment: .topLeading)
//				.clipped()
			
			// === RIGHT-side interactors as TRAILING OVERLAYS (no .offset) ===
			
			// RIGHT wing (partials only)
			let withRightWing = base.overlay(alignment: .trailing) {
				if isPartial, wingR_eff > 0 {
					WingPlate()
						.frame(width: wingR_eff, height: slotH)
						.contentShape(Rectangle())
						.background(Rectangle().fill(Color.black.opacity(0.001)))
						.onDrag { deviceDragProvider(instance: instance, device: device) } preview: {
							devicePreviewView(device: device, layout: L, metrics: metrics)
						}
						.deviceMenu(
							onEdit: { startEditing(device) },
							onRemove: { removeInstance(instance, device: device) }
						)
						.zIndex(50)
				}
			}
			
			// RIGHT thin rail (internal only; NEVER if a wing is present)
			let withRightThin = withRightWing.overlay(alignment: .trailing) {
				if isPartial, wingR_eff == 0, L.rightRailPts > railEps {
					let w = L.rightRailPts              // visual == actual seam width
					ThinRailHandle(
						width: w,
						onDragProvider: { deviceDragProvider(instance: instance, device: device) },
						onRemove: { removeInstance(instance, device: device) },
						onEdit: { startEditing(device) },
						preview: { devicePreviewView(device: device, layout: L, metrics: metrics) }
					)
					.frame(width: w, height: slotH)
					.contentShape(Rectangle().inset(by: -((max(w, 9) - w) / 2))) // bigger hit target only
					.zIndex(60)
				}
			}
			
			// FULL-WIDTH hover rails as edge overlays
			let withHoverEdges =
			withRightThin
			// LEFT edge (full-width only)
				.overlay(alignment: .leading) {
					if showHoverRails {
						let handleW = max(railWidth, 10)

						ZStack {
							// Always-present rail overlay (control visibility via opacity)
							RailOverlay(
								width: railWidth,
								onDragProvider: { deviceDragProvider(instance: instance, device: device) },
								onRemove: { removeInstance(instance, device: device) },
								onEdit: { startEditing(device) },
								preview: { devicePreviewView(device: device, layout: L, metrics: metrics)}
							)
							.frame(width: handleW, height: slotH)
							.opacity(hoverLeft ? 1 : 0)
							.allowsHitTesting(hoverLeft)
							.zIndex(60)
						}
						.frame(width: handleW, height: slotH)
						.contentShape(Rectangle())
						.onHover { hoverLeft = $0 }
						.onDrag {
							deviceDragProvider(instance: instance, device: device)
						} preview: {
							devicePreviewView(device: device, layout: L, metrics: metrics)
						}
						.deviceMenu(
							onEdit: { startEditing(device) },
							onRemove: { removeInstance(instance, device: device) }
						)
					}
				}
			// RIGHT edge (full-width only)
				.overlay(alignment: .trailing) {
					if showHoverRails {
						let handleW = max(railWidth, 10)

						ZStack {
							// Always-present rail overlay (control visibility via opacity)
							RailOverlay(
								width: railWidth,
								onDragProvider: { deviceDragProvider(instance: instance, device: device) },
								onRemove: { removeInstance(instance, device: device) },
								onEdit: { startEditing(device) },
								preview: { devicePreviewView(device: device, layout: L, metrics: metrics)}
							)
							.frame(width: handleW, height: slotH)
							.opacity(hoverRight ? 1 : 0)
							.allowsHitTesting(hoverRight)
							.zIndex(60)
						}
						.frame(width: handleW, height: slotH)
						.contentShape(Rectangle())
						.onHover { hoverRight = $0 }
						.onDrag {
							deviceDragProvider(instance: instance, device: device)
						} preview: {
							devicePreviewView(device: device, layout: L, metrics: metrics)
						}
						.deviceMenu(
							onEdit: { startEditing(device) },
							onRemove: { removeInstance(instance, device: device) }
						)
					}
				}
			
			let finalView = withHoverEdges
				.onPreferenceChange(HoverBubbleActiveKey.self) { hoverBubbleActive = $0 }
				.zIndex(hoverBubbleActive ? 9000 : 0)
			
			// MARK: per-device drop behavior (unchanged)
			let payload = DragContext.shared.currentPayload
			let enableDeviceDrop = (payload?.instanceId == instance.id)
			
			if enableDeviceDrop {
				return AnyView(
					finalView.onDrop(
						of: [UTType.deviceDragPayload],
						delegate: ChassisDropDelegate(
							fixedCell: (anchor.row, anchor.col),
							indexFor: nil,
							rowX0: 0,
							rowWidthPts: rowWidthPts,
							slots: $slots,
							hoveredIndex: $hoveredIndex,
							hoveredValid: $hoveredValid,
							hoveredRange: $hoveredRange,
							hoveredRows:  $hoveredRows,
							library: library,
							kind: .rack,
							session: sessionManager.currentSession,
							sessionManager: sessionManager,
							onCommit: { sessionManager.saveSessions() }
						)
					)
				)
			} else {
				return AnyView(finalView)
			}
		}
		
		// Fallback (should not be used when prelayout is provided)
		return AnyView(EmptyView())

	}
	
	// MARK: - Helpers (unchanged)
	private func spanRows(of device: Device) -> Int { max(1, device.rackUnits ?? 1) }
	private func spanCols(of device: Device) -> Int { max(1, device.rackWidth.rawValue) }
	
	// Binds an instance so writes fan out across the full span of this device.
	private func binding(for device: Device,
						 instance: DeviceInstance,
						 at anchor: (row: Int, col: Int)) -> Binding<DeviceInstance> {
		Binding<DeviceInstance>(
			get: { slots[anchor.row][anchor.col]! },
			set: { newVal in
				let rows = spanRows(of: device)
				let cols = spanCols(of: device)
				for r in anchor.row ..< min(anchor.row + rows, slots.count) {
					for c in anchor.col ..< min(anchor.col + cols, RackGrid.columnsPerRow) {
						slots[r][c] = newVal
					}
				}
			}
		)
	}
	
	private func anchorOfInstance(_ instance: DeviceInstance) -> (row: Int, col: Int)? {
		for r in slots.indices {
			for c in 0..<RackGrid.columnsPerRow {
				if slots[r][c]?.id == instance.id {
					let isTop = (r == 0) || (slots[r-1][c]?.id != instance.id)
					let isLeft = (c == 0) || (slots[r][c-1]?.id != instance.id)
					if isTop && isLeft { return (r,c) }
				}
			}
		}
		return nil
	}
	
	private func deviceDragProvider(instance: DeviceInstance, device: Device) -> NSItemProvider {
		let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
		DragContext.shared.beginDrag(payload: payload)
		let provider = NSItemProvider()
		provider.registerDataRepresentation(forTypeIdentifier: UTType.deviceDragPayload.identifier,
											visibility: .all) { completion in
			completion(try? JSONEncoder().encode(payload), nil)
			return nil
		}
		return provider
	}
	
	@ViewBuilder
	private func devicePreviewView(
		device: Device,
		layout: SlotPrelayout,
		metrics: FaceRenderMetrics
	) -> some View {
		DeviceDragPreview(device: device, layout: layout, metrics: metrics, zoom: canvasZoom, renderStyle: renderStyle)
	}
	
	private func removeInstance(_ instance: DeviceInstance, device: Device) {
		if let anchor = anchorOfInstance(instance) {
			for r in anchor.row ..< min(anchor.row + spanRows(of: device), slots.count) {
				for c in anchor.col ..< min(anchor.col + spanCols(of: device), RackGrid.columnsPerRow) {
					slots[r][c] = nil
				}
			}
		}
	}
	
	private func startEditing(_ device: Device) {
		editingDevice = device
		isPresentingEditor = true
	}
	
	// Small helper: make a rail hit area wide enough to grab, but visually stay inside the rail span
	@ViewBuilder
	func railHitArea(width: CGFloat, height: CGFloat) -> some View {
		// Minimum 9pt for usability, but don't visually spill: draw a subtle line inside
		let hitW = max(width, 9)
		ThinRailHitArea()
			.frame(width: hitW, height: height)
			.contentShape(Rectangle())
			.background(Color.clear)
			.allowsHitTesting(true)
			.zIndex(60) // above face/controls, below any ephemeral menus
	}
}

private struct DeviceContextMenuModifier: ViewModifier {
	let onEdit: () -> Void
	let onRemove: () -> Void
	
	func body(content: Content) -> some View {
		content.contextMenu {
			Button("Edit Device…") { onEdit() }
			Button("Remove from rack", role: .destructive) { onRemove() }
		}
	}
}

private extension View {
	@inline(__always)
	func deviceMenu(onEdit: @escaping () -> Void,
					onRemove: @escaping () -> Void) -> some View {
		self.modifier(DeviceContextMenuModifier(onEdit: onEdit, onRemove: onRemove))
	}
}


// MARK: - Rail overlays (non-generic; stable onDrag overload)
private struct RailOverlay: View {
	let width: CGFloat
	let onDragProvider: () -> NSItemProvider
	let onRemove: () -> Void
	let onEdit: () -> Void
	private let preview: AnyView
	
	init(
		width: CGFloat,
		onDragProvider: @escaping () -> NSItemProvider,
		onRemove: @escaping () -> Void,
		onEdit: @escaping () -> Void,
	@ViewBuilder preview: () -> some View = { EmptyView() }
	) {
		self.width = width
		self.onDragProvider = onDragProvider
		self.onRemove = onRemove
		self.onEdit = onEdit
		self.preview = AnyView(preview())
	}
	
	var body: some View {
		Rectangle()
			.fill(.ultraThinMaterial)
			.overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
			.frame(width: width)
			.opacity(0.9)
			.help("Drag to move this device. Right-click to edit or remove.")
			.overlay(RailScrewsV())
			.contentShape(Rectangle())
			.onDrag { onDragProvider() } preview: { preview }
			.deviceMenu(onEdit: onEdit, onRemove: onRemove)
	}
}

//private struct ThinRailOverlay: View {
//	let width: CGFloat
//	let onDragProvider: () -> NSItemProvider
//	let onRemove: () -> Void
//	let onEdit: () -> Void
//	private let preview: AnyView
//	
//	init(
//		width: CGFloat,
//		onDragProvider: @escaping () -> NSItemProvider,
//		onRemove: @escaping () -> Void,
//		onEdit: @escaping () -> Void,
//		@ViewBuilder preview: () -> some View = { EmptyView() }
//	) {
//		self.width = width
//		self.onDragProvider = onDragProvider
//		self.onRemove = onRemove
//		self.onEdit = onEdit
//		self.preview = AnyView(preview())
//	}
//	
//	var body: some View {
//		ZStack {
//			// Clear hit area (prevents any grey wash)
//			Color.clear
//			// Subtle handle line
//			Rectangle()
//				.stroke(Color.secondary.opacity(0.55), lineWidth: 1)
//				.padding(.vertical, 2)
//		}
//		.frame(width: width)
//		.contentShape(Rectangle())
//		.help("Drag to move this device. Right-click to edit or remove.")
//		.onDrag { onDragProvider() } preview: { preview }
//		.deviceMenu(onEdit: onEdit, onRemove: onRemove)
//		.accessibilityLabel("Device handle")
//	}
//}

private struct ThinRailHandle: View {
	let width: CGFloat
	let onDragProvider: () -> NSItemProvider
	let onRemove: () -> Void
	let onEdit: () -> Void
	private let preview: AnyView
	
	init(
		width: CGFloat,
		onDragProvider: @escaping () -> NSItemProvider,
		onRemove: @escaping () -> Void,
		onEdit: @escaping () -> Void,
		@ViewBuilder preview: () -> some View = { EmptyView() }
	) {
		self.width = width
		self.onDragProvider = onDragProvider
		self.onRemove = onRemove
		self.onEdit = onEdit
		self.preview = AnyView(preview())
	}
	
	var body: some View {
		// Use a nearly-invisible fill so hover/drag/right-click always register.
		Rectangle()
			.fill(Color.black.opacity(0.001))
			.frame(width: width)
			.contentShape(Rectangle())
			.help("Drag to move this device. Right-click to edit or remove.")
			.onDrag { onDragProvider() } preview: { preview }
			.deviceMenu(onEdit: onEdit, onRemove: onRemove)
			.accessibilityLabel("Device handle")
	}
}

private struct ThinRailHitArea: View {
	var body: some View {
		ZStack {
			// Transparent hit area
			Color.clear
			// Very subtle visual so users see the handle (adjust to taste)
			Rectangle()
				.stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 2]))
				.foregroundStyle(Color.secondary.opacity(0.6))
				.padding(.vertical, 2)
		}
	}
}

private struct RailScrewsV: View {
	var body: some View {
		VStack {
			Circle().fill(.secondary).frame(width: 4, height: 4)
			Spacer()
			Circle().fill(.secondary).frame(width: 4, height: 4)
		}
		.padding(.vertical, 6)
	}
}

private struct WingPlate: View {
	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 2)
				.fill(LinearGradient(
					colors: [
						Color.gray.opacity(0.85),
						Color.black.opacity(0.10)
					],
					startPoint: .topLeading, endPoint: .bottomTrailing
				))
				.overlay(
					RoundedRectangle(cornerRadius: 2)
						.stroke(Color.black.opacity(0.25), lineWidth: 0.5)
				)
			VStack {
				Circle().fill(Color.black.opacity(0.35)).frame(width: 3, height: 3)
				Spacer()
				Circle().fill(Color.black.opacity(0.35)).frame(width: 3, height: 3)
			}
			.padding(.vertical, 6)
		}
		.compositingGroup()
	}
}

// MARK: - Drag preview that matches exactly what you see in the slot
private struct DeviceDragPreview: View {
	let device: Device
	let layout: SlotPrelayout
	let metrics: FaceRenderMetrics
	let zoom: CGFloat
	let renderStyle: RenderStyle

	let railEps: CGFloat = 0.25

	var body: some View {
		let wingL_eff = (layout.leftWingPts  > 0 && layout.leftRailPts  <= railEps) ? layout.leftWingPts  : 0
		let wingR_eff = (layout.rightWingPts > 0 && layout.rightRailPts <= railEps) ? layout.rightWingPts : 0

		let scaledLayout = SlotPrelayout(
			faceWidthPts: layout.faceWidthPts * zoom,
			totalWidthPts: layout.totalWidthPts * zoom,
			leftWingPts: layout.leftWingPts * zoom,
			rightWingPts: layout.rightWingPts * zoom,
			leftRailPts: layout.leftRailPts * zoom,
			rightRailPts: layout.rightRailPts * zoom,
			heightPts: layout.heightPts * zoom,
			externalLeft: layout.externalLeft,
			externalRight: layout.externalRight
		)

		let scaledMetrics = FaceRenderMetrics(
			size: CGSize(width: metrics.size.width * zoom, height: metrics.size.height * zoom),
			vOffset: metrics.vOffset * zoom
		)

		let wingL_scaled = wingL_eff * zoom
		let wingR_scaled = wingR_eff * zoom

		ZStack(alignment: .topLeading) {
			// Left wing (if any)
			if wingL_scaled > 0 {
				WingPlate()
					.frame(width: scaledLayout.leftWingPts, height: scaledLayout.heightPts)
			}

			// Face image (same scaling + centering as runtime)
			Group {
				if renderStyle == .representative {
					// Use vector representation
					DeviceView(device: device, metrics: scaledMetrics)
						.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
				} else {
#if os(macOS)
					if let data = device.imageData, let nsimg = NSImage(data: data) {
						Image(nsImage: nsimg)
							.resizable()
							.interpolation(.high)
							.antialiased(true)
							.aspectRatio(nsimg.size, contentMode: .fit)
							.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
					} else {
						DeviceView(device: device, metrics: scaledMetrics)
							.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
					}
#else
					DeviceView(device: device, metrics: scaledMetrics)
						.frame(width: scaledMetrics.size.width, height: scaledMetrics.size.height)
#endif
				}
			}
			.offset(x: wingL_scaled + scaledLayout.leftRailPts, y: scaledMetrics.vOffset)

			// Right wing (if any)
			if wingR_scaled > 0 {
				WingPlate()
					.frame(width: wingR_scaled, height: scaledLayout.heightPts)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}
		}
		.frame(width: scaledLayout.totalWidthPts, height: scaledLayout.heightPts, alignment: .topLeading)
		.clipped()
		.shadow(radius: 8, y: 2)
	}
}
