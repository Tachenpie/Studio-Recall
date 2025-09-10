//
//  RegionHitLayer.swift
//  Studio Recall
//
//  Created by True Jackie on 9/8/25.
//

import SwiftUI

struct RegionHitLayer: View {
	// Normalized region rect [0…1] in canvas coords
	@Binding var rect: CGRect
	
	// Parent (viewport) geometry
	let parentSize: CGSize
	let canvasSize: CGSize
	let zoom: CGFloat
	let pan: CGSize
	var isPanMode: Bool = false
	
	// ---- Tuning -------------------------------------------------------------
	// Visual "screen-like" hit widths (we operate in local px; these feel similar)
	private let edgePx: CGFloat   = 14    // edges easier to catch
	private let cornerPx: CGFloat = 12    // corners a bit tighter than edge
	
	// Snap size (normalized) used on release
	private let snapStep: CGFloat = 0.005
	
	// Debug overlay to visualize bands & current handle
	private let debugUI: Bool = false
	// ------------------------------------------------------------------------
	
	// Drag state
	@State private var dragStartRect: CGRect = .zero
	@State private var dragStartPoint: CGPoint = .zero     // LOCAL to rect
	@State private var activeHandle: ResizeHandle? = nil
	@State private var mode: DragMode = .idle
	
	// Hover state for debug UI
#if os(macOS)
	@State private var hoverPointLocal: CGPoint? = nil
#endif
	
	var body: some View {
		// Region frame in parent space (matches your CanvasViewport math)
		let frame = regionFrameInParent(rect: rect)
		let regionSize = CGSize(width: frame.width, height: frame.height)
		
		ZStack(alignment: .topLeading) {
			// FULL-PARENT hit surface (no offset/position → no coord drift)
			Rectangle()
				.fill(Color.clear)
				.frame(width: parentSize.width, height: parentSize.height)
				.contentShape(Rectangle())
				.gesture(isPanMode ? nil : dragGesture(regionFrame: frame, localSize: regionSize))
				.allowsHitTesting(!isPanMode)
		}
	}
	
	// MARK: - Mapping (parent px delta → normalized delta)
	private func parentDeltaToNormalized(dx: CGFloat, dy: CGFloat) -> (CGFloat, CGFloat) {
		(dx / (canvasSize.width * zoom), dy / (canvasSize.height * zoom))
	}
	
	private func canvasOriginInParent() -> CGPoint {
		// Center the UNscaled canvas; scale is applied around .topLeading later.
		return CGPoint(
			x: (parentSize.width  - canvasSize.width)  * 0.5 + pan.width,
			y: (parentSize.height - canvasSize.height) * 0.5 + pan.height
		)
	}
	
	private func regionFrameInParent(rect r: CGRect) -> CGRect {
		let o = canvasOriginInParent()
		return CGRect(
			x: o.x + r.minX * canvasSize.width  * zoom,
			y: o.y + r.minY * canvasSize.height * zoom,
			width:  r.width  * canvasSize.width  * zoom,
			height: r.height * canvasSize.height * zoom
		)
	}
	
