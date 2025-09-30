//
//  CanvasViewport.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

private struct PanModeKey: EnvironmentKey {
	static let defaultValue: Bool = false
}
extension EnvironmentValues {
	var isPanMode: Bool {
		get { self[PanModeKey.self] }
		set { self[PanModeKey.self] = newValue }
	}
}

/// Owns the fitted canvas rect, zoom/pan transforms, and input→canvas coordinate math.
struct CanvasViewport<Content: View, Overlay: View>: View {
	@Environment(\.isPanMode) private var isPanMode
	
	let aspect: CGFloat                         // width / height
	@Binding var zoom: CGFloat
	@Binding var pan: CGSize
	@Binding var focusN: CGPoint?
	
	/// Render inner content sized to `canvasSize`
	let content: (_ canvasSize: CGSize) -> Content
	var overlayContent: ((CGSize /*parent*/, CGSize /*canvas*/, CGFloat /*zoom*/, CGSize /*pan*/) -> Overlay)? = nil
	
	/// Called when a String is dropped; gives point in *canvas* coordinates
	var onDropString: ((String, CGPoint, CGSize) -> Bool)? = nil
	
	/// Optional hover HUD
	var showHoverHUD: Bool = false
	
	// Internal
	@State private var panStart: CGSize = .zero
	@State private var zoomStart: CGFloat = 1.0
#if os(macOS)
	@State private var hoverPoint: CGPoint? = nil   // in parent coords
#endif
	
