//
//  CanvasLOD.swift
//  Studio Recall
//
//  Created by True Jackie on 9/30/25.
//
import SwiftUI

// MARK: - Canvas LOD
// Mipmapping levels for game-style performance
// Each level is half the resolution of the previous
enum CanvasLOD {
	case level3  // 1/8 resolution (~12.5% pixels)
	case level2  // 1/4 resolution (25% pixels)
	case level1  // 1/2 resolution (50% pixels)
	case full    // Original resolution

	// Legacy compatibility
	static let low = level3
	static let medium = level2
}

struct CanvasLODKey: EnvironmentKey { static let defaultValue: CanvasLOD = .full }

extension EnvironmentValues {
    var canvasLOD: CanvasLOD {
        get { self[CanvasLODKey.self] }
        set { self[CanvasLODKey.self] = newValue }
    }
}
