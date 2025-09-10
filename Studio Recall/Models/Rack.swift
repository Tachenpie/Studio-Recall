//
//  Rack.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import Foundation

struct Rack: Identifiable, Codable {
    var id: UUID = UUID()
    var slots: [DeviceInstance?]
    var position: CGPoint = .zero

    init(slotCount: Int) {
        self.slots = Array(repeating: nil, count: slotCount)
    }
}