	var body: some View {
		GeometryReader { geo in
			let canvasSize = fittedSize(container: geo.size, aspect: aspect)
			// OUTER container (fills parent; attach pan/pinch/hover/drop here)
			ZStack {
				// INNER canvas (unscaled, centered box that we scale/offset)
				content(canvasSize)
					.frame(width: canvasSize.width, height: canvasSize.height)
					.scaleEffect(zoom, anchor: .center)
					.offset(pan)
					.contentShape(Rectangle()) // ensures whole canvas is hittable
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(Color.black.opacity(0.05))
			.cornerRadius(6)
			
			// Pan (only when hand tool is active)
			.gesture(
				DragGesture(minimumDistance: 2)
					.onChanged { g in
						guard isPanMode else { return }
						pan = CGSize(width: panStart.width + g.translation.width,
									 height: panStart.height + g.translation.height)
					}
					.onEnded { _ in if isPanMode { panStart = pan } }
			)
			// Pinch
			.simultaneousGesture(
				MagnificationGesture()
					.onChanged { m in zoom = (zoomStart * m).clamped(to: 0.5...8) }
					.onEnded   { _ in zoomStart = zoom }
			)
			
			// Hover (parent-space)
#if os(macOS)
			.onContinuousHover { phase in
				switch phase {
					case .active(let p): hoverPoint = p
					case .ended:         hoverPoint = nil
				}
			}
#endif
			
			// Drop (parent-space)
			.dropDestination(for: String.self) { items, loc in
				guard let s = items.first else { return false }
				let local = toCanvas(pointInParent: loc,
									 parentSize: geo.size,
									 canvasSize: canvasSize)
				return onDropString?(s, local, canvasSize) ?? false
			} isTargeted: { _ in }
			// Parent-space overlay: hit layer, guides, etc.
				.overlay(alignment: .topLeading) {
					if let overlayContent {
						// type-erase so we don't fight generic Overlay here
						AnyView(overlayContent(geo.size, canvasSize, zoom, pan))
					} else {
						AnyView(EmptyView())
					}
				}
			// HUD
#if os(macOS)
				.overlay(alignment: .topTrailing) {
					if showHoverHUD, let p = hoverPoint {
						let local = toCanvas(pointInParent: p,
											 parentSize: geo.size,
											 canvasSize: canvasSize)
						let nx = max(0, min(1, local.x / canvasSize.width))
						let ny = max(0, min(1, local.y / canvasSize.height))
						VStack(alignment: .trailing, spacing: 4) {
							Text(String(format: "x: %.3f  y: %.3f", nx, ny)).font(.caption.monospacedDigit())
							Text(String(format: "px: %.0f × %.0f", local.x, local.y))
								.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
						}
						.padding(6)
						.background(.ultraThinMaterial)
						.clipShape(RoundedRectangle(cornerRadius: 6))
						.padding(8)
						.allowsHitTesting(false)
					}
				}
#endif
				.onChange(of: zoom) { _, newZoom in
					guard let focusN else { return }
					let canvasPt = CGPoint(x: focusN.x * canvasSize.width,
										   y: focusN.y * canvasSize.height)
					// keep focus at parent center when zoom changes
					let parentCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
					// Solve for new pan so: toParent(canvasPt, ..., newZoom, panNew) == parentCenter
					let originX = (geo.size.width  - canvasSize.width)  * 0.5
					let originY = (geo.size.height - canvasSize.height) * 0.5
					let centerShiftX = canvasSize.width  * 0.5 * (1 - newZoom)
					let centerShiftY = canvasSize.height * 0.5 * (1 - newZoom)
					let panX = parentCenter.x - originX - centerShiftX - canvasPt.x * newZoom
					let panY = parentCenter.y - originY - centerShiftY - canvasPt.y * newZoom
					pan = CGSize(width: panX, height: panY)
					panStart = pan
				}
				.onChange(of: focusN) { _, _ in
					// Snap the newly requested focus to center at current zoom.
					guard let focusN else { return }
					let canvasPt = CGPoint(x: focusN.x * canvasSize.width,
										   y: focusN.y * canvasSize.height)
					let parentCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
					let originX = (geo.size.width  - canvasSize.width)  * 0.5
					let originY = (geo.size.height - canvasSize.height) * 0.5
					let centerShiftX = canvasSize.width  * 0.5 * (1 - zoom)
					let centerShiftY = canvasSize.height * 0.5 * (1 - zoom)
					let panX = parentCenter.x - originX - centerShiftX - canvasPt.x * zoom
					let panY = parentCenter.y - originY - centerShiftY - canvasPt.y * zoom
					pan = CGSize(width: panX, height: panY)
					panStart = pan
				}
		}
	}

	
	// MARK: math
	private func fittedSize(container: CGSize, aspect: CGFloat) -> CGSize {
		let containerRatio = container.width / container.height
		if containerRatio > aspect {
			let h = container.height
			return .init(width: h * aspect, height: h)
		} else {
			let w = container.width
			return .init(width: w, height: w / aspect)
		}
	}
	
	@inline(__always)
	func toParent(pointInCanvas c: CGPoint,
				  parentSize: CGSize, canvasSize: CGSize,
				  zoom: CGFloat, pan: CGSize) -> CGPoint {
		let originX = (parentSize.width  - canvasSize.width)  * 0.5
		let originY = (parentSize.height - canvasSize.height) * 0.5
		let centerShiftX = canvasSize.width  * 0.5 * (1 - zoom)
		let centerShiftY = canvasSize.height * 0.5 * (1 - zoom)
		let x = originX + centerShiftX + pan.width  + c.x * zoom
		let y = originY + centerShiftY + pan.height + c.y * zoom
		return CGPoint(x: x, y: y)
	}
	
	/// Convert a point (in the parent view that contains the centered, zoomed canvas)
	/// into *canvas-local* coordinates, undoing centering, pan, and zoom.
	private func toCanvas(pointInParent p: CGPoint,
						  parentSize: CGSize,
						  canvasSize: CGSize) -> CGPoint {
		// Center of the unscaled canvas in the parent
		let originX = (parentSize.width  - canvasSize.width)  * 0.5
		let originY = (parentSize.height - canvasSize.height) * 0.5
		
		// Extra top-left shift when scaling around .center
		let centerShiftX = canvasSize.width  * 0.5 * (1 - zoom)
		let centerShiftY = canvasSize.height * 0.5 * (1 - zoom)
		
		// Undo centering, center shift, then pan, then zoom
		let x = (p.x - originX - centerShiftX - pan.width)  / zoom
		let y = (p.y - originY - centerShiftY - pan.height) / zoom
		
		return CGPoint(x: x, y: y).clamped(to: CGRect(origin: .zero, size: canvasSize))
	}
}

private extension CGPoint {
	func clamped(to rect: CGRect) -> CGPoint {
		CGPoint(x: max(rect.minX, min(rect.maxX, x)),
				y: max(rect.minY, min(rect.maxY, y)))
	}
}
