//
//  ShapeInstanceHitLayer.swift
//  Studio Recall
//
//  Hit testing and interaction layer for individual shape instances
//

import SwiftUI

struct ShapeInstanceHitLayer: View {
	@Binding var shapeInstance: ShapeInstance
	let regionRect: CGRect  // normalized (0-1) canvas coordinates
	let parentSize: CGSize
	let canvasSize: CGSize
	let zoom: CGFloat
	let pan: CGSize
	var isPanMode: Bool = false
	var isEnabled: Bool = true
	var onSelect: (() -> Void)? = nil
	
	// Drag state
	@State private var dragStartInstance: ShapeInstance? = nil
	@State private var activeHandle: Handle? = nil
	@State private var mode: DragMode = .idle
	
	// Tuning
	private let edgePx: CGFloat = 14
	private let cornerPx: CGFloat = 12
	private let rotHandleOffsetPx: CGFloat = 20
	
	var body: some View {
		let instanceFrame = calculateInstanceFrameInParent()
		let localSize = instanceFrame.size
		
		ZStack(alignment: .topLeading) {
			// Main shape hit area
			let shapePath = createShapePath(in: CGRect(origin: .zero, size: localSize))
			
			Path { _ in shapePath }
				.fill(Color.clear)
				.frame(width: localSize.width, height: localSize.height)
				.contentShape(Path { _ in shapePath })
				.rotationEffect(.degrees(shapeInstance.rotation), anchor: .center)
				.position(x: instanceFrame.midX, y: instanceFrame.midY)
				.gesture(isPanMode ? nil : dragGesture(instanceFrame: instanceFrame, localSize: localSize))
			
			// Rotation handle (only for selected shapes)
			if isEnabled {
				let rotHandleY = instanceFrame.minY - rotHandleOffsetPx / zoom
				Circle()
					.fill(Color.clear)
					.frame(width: 16.0 / zoom, height: 16.0 / zoom)
					.contentShape(Circle())
					.position(x: instanceFrame.midX, y: rotHandleY)
					.gesture(isPanMode ? nil : rotationGesture(instanceFrame: instanceFrame))
			}
		}
		.allowsHitTesting(!isPanMode)
	}
	
	// MARK: - Gestures
	
