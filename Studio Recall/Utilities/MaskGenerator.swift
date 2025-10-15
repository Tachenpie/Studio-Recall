//
//  MaskGenerator.swift
//  Studio Recall
//
//  **DEPRECATED**: This utility is kept only for backward compatibility
//  with existing sessions that use alpha masks.
//
//  For new development, use ShapeInstance with automatic color fill matching.
//  See IMPLEMENTATION_SimplifiedShapes.md for details.
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// **DEPRECATED**: Use ShapeInstance with color fill matching instead
struct MaskGenerator {
	/// **DEPRECATED**: Generate a mask image from parameters (kept for backward compatibility)
	/// Returns PNG data (white = shows pointer/opaque, black = shows background/transparent)
	@available(*, deprecated, message: "Use ShapeInstance with automatic color fill matching instead")
	static func generateMask(params: MaskParameters, size: CGSize) -> Data? {
		let width = Int(size.width)
		let height = Int(size.height)

		guard width > 0, height > 0 else { return nil }

		// Create a grayscale context (mask is black and white)
		let colorSpace = CGColorSpaceCreateDeviceGray()
		guard let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else { return nil }

		// Fill with black (transparent, shows background)
		context.setFillColor(gray: 0.0, alpha: 1.0)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))

		// Draw pointer in white (opaque, shows the pointer)
		context.setFillColor(gray: 1.0, alpha: 1.0)

		let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
		let maxRadius = min(CGFloat(width), CGFloat(height)) / 2

		switch params.style {
		case .line:
			drawLine(context: context, params: params, center: center, maxRadius: maxRadius)
		case .wedge:
			drawWedge(context: context, params: params, center: center, maxRadius: maxRadius)
		case .dot:
			drawDot(context: context, params: params, center: center, maxRadius: maxRadius)
		case .rectangle:
			drawRectangle(context: context, params: params, center: center, maxRadius: maxRadius)
		case .chickenhead:
			drawChickenhead(context: context, params: params, center: center, maxRadius: maxRadius)
		case .knurl:
			drawKnurl(context: context, params: params, center: center, maxRadius: maxRadius)
		case .dLine:
			drawDLine(context: context, params: params, center: center, maxRadius: maxRadius)
		case .trianglePointer:
			drawTrianglePointer(context: context, params: params, center: center, maxRadius: maxRadius)
		case .arrowPointer:
			drawArrowPointer(context: context, params: params, center: center, maxRadius: maxRadius)
		}

		// Convert to PNG data
		guard let image = context.makeImage() else { return nil }

#if os(macOS)
		let nsImage = NSImage(cgImage: image, size: size)
		guard let tiff = nsImage.tiffRepresentation,
			  let bitmap = NSBitmapImageRep(data: tiff),
			  let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
		return png
#else
		let uiImage = UIImage(cgImage: image)
		return uiImage.pngData()
