//
//  Device.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

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

// MARK: - Device Model
struct Device: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String

    var type: DeviceType        // Rack vs 500
    
    var controls: [Control] = []
    
    // Physical sizing
    var rackUnits: Int? = 1       // e.g., 1U, 2U
    var slotWidth: Int? = nil       // e.g., 1 slot, 2 slots
    
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
    
    init(device: Device) {
        self.device = device
    }
}

struct DeviceMetrics {
    /// Scale in pixels per inch (ppi)
    static func rackSize(units: Int, scale: CGFloat) -> CGSize {
        CGSize(
            width: 19 * scale,                   // standard rack width in inches
            height: CGFloat(units) * 1.75 * scale // 1U = 1.75 inches
        )
    }

    static func moduleSize(units: Int, scale: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(units) * 1.5 * scale,                   // module width in inches
            height: 3 * 1.75 * scale              // 3U tall (like Eurorack)
        )
    }
}

