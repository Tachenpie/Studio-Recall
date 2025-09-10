//
//  AnyShape.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//
import SwiftUI

// Clips a view to either a rectangle or a circle, decided at runtime.
struct RegionClipShape: Shape {
	let shape: ImageRegionShape   // .rect or .circle
	func path(in rect: CGRect) -> Path {
		switch shape {
			case .rect:
				return Path(rect)                  // rectangle path
			case .circle:
				return Path(ellipseIn: rect)       // perfect circle in rect
		}
	}
}
