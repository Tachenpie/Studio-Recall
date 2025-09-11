//
//  DragTypes.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//

import UniformTypeIdentifiers

extension UTType {
    /// UUID of a device from the library
	static let deviceID   = UTType(exportedAs: "com.studiorecall.device-id", conformingTo: .data)
    /// Int index when dragging an already-placed device inside a chassis
	static let chassisIndex = UTType(exportedAs: "com.studiorecall.chassis-index", conformingTo: .data)
	static let deviceInstanceID = UTType(exportedAs: "com.studiorecall.device-instance-id", conformingTo: .data)
	static let deviceDragPayload = UTType(exportedAs: "com.studiorecall.device-drag-payload", conformingTo: .data)
}
