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
	let shape: ImageRegionShape
	let controlType: ControlType
	let regionIndex: Int
	let regions: [ImageRegion]
	var isEnabled: Bool = true
	
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
//			Rectangle()
//				.fill(Color.clear)
//				.frame(width: parentSize.width, height: parentSize.height)
//				.contentShape(Rectangle())
//				.gesture(isPanMode || !isEnabled ? nil : dragGesture(regionFrame: frame, localSize: regionSize))
//				.allowsHitTesting(isEnabled && !isPanMode)
			if isConcentricOuterRegion {
				let outer = regionFrameInParent(rect: rect)
				let inner = regionFrameInParent(rect: regions[1].rect)
				DonutShape(outerRect: outer, innerRect: inner)
					.fill(Color.clear, style: FillStyle(eoFill: true))
					.contentShape(DonutShape(outerRect: outer, innerRect: inner))
					.gesture(isPanMode || !isEnabled ? nil : dragGesture(regionFrame: outer, localSize: regionSize))
					.allowsHitTesting(isEnabled && !isPanMode)
			} else {
				RegionClipShape(shape: shape)
					.fill(Color.clear)
					.frame(width: parentSize.width, height: parentSize.height)
					.contentShape(RegionClipShape(shape: shape))   // ✅ hit testing matches shape
					.gesture(isPanMode || !isEnabled ? nil : dragGesture(regionFrame: frame, localSize: regionSize))
					.allowsHitTesting(isEnabled && !isPanMode)
			}
		}
	}
	
	// MARK: - Mapping (parent px delta → normalized delta)
	private var isConcentricOuterRegion: Bool {
		controlType == .concentricKnob && regionIndex == 0 && regions.count > 1
	}
	
	private var innerRect: CGRect? {
		guard isConcentricOuterRegion else { return nil }
		return regions[1].rect.denormalized(to: canvasSize, zoom: zoom, pan: pan, parentSize: parentSize)
	}
	
	private func parentDeltaToNormalized(dx: CGFloat, dy: CGFloat) -> (CGFloat, CGFloat) {
//		(dx / (canvasSize.width * zoom), dy / (canvasSize.height * zoom))
		(dx / canvasSize.width, dy / canvasSize.height)
	}
	
	private func canvasOriginInParent() -> CGPoint {
		// Unscaled canvas centered in parent, then scaled around center → add centerShift
		let centerShiftX = canvasSize.width  * 0.5 * (1 - zoom)
		let centerShiftY = canvasSize.height * 0.5 * (1 - zoom)
		return CGPoint(
			x: (parentSize.width  - canvasSize.width)  * 0.5 + pan.width  + centerShiftX,
			y: (parentSize.height - canvasSize.height) * 0.5 + pan.height + centerShiftY
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
				
				// Begin drag (allow just outside the border)
				if mode == .idle {
					let startOK = regionFrame.insetBy(dx: -edgePx, dy: -edgePx).contains(g.startLocation)
					guard startOK else { return }
					mode = .dragging
					dragStartRect = rect
					
					// Parent → rect-local
					let startLocal = CGPoint(x: g.startLocation.x - regionFrame.minX,
											 y: g.startLocation.y - regionFrame.minY)
					dragStartPoint = startLocal
					activeHandle   = pickHandle(localPoint: startLocal, size: localSize)
					
#if os(macOS)
					if let h = activeHandle { cursor(for: h).push() } else { NSCursor.openHand.push() }
#endif
				}
				
				// Parent px deltas → canvas-normalized deltas
				let resizeScale = 1.0 / zoom
//				let (nx, ny) = parentDeltaToNormalized(dx: g.translation.width, dy: g.translation.height)
				let (nx, ny) = parentDeltaToNormalized(
					dx: g.translation.width * resizeScale,
					dy: g.translation.height * resizeScale
				)
				var r = dragStartRect
				
				guard let h = activeHandle else {
					// MOVE
					r.origin.x += nx
					r.origin.y += ny
					// live clamp
					r.origin.x = max(0, min(r.origin.x, 1 - r.size.width))
					r.origin.y = max(0, min(r.origin.y, 1 - r.size.height))
					rect = r
					return
				}
				
				if shape == .circle {
					// --- Circle behavior ---
					let s = dragStartRect
					let minS: CGFloat = 0.01
					
					// Edges: single-axis resize; keep the other axis fixed.
					switch h {
						case .top:
							let newT = (s.minY + ny).clamped(to: 0...(s.maxY - minS))
							r.origin.y    = newT
							r.size.height = s.maxY - newT
							r.origin.x    = s.minX       // keep width unchanged
							r.size.width  = s.width
							
						case .bottom:
							let newB = (s.maxY + ny).clamped(to: (s.minY + minS)...1)
							r.size.height = newB - s.minY
							r.origin.x    = s.minX
							r.size.width  = s.width
							
						case .left:
							let newL = (s.minX + nx).clamped(to: 0...(s.maxX - minS))
							r.origin.x   = newL
							r.size.width = s.maxX - newL
							r.origin.y   = s.minY       // keep height unchanged
							r.size.height = s.height
							
						case .right:
							let newR = (s.maxX + nx).clamped(to: (s.minX + minS)...1)
							r.size.width = newR - s.minX
							r.origin.y   = s.minY
							r.size.height = s.height
							
							// Corners: uniform (square) resize, anchored at opposite corner.
						case .topLeft:
							let newL = (s.minX + nx).clamped(to: 0...(s.maxX - minS))
							let newT = (s.minY + ny).clamped(to: 0...(s.maxY - minS))
							r.origin.x   = newL
							r.size.width = s.maxX - newL
							r.origin.y   = newT
							r.size.height = s.maxY - newT
							
						case .topRight:
							let newR = (s.maxX + nx).clamped(to: (s.minX + minS)...1)
							let newT = (s.minY + ny).clamped(to: 0...(s.maxY - minS))
							r.size.width  = newR - s.minX
							r.origin.y    = newT
							r.size.height = s.maxY - newT
							
						case .bottomLeft:
							let newL = (s.minX + nx).clamped(to: 0...(s.maxX - minS))
							let newB = (s.maxY + ny).clamped(to: (s.minY + minS)...1)
							r.origin.x   = newL
							r.size.width = s.maxX - newL
							r.size.height = newB - s.minY
							
						case .bottomRight:
							let newR = (s.maxX + nx).clamped(to: (s.minX + minS)...1)
							let newB = (s.maxY + ny).clamped(to: (s.minY + minS)...1)
							r.size.width  = newR - s.minX
							r.size.height = newB - s.minY
					}
					
				} else {
						// ---- Rectangular anchored resizing (linear, no drift) ----
						let minW: CGFloat = 0.01
						let minH: CGFloat = 0.01
						switch h {
							case .left:
								let newL = (dragStartRect.minX + nx).clamped(to: 0...(dragStartRect.maxX - minW))
								r.origin.x   = newL
								r.size.width = dragStartRect.maxX - newL
								
							case .right:
								let newR = (dragStartRect.maxX + nx).clamped(to: (dragStartRect.minX + minW)...1)
								r.size.width = newR - dragStartRect.minX
								
							case .top:
								let newT = (dragStartRect.minY + ny).clamped(to: 0...(dragStartRect.maxY - minH))
								r.origin.y    = newT
								r.size.height = dragStartRect.maxY - newT
								
							case .bottom:
								let newB = (dragStartRect.maxY + ny).clamped(to: (dragStartRect.minY + minH)...1)
								r.size.height = newB - dragStartRect.minY
								
							case .topLeft:
								let newL = (dragStartRect.minX + nx).clamped(to: 0...(dragStartRect.maxX - minW))
								let newT = (dragStartRect.minY + ny).clamped(to: 0...(dragStartRect.maxY - minH))
								r.origin.x   = newL
								r.size.width = dragStartRect.maxX - newL
								r.origin.y   = newT
								r.size.height = dragStartRect.maxY - newT
								
							case .topRight:
								let newR = (dragStartRect.maxX + nx).clamped(to: (dragStartRect.minX + minW)...1)
								let newT = (dragStartRect.minY + ny).clamped(to: 0...(dragStartRect.maxY - minH))
								r.size.width  = newR - dragStartRect.minX
								r.origin.y    = newT
								r.size.height = dragStartRect.maxY - newT
								
							case .bottomLeft:
								let newL = (dragStartRect.minX + nx).clamped(to: 0...(dragStartRect.maxX - minW))
								let newB = (dragStartRect.maxY + ny).clamped(to: (dragStartRect.minY + minH)...1)
								r.origin.x   = newL
								r.size.width = dragStartRect.maxX - newL
								r.size.height = newB - dragStartRect.minY
								
							case .bottomRight:
								let newR = (dragStartRect.maxX + nx).clamped(to: (dragStartRect.minX + minW)...1)
								let newB = (dragStartRect.maxY + ny).clamped(to: (dragStartRect.minY + minH)...1)
								r.size.width  = newR - dragStartRect.minX
								r.size.height = newB - dragStartRect.minY
						}
					}
				// Live clamp to 0…1 (safety)
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
	private func pickHandle(localPoint p: CGPoint, size s: CGSize) -> ResizeHandle? {
		// Distances to each edge (allow outside; negative means outside)
		let dL = p.x - 0
		let dR = s.width - p.x
		let dT = p.y - 0
		let dB = s.height - p.y
		
		// Use absolute distance to the edge lines
		let aL = abs(dL), aR = abs(dR), aT = abs(dT), aB = abs(dB)
		
		// Corner/edge bands (cap for tiny rects so corners don’t cover everything)
		let e = min(edgePx,   min(s.width, s.height) * 0.50)
		let c = min(cornerPx, min(s.width, s.height) * 0.40)
		
		// Are we near each edge?
		let nearL = aL <= e, nearR = aR <= e, nearT = aT <= e, nearB = aB <= e
		
		// Corner priority (within corner band of both adjoining edges)
		if nearL && nearT && aL <= c && aT <= c { return .topLeft }
		if nearR && nearT && aR <= c && aT <= c { return .topRight }
		if nearL && nearB && aL <= c && aB <= c { return .bottomLeft }
		if nearR && nearB && aR <= c && aB <= c { return .bottomRight }
		
		// Then edges
		if nearL { return .left }
		if nearR { return .right }
		if nearT { return .top }
		if nearB { return .bottom }
		
		// Otherwise: MOVE only if we started inside; if we started outside beyond the band, ignore
		if p.x >= 0, p.y >= 0, p.x <= s.width, p.y <= s.height { return nil }
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
	
	private func resizeRect(from h: ResizeHandle, start s: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
		var r = s
		let minW: CGFloat = 0.01
		let minH: CGFloat = 0.01
		switch h {
			case .left:
				let newL = (s.minX + dx).clamped(to: 0...(s.maxX - minW))
				r.origin.x   = newL
				r.size.width = s.maxX - newL
			case .right:
				let newR = (s.maxX + dx).clamped(to: (s.minX + minW)...1)
				r.size.width = newR - s.minX
			case .top:
				let newT = (s.minY + dy).clamped(to: 0...(s.maxY - minH))
				r.origin.y    = newT
				r.size.height = s.maxY - newT
			case .bottom:
				let newB = (s.maxY + dy).clamped(to: (s.minY + minH)...1)
				r.size.height = newB - s.minY
			case .topLeft:
				r = resizeRect(from: .left, start: r, dx: dx, dy: dy)
				r = resizeRect(from: .top,  start: r, dx: dx, dy: dy)
			case .topRight:
				r = resizeRect(from: .right, start: r, dx: dx, dy: dy)
				r = resizeRect(from: .top,   start: r, dx: dx, dy: dy)
			case .bottomLeft:
				r = resizeRect(from: .left,  start: r, dx: dx, dy: dy)
				r = resizeRect(from: .bottom,start: r, dx: dx, dy: dy)
			case .bottomRight:
				r = resizeRect(from: .right, start: r, dx: dx, dy: dy)
				r = resizeRect(from: .bottom,start: r, dx: dx, dy: dy)
		}
		return r
	}
	
	private func resizeCircle(from h: ResizeHandle, start s: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
		// Build a square anchored at the opposite edge/corner.
		let minS: CGFloat = max(0.01, min(s.width, s.height) * 0.2) // sensible floor
		
		func clampSquare(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> CGRect {
			let size = max(minS, size)
			var x0 = x, y0 = y
			x0 = min(max(x0, 0), 1 - size)
			y0 = min(max(y0, 0), 1 - size)
			return CGRect(x: x0, y: y0, width: size, height: size)
		}
		
		switch h {
				// EDGES: keep the opposite edge and center along the perpendicular axis
			case .left:   // anchor at right-edge & centerY
				let xR = s.maxX, cY = s.midY
				let size = max(minS, xR - (s.minX + dx))
				return clampSquare(xR - size, cY - size/2, size)
			case .right:  // anchor at left-edge & centerY
				let xL = s.minX, cY = s.midY
				let size = max(minS, (s.maxX + dx) - xL)
				return clampSquare(xL, cY - size/2, size)
			case .top:    // anchor at bottom-edge & centerX
				let yB = s.maxY, cX = s.midX
				let size = max(minS, yB - (s.minY + dy))
				return clampSquare(cX - size/2, yB - size, size)
			case .bottom: // anchor at top-edge & centerX
				let yT = s.minY, cX = s.midX
				let size = max(minS, (s.maxY + dy) - yT)
				return clampSquare(cX - size/2, yT, size)
				
				// CORNERS: anchor at opposite corner; size from max of dx,dy
			case .topLeft:
				let xB = s.maxX, yB = s.maxY
				let nx = xB - (s.minX + dx)
				let ny = yB - (s.minY + dy)
				let size = max(minS, max(nx, ny))
				return clampSquare(xB - size, yB - size, size)
			case .topRight:
				let xL = s.minX, yB = s.maxY
				let nx = (s.maxX + dx) - xL
				let ny = yB - (s.minY + dy)
				let size = max(minS, max(nx, ny))
				return clampSquare(xL, yB - size, size)
			case .bottomLeft:
				let xR = s.maxX, yT = s.minY
				let nx = xR - (s.minX + dx)
				let ny = (s.maxY + dy) - yT
				let size = max(minS, max(nx, ny))
				return clampSquare(xR - size, yT, size)
			case .bottomRight:
				let xL = s.minX, yT = s.minY
				let nx = (s.maxX + dx) - xL
				let ny = (s.maxY + dy) - yT
				let size = max(minS, max(nx, ny))
				return clampSquare(xL, yT, size)
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

// MARK: - CGRect helpers
extension CGRect {
	func denormalized(to canvasSize: CGSize, zoom: CGFloat, pan: CGSize, parentSize: CGSize) -> CGRect {
		let origin = CGPoint(
			x: origin.x * canvasSize.width * zoom + (parentSize.width - canvasSize.width * zoom) * 0.5 + pan.width,
			y: origin.y * canvasSize.height * zoom + (parentSize.height - canvasSize.height * zoom) * 0.5 + pan.height
		)
		return CGRect(
			x: origin.x,
			y: origin.y,
			width: size.width * canvasSize.width * zoom,
			height: size.height * canvasSize.height * zoom
		)
	}
}
