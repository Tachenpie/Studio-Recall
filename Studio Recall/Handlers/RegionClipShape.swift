//
//  RegionClipShape.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//

import SwiftUI

/// Clips a view to either a rectangle or a circle at runtime.
struct RegionClipShape: InsettableShape {
	var shape: ImageRegionShape        // .rect or .circle
	private var insetAmount: CGFloat = 0
	
	init(shape: ImageRegionShape) { self.shape = shape }
	
	func path(in rect: CGRect) -> Path {
		let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
		switch shape {
			case .rect:
				var p = Path()
				p.addRect(r)
				return p
			case .circle:
				return Path(ellipseIn: r)
		}
	}
	
	func inset(by amount: CGFloat) -> some InsettableShape {
		var s = self
		s.insetAmount += amount
		return s
	}
}