	/// Coerce a point that might be *local* or *parent* into rect-local space.
	/// If it's already local (inside [0,size]), return it. Otherwise subtract the
	/// rect's origin in parent space to convert to local.
	private func normalizeToLocal(_ p: CGPoint, frame: CGRect, size: CGSize) -> CGPoint {
		if p.x >= 0, p.y >= 0, p.x <= size.width, p.y <= size.height { return p }
		return CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)
	}
	
	// MARK: - Gestures (LOCAL to rect)
	private func dragGesture(regionFrame: CGRect, localSize: CGSize) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { g in
				guard !isPanMode else { return }
				
				if mode == .idle {
					// Must start inside the region; otherwise ignore this drag
					guard regionFrame.contains(g.startLocation) else { return }
					mode = .dragging
					dragStartRect  = rect
					
					// Convert start point from PARENT → RECT-LOCAL
					let startLocal = CGPoint(x: g.startLocation.x - regionFrame.minX,
											 y: g.startLocation.y - regionFrame.minY)
					dragStartPoint = startLocal
					activeHandle   = pickHandle(localPoint: startLocal, size: localSize)
					
#if os(macOS)
					if let h = activeHandle { cursor(for: h).push() } else { NSCursor.openHand.push() }
#endif
				}
				
				// Parent-space translation is exactly what DragGesture gives us here
				let dx = g.translation.width
				let dy = g.translation.height
				
				// Convert parent px → normalized deltas
				let (nx, ny) = parentDeltaToNormalized(dx: dx, dy: dy)
				
				var r = dragStartRect
				if let h = activeHandle {
					switch h {
						case .left:
							r.origin.x = r.origin.x + nx
							r.size.width  = dragStartRect.maxX - r.origin.x
						case .right:
							r.size.width  = dragStartRect.width + nx
						case .top:
							r.origin.y = r.origin.y + ny
							r.size.height = dragStartRect.maxY - r.origin.y
						case .bottom:
							r.size.height = dragStartRect.height + ny
						case .topLeft:
							r.origin.x = r.origin.x + nx
							r.size.width  = dragStartRect.maxX - r.origin.x
							r.origin.y = r.origin.y + ny
							r.size.height = dragStartRect.maxY - r.origin.y
						case .topRight:
							r.size.width  = dragStartRect.width + nx
							r.origin.y = r.origin.y + ny
							r.size.height = dragStartRect.maxY - r.origin.y
						case .bottomLeft:
							r.origin.x = r.origin.x + nx
							r.size.width  = dragStartRect.maxX - r.origin.x
							r.size.height = dragStartRect.height + ny
						case .bottomRight:
							r.size.width  = dragStartRect.width + nx
							r.size.height = dragStartRect.height + ny
					}
				} else {
					// MOVE
					r.origin.x = r.origin.x + nx
					r.origin.y = r.origin.y + ny
				}
				
				// live clamp (no snap while dragging)
				r.size.width  = max(0.001, r.size.width)
				r.size.height = max(0.001, r.size.height)
				r.origin.x = max(0, min(r.origin.x, 1 - r.size.width))
				r.origin.y = max(0, min(r.origin.y, 1 - r.size.height))
				
				rect = r
			}
			.onEnded { _ in
				// optional safety clamp; no rounding
				var r = rect
				r.size.width  = max(0.001, r.size.width)
				r.size.height = max(0.001, r.size.height)
				r.origin.x = max(0, min(r.origin.x, 1 - r.size.width))
				r.origin.y = max(0, min(r.origin.y, 1 - r.size.height))
				rect = r
				
				mode = .idle
				activeHandle = nil
#if os(macOS)
				NSCursor.pop()
#endif
			}

	}


	
	// MARK: - Hit testing (LOCAL to rect)
	/// Pick handle based on distance to edges/corners. `nil` == center/move.
	private func pickHandle(localPoint p: CGPoint, size s: CGSize) -> ResizeHandle? {
		// Must be inside to resize; outside -> MOVE (nil)
		guard p.x >= 0, p.y >= 0, p.x <= s.width, p.y <= s.height else { return nil }
		
		// Distances to edges
		let dL = p.x, dR = s.width - p.x, dT = p.y, dB = s.height - p.y
		
		// Cap bands for tiny rects so corners don't cover whole edge
		let e = min(edgePx,   min(s.width, s.height) * 0.50)
		let c = min(cornerPx, min(s.width, s.height) * 0.40)
		
		// Corners first
		if dL <= c && dT <= c { return .topLeft }
		if dR <= c && dT <= c { return .topRight }
		if dL <= c && dB <= c { return .bottomLeft }
		if dR <= c && dB <= c { return .bottomRight }
		
		// Then edges
		if dL <= e { return .left }
		if dR <= e { return .right }
		if dT <= e { return .top }
		if dB <= e { return .bottom }
		
		// Center -> move
		return nil
	}
	
	// MARK: - Types
	private enum DragMode { case idle, dragging }
	private enum ResizeHandle { case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
	
	// ---- Debug overlay ------------------------------------------------------
	private struct DebugOverlay: View {
		let regionSize: CGSize
		let edgePx: CGFloat
		let cornerPx: CGFloat
		let hoverPoint: CGPoint?
		let currentHandle: ResizeHandle?
		
		var body: some View {
			let w = regionSize.width, h = regionSize.height
			let e = min(edgePx,   min(w, h) * 0.50)
			let c = min(cornerPx, min(w, h) * 0.40)
			
			ZStack(alignment: .topLeading) {
				// Edges
				Rectangle().fill(Color.red.opacity(0.10))
					.frame(width: e, height: h)
				Rectangle().fill(Color.red.opacity(0.10))
					.frame(width: e, height: h)
					.position(x: w - e/2, y: h/2)
				Rectangle().fill(Color.green.opacity(0.10))
					.frame(width: w, height: e)
				Rectangle().fill(Color.green.opacity(0.10))
					.frame(width: w, height: e)
					.position(x: w/2, y: h - e/2)
				
				// Corners
				Rectangle().fill(Color.blue.opacity(0.15))
					.frame(width: c, height: c)
				Rectangle().fill(Color.blue.opacity(0.15))
					.frame(width: c, height: c)
					.position(x: w, y: 0)
				Rectangle().fill(Color.blue.opacity(0.15))
					.frame(width: c, height: c)
					.position(x: 0, y: h)
				Rectangle().fill(Color.blue.opacity(0.15))
					.frame(width: c, height: c)
					.position(x: w, y: h)
				
				// Hover marker + label
				if let p = hoverPoint {
					Circle().stroke(Color.yellow, lineWidth: 1)
						.frame(width: 6, height: 6)
						.position(x: p.x, y: p.y)
					Text(label(for: currentHandle))
						.font(.caption2.monospaced())
						.padding(4)
						.background(.ultraThinMaterial)
						.clipShape(RoundedRectangle(cornerRadius: 6))
						.position(x: min(max(40, p.x), w - 40), y: max(16, p.y + 16))
				}
			}
		}
		
		private func label(for h: ResizeHandle?) -> String {
			guard let h else { return "move" }
			switch h {
				case .left:        return "left"
				case .right:       return "right"
				case .top:         return "top"
				case .bottom:      return "bottom"
				case .topLeft:     return "topLeft"
				case .topRight:    return "topRight"
				case .bottomLeft:  return "bottomLeft"
				case .bottomRight: return "bottomRight"
			}
		}
	}
	
	private func cursor(for h: RegionHitLayer.ResizeHandle?) -> NSCursor {
		guard let h else { return .openHand }
		switch h {
			case .left, .right: return .resizeLeftRight
			case .top,  .bottom: return .resizeUpDown
			case .topLeft, .bottomRight: return .resizeDiagonalNWSE
			case .topRight, .bottomLeft: return .resizeDiagonalNESW
		}
	}
}

// MARK: - macOS cursors
#if os(macOS)
import AppKit

private func makeOutlinedCursor(symbolName: String,
								pointSize: CGFloat = 16,
								hot: NSPoint = NSPoint(x: 8, y: 8)) -> NSCursor {
	let size = NSSize(width: pointSize + 4, height: pointSize + 4)
	let image = NSImage(size: size, flipped: false) { rect in
		guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
			return false
		}
		let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
		guard let sized = base.withSymbolConfiguration(cfg) else { return false }
		let black = sized.withSymbolConfiguration(.init(hierarchicalColor: .black))
		let white = sized.withSymbolConfiguration(.init(hierarchicalColor: .white))
		black?.draw(in: rect.offsetBy(dx: 0.7, dy: -0.7))
		white?.draw(in: rect)
		return true
	}
	return NSCursor(image: image, hotSpot: hot)
}

private extension NSCursor {
	static let resizeDiagonalNWSE: NSCursor = makeOutlinedCursor(symbolName: "arrow.up.left.and.arrow.down.right")
	static let resizeDiagonalNESW: NSCursor = makeOutlinedCursor(symbolName: "arrow.up.right.and.arrow.down.left")
}

#endif
