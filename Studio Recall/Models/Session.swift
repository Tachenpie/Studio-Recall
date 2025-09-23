//
//  Session.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

// MARK: - Session Model
struct Session: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var racks: [Rack] = []
    var series500Chassis: [Series500Chassis] = []
	var labels: [SessionLabel] = []
	
	var canvasZoom: Double = 1.2
	var canvasPan: CGPoint = .zero
}