	private func dragGesture(instanceFrame: CGRect, localSize: CGSize) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { gesture in
				if mode == .idle {
					// Select this shape instance
					onSelect?()
					
					// Start drag
					mode = .dragging
					dragStartInstance = shapeInstance
					
					// Determine which handle was grabbed
					let startLocal = CGPoint(
						x: gesture.startLocation.x - instanceFrame.minX,
						y: gesture.startLocation.y - instanceFrame.minY
					)
					activeHandle = pickHandle(localPoint: startLocal, size: localSize)
					
#if os(macOS)
					if let h = activeHandle {
						cursor(for: h).push()
					} else {
						NSCursor.openHand.push()
					}
#endif
				}
				
				guard let startInstance = dragStartInstance else { return }
				
				// Only allow editing if shape is enabled/selected
				guard isEnabled else { return }
				
				// Calculate delta in normalized region coordinates
				let dx = gesture.translation.width / zoom / (regionRect.width * canvasSize.width)
				let dy = gesture.translation.height / zoom / (regionRect.height * canvasSize.height)
				
				if let handle = activeHandle {
					// Resize
					applyResize(handle: handle, dx: dx, dy: dy, startInstance: startInstance)
				} else {
					// Move
					shapeInstance.position = CGPoint(
						x: (startInstance.position.x + dx).clamped(to: 0...1),
						y: (startInstance.position.y + dy).clamped(to: 0...1)
					)
				}
			}
			.onEnded { _ in
				mode = .idle
				activeHandle = nil
				dragStartInstance = nil
#if os(macOS)
				NSCursor.pop()
#endif
			}
	}
	
	private func rotationGesture(instanceFrame: CGRect) -> some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { gesture in
				if mode == .idle {
					// Select on start
					onSelect?()
					
					mode = .rotating
					dragStartInstance = shapeInstance
#if os(macOS)
					NSCursor.crosshair.push()
#endif
				}
				
				// Only allow rotation if shape is enabled/selected
				guard isEnabled else { return }
				
				// Calculate angle from shape center to current drag point
				let center = CGPoint(x: instanceFrame.midX, y: instanceFrame.midY)
				let currentPoint = gesture.location
				
				let dx = currentPoint.x - center.x
				let dy = currentPoint.y - center.y
				let angle = atan2(dy, dx) * 180 / .pi
				
				// Adjust for 0° pointing up (not right)
				shapeInstance.rotation = (angle + 90).truncatingRemainder(dividingBy: 360)
				if shapeInstance.rotation < 0 {
					shapeInstance.rotation += 360
				}
			}
			.onEnded { _ in
				mode = .idle
				dragStartInstance = nil
#if os(macOS)
				NSCursor.pop()
#endif
			}
	}
	
	// MARK: - Resize Logic
	
	private func applyResize(handle: Handle, dx: CGFloat, dy: CGFloat, startInstance: ShapeInstance) {
		let minSize: CGFloat = 0.05
		
		var newSize = startInstance.size
		var newPos = startInstance.position
		
		switch handle {
		case .topLeft:
			// Resize from top-left, anchor at bottom-right
			newSize.width = max(minSize, startInstance.size.width - dx)
			newSize.height = max(minSize, startInstance.size.height - dy)
			newPos.x = startInstance.position.x + (startInstance.size.width - newSize.width) / 2
			newPos.y = startInstance.position.y + (startInstance.size.height - newSize.height) / 2
			
		case .topRight:
			// Resize from top-right, anchor at bottom-left
			newSize.width = max(minSize, startInstance.size.width + dx)
			newSize.height = max(minSize, startInstance.size.height - dy)
			newPos.x = startInstance.position.x + (newSize.width - startInstance.size.width) / 2
			newPos.y = startInstance.position.y + (startInstance.size.height - newSize.height) / 2
			
		case .bottomLeft:
			// Resize from bottom-left, anchor at top-right
			newSize.width = max(minSize, startInstance.size.width - dx)
			newSize.height = max(minSize, startInstance.size.height + dy)
			newPos.x = startInstance.position.x + (startInstance.size.width - newSize.width) / 2
			newPos.y = startInstance.position.y + (newSize.height - startInstance.size.height) / 2
			
		case .bottomRight:
			// Resize from bottom-right, anchor at top-left
			newSize.width = max(minSize, startInstance.size.width + dx)
			newSize.height = max(minSize, startInstance.size.height + dy)
			newPos.x = startInstance.position.x + (newSize.width - startInstance.size.width) / 2
			newPos.y = startInstance.position.y + (newSize.height - startInstance.size.height) / 2
			
		case .top:
			// Resize height from top
			newSize.height = max(minSize, startInstance.size.height - dy)
			newPos.y = startInstance.position.y + (startInstance.size.height - newSize.height) / 2
			
		case .bottom:
			// Resize height from bottom
			newSize.height = max(minSize, startInstance.size.height + dy)
			newPos.y = startInstance.position.y + (newSize.height - startInstance.size.height) / 2
			
		case .left:
			// Resize width from left
			newSize.width = max(minSize, startInstance.size.width - dx)
			newPos.x = startInstance.position.x + (startInstance.size.width - newSize.width) / 2
			
		case .right:
			// Resize width from right
			newSize.width = max(minSize, startInstance.size.width + dx)
			newPos.x = startInstance.position.x + (newSize.width - startInstance.size.width) / 2
		}
		
		// Clamp to valid range
		newPos.x = newPos.x.clamped(to: 0...1)
		newPos.y = newPos.y.clamped(to: 0...1)
		newSize.width = newSize.width.clamped(to: minSize...1.0)
		newSize.height = newSize.height.clamped(to: minSize...1.0)
		
		shapeInstance.size = newSize
		shapeInstance.position = newPos
	}
	
	// MARK: - Hit Testing
	
	private func pickHandle(localPoint p: CGPoint, size s: CGSize) -> Handle? {
		// Calculate distances to edges
		let dL = p.x
		let dR = s.width - p.x
		let dT = p.y
		let dB = s.height - p.y
		
		let aL = abs(dL), aR = abs(dR), aT = abs(dT), aB = abs(dB)
		
		let e = min(edgePx / zoom, min(s.width, s.height) * 0.50)
		let c = min(cornerPx / zoom, min(s.width, s.height) * 0.40)
		
		let nearL = aL <= e, nearR = aR <= e, nearT = aT <= e, nearB = aB <= e
		
		// Corners have priority
		if nearL && nearT && aL <= c && aT <= c { return .topLeft }
		if nearR && nearT && aR <= c && aT <= c { return .topRight }
		if nearL && nearB && aL <= c && aB <= c { return .bottomLeft }
		if nearR && nearB && aR <= c && aB <= c { return .bottomRight }
		
		// Edges (only for non-circles)
		if shapeInstance.shape != .circle {
			if nearL { return .left }
			if nearR { return .right }
			if nearT { return .top }
			if nearB { return .bottom }
		}
		
		// Inside = move
		if p.x >= 0 && p.y >= 0 && p.x <= s.width && p.y <= s.height {
			return nil
		}
		
		return nil
	}
	
	// MARK: - Helpers
	
	private func calculateInstanceFrameInParent() -> CGRect {
		// Region rect in canvas pixels
		let regionPixels = CGRect(
			x: regionRect.origin.x * canvasSize.width,
			y: regionRect.origin.y * canvasSize.height,
			width: regionRect.size.width * canvasSize.width,
			height: regionRect.size.height * canvasSize.height
		)
		
		// Shape instance center in canvas pixels
		let centerX = regionPixels.minX + shapeInstance.position.x * regionPixels.width
		let centerY = regionPixels.minY + shapeInstance.position.y * regionPixels.height
		
		// Shape size in canvas pixels
		let w = shapeInstance.size.width * regionPixels.width
		let h = shapeInstance.size.height * regionPixels.height
		
		// Convert to parent space (apply zoom and pan)
		let canvasOrigin = canvasOriginInParent()
		
		return CGRect(
			x: canvasOrigin.x + (centerX - w/2) * zoom,
			y: canvasOrigin.y + (centerY - h/2) * zoom,
			width: w * zoom,
			height: h * zoom
		)
	}
	
	private func canvasOriginInParent() -> CGPoint {
		let centerShiftX = canvasSize.width * 0.5 * (1 - zoom)
		let centerShiftY = canvasSize.height * 0.5 * (1 - zoom)
		return CGPoint(
			x: (parentSize.width - canvasSize.width) * 0.5 + pan.width + centerShiftX,
			y: (parentSize.height - canvasSize.height) * 0.5 + pan.height + centerShiftY
		)
	}
	
	private func createShapePath(in rect: CGRect) -> CGPath {
		let path = CGMutablePath()
		
		switch shapeInstance.shape {
		case .circle:
			path.addEllipse(in: rect)
			
		case .rectangle:
			path.addRect(rect)
			
		case .triangle:
			let topPoint = CGPoint(x: rect.midX, y: rect.minY)
			let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
			let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
			
			path.move(to: topPoint)
			path.addLine(to: bottomRight)
			path.addLine(to: bottomLeft)
			path.closeSubpath()
			
		default:
			path.addRect(rect)
		}
		
		return path
	}
	
	private func cursor(for h: Handle) -> NSCursor {
#if os(macOS)
		switch h {
		case .left, .right: return .resizeLeftRight
		case .top, .bottom: return .resizeUpDown
		case .topLeft, .bottomRight: return .resizeDiagonalNWSE
		case .topRight, .bottomLeft: return .resizeDiagonalNESW
		}
#else
		return NSCursor.arrow
#endif
	}
	
	// MARK: - Types
	
	private enum DragMode { case idle, dragging, rotating }
	
	private enum Handle {
		case topLeft, topRight, bottomLeft, bottomRight
		case top, bottom, left, right
	}
}

// MARK: - macOS cursors

#if os(macOS)
import AppKit

extension NSCursor {
	static var resizeDiagonalNWSE: NSCursor {
		makeOutlinedCursor(symbolName: "arrow.up.left.and.arrow.down.right")
	}
	
	static var resizeDiagonalNESW: NSCursor {
		makeOutlinedCursor(symbolName: "arrow.up.right.and.arrow.down.left")
	}
	
	private static func makeOutlinedCursor(symbolName: String, pointSize: CGFloat = 16, hot: NSPoint = NSPoint(x: 8, y: 8)) -> NSCursor {
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
}
#endif
