//
//  Series500Chassis.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import Foundation

struct Series500Chassis: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String?
    var slots: [DeviceInstance?]
    var position: CGPoint = .zero

	// Mounting state: if mounted in a rack, stores rack ID and row position
	var mountedInRack: UUID? = nil
	var mountedAtRow: Int? = nil

    init(name: String?, slotCount: Int) {
        self.name = name
        self.slots = Array(repeating: nil, count: slotCount)
    }

	init(slotCount: Int) {
		self.slots = Array(repeating: nil, count: slotCount)
	}

	var isMounted: Bool {
		mountedInRack != nil
	}
}
