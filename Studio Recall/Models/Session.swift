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
	var pedalboards: [Pedalboard] = []
	var labels: [SessionLabel] = []

	var canvasZoom: Double = 1.2
	var canvasPan: CGPoint = .zero

	// Custom decoding for backward compatibility
	enum CodingKeys: String, CodingKey {
		case id, name, racks, series500Chassis, pedalboards, labels, canvasZoom, canvasPan
	}

	init(id: UUID = UUID(), name: String, racks: [Rack] = [], series500Chassis: [Series500Chassis] = [],
		 pedalboards: [Pedalboard] = [], labels: [SessionLabel] = [], canvasZoom: Double = 1.2,
		 canvasPan: CGPoint = .zero) {
		self.id = id
		self.name = name
		self.racks = racks
		self.series500Chassis = series500Chassis
		self.pedalboards = pedalboards
		self.labels = labels
		self.canvasZoom = canvasZoom
		self.canvasPan = canvasPan
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(UUID.self, forKey: .id)
		name = try container.decode(String.self, forKey: .name)
		racks = try container.decode([Rack].self, forKey: .racks)
		series500Chassis = try container.decode([Series500Chassis].self, forKey: .series500Chassis)
		// Backward compatibility: pedalboards may not exist in old sessions
		pedalboards = try container.decodeIfPresent([Pedalboard].self, forKey: .pedalboards) ?? []
		labels = try container.decode([SessionLabel].self, forKey: .labels)
		canvasZoom = try container.decode(Double.self, forKey: .canvasZoom)
		canvasPan = try container.decode(CGPoint.self, forKey: .canvasPan)
	}
}
