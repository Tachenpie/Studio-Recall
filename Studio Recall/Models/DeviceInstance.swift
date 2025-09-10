//
//  DeviceInstance.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//

import Foundation

/// Represents a physical unit of a device placed in a rack/chassis.
/// References a `Device` from the library, but has its own unique ID.
struct DeviceInstance: Identifiable, Codable, Hashable {
    let id: UUID         // unique per instance
    let deviceID: UUID   // points to the library Device
    
    init(deviceID: UUID) {
        self.id = UUID()
        self.deviceID = deviceID
    }
}
