//
//  RegionClipShape.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI

/// Clips a view to various shapes at runtime.
struct RegionClipShape: InsettableShape {
	var shape: ImageRegionShape
	var maskParams: MaskParameters?    // For parametric shapes (wedge, line, dot, pointer)
	private var insetAmount: CGFloat = 0

	init(shape: ImageRegionShape, maskParams: MaskParameters? = nil) {
		self.shape = shape
		self.maskParams = maskParams
	}

	func path(in rect: CGRect) -> Path {
		let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
		switch shape {
			case .rect:
				var p = Path()
				p.addRect(r)
				return p
			case .circle:
				return Path(ellipseIn: r)
			case .wedge:
				return wedgePath(in: r)
			case .line:
				return linePath(in: r)
			case .dot:
				return dotPath(in: r)
			case .pointer:
				return pointerPath(in: r)
		}
	}

	func inset(by amount: CGFloat) -> some InsettableShape {
		var s = self
		s.insetAmount += amount
		return s
	}

	// MARK: - Parametric Shape Paths

	private func wedgePath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) / 2.0
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Wedge: triangle from center extending outward
		var path = Path()

		// Calculate the three points of the wedge
		let innerLeft = CGPoint(
			x: center.x + innerR * cos(angleRad - halfWidth),
			y: center.y + innerR * sin(angleRad - halfWidth)
		)
		let innerRight = CGPoint(
			x: center.x + innerR * cos(angleRad + halfWidth),
			y: center.y + innerR * sin(angleRad + halfWidth)
		)
		let outerPoint = CGPoint(
			x: center.x + outerR * cos(angleRad),
			y: center.y + outerR * sin(angleRad)
		)

		path.move(to: innerLeft)
		path.addLine(to: outerPoint)
		path.addLine(to: innerRight)
		path.closeSubpath()

		return path
	}

	private func linePath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) / 2.0
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Line: thin rectangle extending from innerRadius to outerRadius
		var path = Path()

		// Four corners of the line rectangle
		let innerLeft = CGPoint(
			x: center.x + innerR * cos(angleRad) - halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) + halfWidth * cos(angleRad)
		)
		let innerRight = CGPoint(
			x: center.x + innerR * cos(angleRad) + halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) - halfWidth * cos(angleRad)
		)
		let outerRight = CGPoint(
			x: center.x + outerR * cos(angleRad) + halfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) - halfWidth * cos(angleRad)
		)
		let outerLeft = CGPoint(
			x: center.x + outerR * cos(angleRad) - halfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) + halfWidth * cos(angleRad)
		)

		path.move(to: innerLeft)
		path.addLine(to: innerRight)
		path.addLine(to: outerRight)
		path.addLine(to: outerLeft)
		path.closeSubpath()

		return path
	}

	private func dotPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let radius = CGFloat(params.outerRadius) * maxRadius
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0
		let dotRadius = CGFloat(params.width) * maxRadius / 2

		// Dot: small circle at the specified position
		let dotCenter = CGPoint(
			x: center.x + radius * cos(angleRad),
			y: center.y + radius * sin(angleRad)
		)

		let dotRect = CGRect(
			x: dotCenter.x - dotRadius,
			y: dotCenter.y - dotRadius,
			width: dotRadius * 2,
			height: dotRadius * 2
		)

		return Path(ellipseIn: dotRect)
	}

	private func pointerPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) / 2.0
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Pointer: same as line but potentially with different default parameters
		var path = Path()

		let innerLeft = CGPoint(
			x: center.x + innerR * cos(angleRad) - halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) + halfWidth * cos(angleRad)
		)
		let innerRight = CGPoint(
			x: center.x + innerR * cos(angleRad) + halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) - halfWidth * cos(angleRad)
		)
		let outerRight = CGPoint(
			x: center.x + outerR * cos(angleRad) + halfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) - halfWidth * cos(angleRad)
		)
		let outerLeft = CGPoint(
			x: center.x + outerR * cos(angleRad) - halfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) + halfWidth * cos(angleRad)
		)

		path.move(to: innerLeft)
		path.addLine(to: innerRight)
		path.addLine(to: outerRight)
		path.addLine(to: outerLeft)
		path.closeSubpath()

		return path
	}
}
