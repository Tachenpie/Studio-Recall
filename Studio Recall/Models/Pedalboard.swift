//
//  Pedalboard.swift
//  Studio Recall
//
//  Pedalboard for guitar/effect pedals with free-form placement
//

import Foundation

struct Pedalboard: Identifiable, Codable {
	var id: UUID = UUID()
	var name: String?
	var widthInches: Double  // Width in inches
	var heightInches: Double  // Height in inches
	var pedals: [PedalPlacement] = []  // Pedals with their positions
	var position: CGPoint = .zero  // Position in session canvas

	init(name: String? = nil, widthInches: Double = 24, heightInches: Double = 12) {
		self.name = name
		self.widthInches = max(12, min(48, widthInches))  // Constrain to 12"-48"
		self.heightInches = max(8, min(24, heightInches))  // Constrain to 8"-24"
	}
}

/// Represents a pedal placed on a pedalboard with its position
struct PedalPlacement: Identifiable, Codable {
	var id: UUID = UUID()
	var instance: DeviceInstance
	var position: CGPoint  // Position relative to pedalboard top-left (in inches)

	init(instance: DeviceInstance, position: CGPoint = .zero) {
		self.instance = instance
		self.position = position
	}
}
