//
//  DonutShape.swift
//  Studio Recall
//
//  Created by True Jackie on 9/16/25.
//
import SwiftUI

/// A shape representing a ring (outer circle minus inner circle).
struct DonutShape: Shape {
	var outerRect: CGRect
	var innerRect: CGRect
	
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.addEllipse(in: outerRect)
		path.addEllipse(in: innerRect)
		return path
	}
}

