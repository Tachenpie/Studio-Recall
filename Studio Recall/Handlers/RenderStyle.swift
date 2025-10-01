//
//  RenderStyle.swift
//  Studio Recall
//
//  Created by True Jackie on 10/1/25.
//

import SwiftUI

/// Two render modes: photo-real PNG faceplates or lightweight vector representatives.
enum RenderStyle: String, CaseIterable {
	case photoreal      // current behavior
	case representative // fast path (no faceplate images / patches)
}

// Environment plumbing
private struct RenderStyleKey: EnvironmentKey {
	static let defaultValue: RenderStyle = .photoreal
}
extension EnvironmentValues {
	var renderStyle: RenderStyle {
		get { self[RenderStyleKey.self] }
		set { self[RenderStyleKey.self] = newValue }
	}
}
