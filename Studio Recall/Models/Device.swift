//
//  Device.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Device Type Enum
enum DeviceType: String, Codable, CaseIterable {
    case rack
    case series500
    
    var displayName: String {
        switch self {
        case .rack:
            return "Rack Gear"
        case .series500:
            return "500 Series Module"
        }
    }
}

enum RackWidth: Int, Codable, CaseIterable, Identifiable {
	case full  = 6
	case half  = 3
	case third = 2
	
	var id: Int { rawValue }
	var label: String {
		switch self {
			case .full: return "Full (19\")"
			case .half: return "Half (½)"
			case .third: return "Third (⅓)"
		}
	}
}

// MARK: - Device Model
struct Device: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String

    var type: DeviceType        // Rack vs 500
    
    var controls: [Control] = []
    
    // Physical sizing
    var rackUnits: Int? = 1       // e.g., 1U, 2U
	var rackWidth: RackWidth = .full
    var slotWidth: Int? = nil       // e.g., 1 slot, 2 slots

	var wingWidthInches: CGFloat = DeviceMetrics.wingWidth
    
    var isFiller: Bool = false  // true = blank panel
    
    var imageData: Data? = nil  // expects a PNG in asset catalog or file system
    
    var categories: [String] = []   // User-defined categories
    
    // Equatable
    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
}

final class EditableDevice: ObservableObject, Identifiable {
    @Published var device: Device
    let id = UUID()
    
	@Published var revision: Int = 0
	func bumpRevision() { revision &+= 1 }
	
    init(device: Device) {
        self.device = device
    }
}
