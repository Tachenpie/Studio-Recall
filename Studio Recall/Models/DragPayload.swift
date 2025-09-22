//
//  DragPayload.swift
//  Studio Recall
//
//  Created by True Jackie on 9/3/25.
//
import SwiftUI
import UniformTypeIdentifiers

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

extension DragPayload {
	/// Canonical provider for rack/library drags.
	func itemProvider() -> NSItemProvider {
		let provider = NSItemProvider()
		let data = (try? JSONEncoder().encode(self)) ?? Data()
		
		// Our custom type
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.deviceDragPayload.identifier,
			visibility: .all
		) { completion in
			completion(data, nil)
			return nil
		}
		
		// A couple of safe fallbacks so .onDrop(of:[...]) still wakes up
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.data.identifier,
			visibility: .all
		) { completion in
			completion(data, nil)
			return nil
		}
		provider.registerDataRepresentation(
			forTypeIdentifier: UTType.utf8PlainText.identifier,
			visibility: .all
		) { completion in
			completion(data, nil)
			return nil
		}
		
		return provider
	}
}
