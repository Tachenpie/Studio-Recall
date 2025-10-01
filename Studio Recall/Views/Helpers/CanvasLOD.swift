//
//  CanvasLOD.swift
//  Studio Recall
//
//  Created by True Jackie on 9/30/25.
//
import SwiftUI

// MARK: - Canvas LOD
enum CanvasLOD { case low, medium, full }

struct CanvasLODKey: EnvironmentKey { static let defaultValue: CanvasLOD = .full }

extension EnvironmentValues {
    var canvasLOD: CanvasLOD {
        get { self[CanvasLODKey.self] }
        set { self[CanvasLODKey.self] = newValue }
    }
}
