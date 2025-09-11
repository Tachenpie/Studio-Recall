//
//  InstanceDiff.swift
//  Studio Recall
//
//  Created by True Jackie on 9/10/25.
//
import Foundation

struct InstanceDiff {
    let instanceID: UUID
    let deviceName: String
    let location: String   // "Rack 1 Slot 3" or "Chassis A Slot 2"
    let diffs: [ControlDiff]
}