#endif
	}

	private static func drawLine(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) * maxRadius / 2

		// Calculate line endpoints
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		// Draw as a thick line (rectangle)
		let perpAngle = angleRad + .pi / 2
		let dx = cos(perpAngle) * halfWidth
		let dy = sin(perpAngle) * halfWidth

		let path = CGMutablePath()
		path.move(to: CGPoint(x: innerX + dx, y: innerY + dy))
		path.addLine(to: CGPoint(x: outerX + dx, y: outerY + dy))
		path.addLine(to: CGPoint(x: outerX - dx, y: outerY - dy))
		path.addLine(to: CGPoint(x: innerX - dx, y: innerY - dy))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawWedge(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfAngle = CGFloat(params.width) * .pi  // width as angular spread

		let path = CGMutablePath()

		// Start at inner radius
		path.move(to: CGPoint(
			x: center.x + cos(angleRad - halfAngle) * innerR,
			y: center.y + sin(angleRad - halfAngle) * innerR
		))

		// Arc to outer radius
		path.addLine(to: CGPoint(
			x: center.x + cos(angleRad - halfAngle) * outerR,
			y: center.y + sin(angleRad - halfAngle) * outerR
		))

		// Arc along outer radius
		path.addArc(center: center, radius: outerR, startAngle: angleRad - halfAngle, endAngle: angleRad + halfAngle, clockwise: false)

		// Back to inner radius
		path.addLine(to: CGPoint(
			x: center.x + cos(angleRad + halfAngle) * innerR,
			y: center.y + sin(angleRad + halfAngle) * innerR
		))

		// Arc along inner radius (back to start)
		path.addArc(center: center, radius: innerR, startAngle: angleRad + halfAngle, endAngle: angleRad - halfAngle, clockwise: true)

		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawDot(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let radius = (CGFloat(params.innerRadius) + CGFloat(params.outerRadius)) / 2 * maxRadius
		let dotRadius = CGFloat(params.width) * maxRadius

		let dotX = center.x + cos(angleRad) * radius
		let dotY = center.y + sin(angleRad) * radius

		context.fillEllipse(in: CGRect(
			x: dotX - dotRadius,
			y: dotY - dotRadius,
			width: dotRadius * 2,
			height: dotRadius * 2
		))
	}

	private static func drawRectangle(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) * maxRadius / 2

		// Similar to line, but could be wider/different proportions
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		let perpAngle = angleRad + .pi / 2
		let dx = cos(perpAngle) * halfWidth
		let dy = sin(perpAngle) * halfWidth

		let path = CGMutablePath()
		path.move(to: CGPoint(x: innerX + dx, y: innerY + dy))
		path.addLine(to: CGPoint(x: outerX + dx, y: outerY + dy))
		path.addLine(to: CGPoint(x: outerX - dx, y: outerY - dy))
		path.addLine(to: CGPoint(x: innerX - dx, y: innerY - dy))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawChickenhead(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius

		// Chickenhead: tapered pointer, wide at base, narrow at tip
		let innerHalfWidth = baseWidth / 2
		let outerHalfWidth = baseWidth / 6

		let perpAngle = angleRad + .pi / 2
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		let path = CGMutablePath()
		path.move(to: CGPoint(
			x: innerX + cos(perpAngle) * innerHalfWidth,
			y: innerY + sin(perpAngle) * innerHalfWidth
		))
		path.addLine(to: CGPoint(
			x: outerX + cos(perpAngle) * outerHalfWidth,
			y: outerY + sin(perpAngle) * outerHalfWidth
		))
		path.addLine(to: CGPoint(
			x: outerX - cos(perpAngle) * outerHalfWidth,
			y: outerY - sin(perpAngle) * outerHalfWidth
		))
		path.addLine(to: CGPoint(
			x: innerX - cos(perpAngle) * innerHalfWidth,
			y: innerY - sin(perpAngle) * innerHalfWidth
		))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawKnurl(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let innerR = outerR * 0.85
		let notchCount = 12
		let notchWidth = CGFloat(params.width) * maxRadius * 0.3

		for i in 0..<notchCount {
			let notchAngle = angleRad + CGFloat(i) * (2 * .pi / CGFloat(notchCount))
			let perpAngle = notchAngle + .pi / 2

			let innerX = center.x + cos(notchAngle) * innerR
			let innerY = center.y + sin(notchAngle) * innerR
			let outerX = center.x + cos(notchAngle) * outerR
			let outerY = center.y + sin(notchAngle) * outerR

			let dx = cos(perpAngle) * notchWidth / 2
			let dy = sin(perpAngle) * notchWidth / 2

			let path = CGMutablePath()
			path.move(to: CGPoint(x: innerX + dx, y: innerY + dy))
			path.addLine(to: CGPoint(x: outerX + dx, y: outerY + dy))
			path.addLine(to: CGPoint(x: outerX - dx, y: outerY - dy))
			path.addLine(to: CGPoint(x: innerX - dx, y: innerY - dy))
			path.closeSubpath()

			context.addPath(path)
			context.fillPath()
		}
	}

	private static func drawDLine(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) * maxRadius / 2

		let perpAngle = angleRad + .pi / 2
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		// Draw line shaft
		let path = CGMutablePath()
		path.move(to: CGPoint(x: innerX + cos(perpAngle) * halfWidth, y: innerY + sin(perpAngle) * halfWidth))
		path.addLine(to: CGPoint(x: outerX + cos(perpAngle) * halfWidth, y: outerY + sin(perpAngle) * halfWidth))

		// Add semicircular cap at outer end
		path.addArc(center: CGPoint(x: outerX, y: outerY), radius: halfWidth,
					startAngle: angleRad - .pi / 2, endAngle: angleRad + .pi / 2, clockwise: false)

		path.addLine(to: CGPoint(x: innerX - cos(perpAngle) * halfWidth, y: innerY - sin(perpAngle) * halfWidth))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawTrianglePointer(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius

		let perpAngle = angleRad + .pi / 2
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		let path = CGMutablePath()
		path.move(to: CGPoint(
			x: innerX + cos(perpAngle) * baseWidth / 2,
			y: innerY + sin(perpAngle) * baseWidth / 2
		))
		path.addLine(to: CGPoint(x: outerX, y: outerY))
		path.addLine(to: CGPoint(
			x: innerX - cos(perpAngle) * baseWidth / 2,
			y: innerY - sin(perpAngle) * baseWidth / 2
		))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}

	private static func drawArrowPointer(context: CGContext, params: MaskParameters, center: CGPoint, maxRadius: CGFloat) {
		let angleRad = params.angleOffset * .pi / 180
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius

		let shaftWidth = baseWidth / 3
		let arrowWidth = baseWidth
		let shaftLength = (outerR - innerR) * 0.6
		let arrowStart = innerR + shaftLength

		let perpAngle = angleRad + .pi / 2
		let innerX = center.x + cos(angleRad) * innerR
		let innerY = center.y + sin(angleRad) * innerR
		let shaftEndX = center.x + cos(angleRad) * arrowStart
		let shaftEndY = center.y + sin(angleRad) * arrowStart
		let outerX = center.x + cos(angleRad) * outerR
		let outerY = center.y + sin(angleRad) * outerR

		let path = CGMutablePath()
		// Shaft
		path.move(to: CGPoint(x: innerX + cos(perpAngle) * shaftWidth, y: innerY + sin(perpAngle) * shaftWidth))
		path.addLine(to: CGPoint(x: shaftEndX + cos(perpAngle) * shaftWidth, y: shaftEndY + sin(perpAngle) * shaftWidth))
		path.addLine(to: CGPoint(x: shaftEndX + cos(perpAngle) * arrowWidth / 2, y: shaftEndY + sin(perpAngle) * arrowWidth / 2))
		// Arrowhead tip
		path.addLine(to: CGPoint(x: outerX, y: outerY))
		path.addLine(to: CGPoint(x: shaftEndX - cos(perpAngle) * arrowWidth / 2, y: shaftEndY - sin(perpAngle) * arrowWidth / 2))
		path.addLine(to: CGPoint(x: shaftEndX - cos(perpAngle) * shaftWidth, y: shaftEndY - sin(perpAngle) * shaftWidth))
		path.addLine(to: CGPoint(x: innerX - cos(perpAngle) * shaftWidth, y: innerY - sin(perpAngle) * shaftWidth))
		path.closeSubpath()

		context.addPath(path)
		context.fillPath()
	}
}
