//
//  MaskGenerator.swift
//  Studio Recall
//
//  Generates alpha mask images for carved knob pointers
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

struct MaskGenerator {
	/// Generate a mask image from parameters
	/// Returns PNG data (white = shows pointer/opaque, black = shows background/transparent)
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
}
