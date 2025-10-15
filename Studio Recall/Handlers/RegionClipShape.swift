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
			case .chickenhead:
				return chickenheadPath(in: r)
			case .knurl:
				return knurlPath(in: r)
			case .dLine:
				return dLinePath(in: r)
			case .trianglePointer:
				return trianglePointerPath(in: r)
			case .arrowPointer:
				return arrowPointerPath(in: r)
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

	private func chickenheadPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Chickenhead: distinctive tapered pointer with wider base and narrow tip
		var path = Path()

		// Base width at inner radius
		let innerHalfWidth = baseWidth / 2.0
		// Tip width at outer radius (narrower)
		let outerHalfWidth = baseWidth / 6.0

		let innerLeft = CGPoint(
			x: center.x + innerR * cos(angleRad) - innerHalfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) + innerHalfWidth * cos(angleRad)
		)
		let innerRight = CGPoint(
			x: center.x + innerR * cos(angleRad) + innerHalfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) - innerHalfWidth * cos(angleRad)
		)
		let outerRight = CGPoint(
			x: center.x + outerR * cos(angleRad) + outerHalfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) - outerHalfWidth * cos(angleRad)
		)
		let outerLeft = CGPoint(
			x: center.x + outerR * cos(angleRad) - outerHalfWidth * sin(angleRad),
			y: center.y + outerR * sin(angleRad) + outerHalfWidth * cos(angleRad)
		)

		path.move(to: innerLeft)
		path.addLine(to: innerRight)
		path.addLine(to: outerRight)
		path.addLine(to: outerLeft)
		path.closeSubpath()

		return path
	}

	private func knurlPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let innerR = outerR * 0.85 // Knurl is a ring near the edge
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Knurl: series of small notches around the edge
		var path = Path()
		let notchCount = 12
		let notchWidth = CGFloat(params.width) * maxRadius * 0.3

		for i in 0..<notchCount {
			let notchAngle = angleRad + CGFloat(i) * (2.0 * .pi / CGFloat(notchCount))
			let c = cos(notchAngle)
			let s = sin(notchAngle)

			let innerPoint = CGPoint(
				x: center.x + innerR * c,
				y: center.y + innerR * s
			)
			let outerPoint = CGPoint(
				x: center.x + outerR * c,
				y: center.y + outerR * s
			)

			// Create small rectangular notch
			let perpAngle = notchAngle + .pi / 2
			let pc = cos(perpAngle)
			let ps = sin(perpAngle)

			let p1 = CGPoint(
				x: innerPoint.x - notchWidth / 2 * pc,
				y: innerPoint.y - notchWidth / 2 * ps
			)
			let p2 = CGPoint(
				x: innerPoint.x + notchWidth / 2 * pc,
				y: innerPoint.y + notchWidth / 2 * ps
			)
			let p3 = CGPoint(
				x: outerPoint.x + notchWidth / 2 * pc,
				y: outerPoint.y + notchWidth / 2 * ps
			)
			let p4 = CGPoint(
				x: outerPoint.x - notchWidth / 2 * pc,
				y: outerPoint.y - notchWidth / 2 * ps
			)

			path.move(to: p1)
			path.addLine(to: p2)
			path.addLine(to: p3)
			path.addLine(to: p4)
			path.closeSubpath()
		}

		return path
	}

	private func dLinePath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let halfWidth = CGFloat(params.width) / 2.0
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// D-line: line with a circular cap at the end
		var path = Path()

		// Line portion
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

		// Add semicircular cap at the outer end
		let capCenter = CGPoint(
			x: center.x + outerR * cos(angleRad),
			y: center.y + outerR * sin(angleRad)
		)
		let capRadius = halfWidth

		// Arc from outerRight to outerLeft around the cap
		path.addArc(
			center: capCenter,
			radius: capRadius,
			startAngle: Angle(radians: angleRad - .pi / 2),
			endAngle: Angle(radians: angleRad + .pi / 2),
			clockwise: false
		)

		path.closeSubpath()

		return path
	}

	private func trianglePointerPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Triangle: three points forming an isosceles triangle
		var path = Path()

		let halfWidth = baseWidth / 2.0

		// Base points at inner radius
		let baseLeft = CGPoint(
			x: center.x + innerR * cos(angleRad) - halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) + halfWidth * cos(angleRad)
		)
		let baseRight = CGPoint(
			x: center.x + innerR * cos(angleRad) + halfWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) - halfWidth * cos(angleRad)
		)

		// Apex at outer radius
		let apex = CGPoint(
			x: center.x + outerR * cos(angleRad),
			y: center.y + outerR * sin(angleRad)
		)

		path.move(to: baseLeft)
		path.addLine(to: baseRight)
		path.addLine(to: apex)
		path.closeSubpath()

		return path
	}

	private func arrowPointerPath(in rect: CGRect) -> Path {
		guard let params = maskParams else { return Path() }

		let center = CGPoint(x: rect.midX, y: rect.midY)
		let maxRadius = max(rect.width, rect.height) / 2
		let innerR = CGFloat(params.innerRadius) * maxRadius
		let outerR = CGFloat(params.outerRadius) * maxRadius
		let baseWidth = CGFloat(params.width) * maxRadius
		let angleRad = CGFloat(params.angleOffset) * .pi / 180.0

		// Arrow: line shaft with arrowhead at the tip
		var path = Path()

		let shaftWidth = baseWidth / 3.0
		let arrowWidth = baseWidth

		// Shaft portion
		let shaftLength = (outerR - innerR) * 0.6
		let arrowStart = innerR + shaftLength

		let innerLeft = CGPoint(
			x: center.x + innerR * cos(angleRad) - shaftWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) + shaftWidth * cos(angleRad)
		)
		let innerRight = CGPoint(
			x: center.x + innerR * cos(angleRad) + shaftWidth * sin(angleRad),
			y: center.y + innerR * sin(angleRad) - shaftWidth * cos(angleRad)
		)

		// Arrow base (where shaft meets arrowhead)
		let arrowLeft = CGPoint(
			x: center.x + arrowStart * cos(angleRad) - arrowWidth / 2 * sin(angleRad),
			y: center.y + arrowStart * sin(angleRad) + arrowWidth / 2 * cos(angleRad)
		)
		let arrowRight = CGPoint(
			x: center.x + arrowStart * cos(angleRad) + arrowWidth / 2 * sin(angleRad),
			y: center.y + arrowStart * sin(angleRad) - arrowWidth / 2 * cos(angleRad)
		)
		let shaftEndLeft = CGPoint(
			x: center.x + arrowStart * cos(angleRad) - shaftWidth * sin(angleRad),
			y: center.y + arrowStart * sin(angleRad) + shaftWidth * cos(angleRad)
		)
		let shaftEndRight = CGPoint(
			x: center.x + arrowStart * cos(angleRad) + shaftWidth * sin(angleRad),
			y: center.y + arrowStart * sin(angleRad) - shaftWidth * cos(angleRad)
		)

		// Arrowhead tip
		let tip = CGPoint(
			x: center.x + outerR * cos(angleRad),
			y: center.y + outerR * sin(angleRad)
		)

		path.move(to: innerLeft)
		path.addLine(to: innerRight)
		path.addLine(to: shaftEndRight)
		path.addLine(to: arrowRight)
		path.addLine(to: tip)
		path.addLine(to: arrowLeft)
		path.addLine(to: shaftEndLeft)
		path.closeSubpath()

		return path
	}
}
