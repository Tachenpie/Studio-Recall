//
//  DragPayload.swift
//  Studio Recall
//
//  Created by True Jackie on 9/3/25.
//
import SwiftUI

struct DragPayload: Codable, Identifiable {
    enum Source: String, Codable {
        case library
        case instance
    }
    
    let id: UUID            // DeviceInstance.id if dragging from chassis
    let source: Source      // Where it's coming from
    let deviceId: UUID      // Always present. Which device.
    let instanceId: UUID?   // Only if we're moving an existing device.
    
    init(deviceId: UUID) {
        self.id = UUID()
        self.source = .library
        self.deviceId = deviceId
        self.instanceId = nil
    }
    
    init(instanceId: UUID, deviceId: UUID) {
        self.id = UUID()
        self.source = .instance
        self.deviceId = deviceId
        self.instanceId = instanceId
    }
}
