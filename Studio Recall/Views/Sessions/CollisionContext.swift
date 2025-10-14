//
//  CollisionContext.swift
//  Studio Recall
//
//  Provides collision detection data for rack/chassis dragging
//

import SwiftUI

/// Collision information for a single rack or chassis
struct CollisionRect: Identifiable {
	let id: UUID
	let rect: CGRect
	let isRack: Bool  // true for rack, false for 500-series
}

/// Environment key for passing collision data to drag handlers
struct CollisionContextKey: EnvironmentKey {
	static let defaultValue: [CollisionRect] = []
}

extension EnvironmentValues {
	var collisionRects: [CollisionRect] {
		get { self[CollisionContextKey.self] }
		set { self[CollisionContextKey.self] = newValue }
	}
}
