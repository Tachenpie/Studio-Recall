//
//  RackRect.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

struct RackRect: Equatable, Identifiable {
    let id: UUID
    let frame: CGRect
}

struct RackRectsKey: PreferenceKey {
    static var defaultValue: [RackRect] = []
    static func reduce(value: inout [RackRect], nextValue: () -> [RackRect]) {
        value.append(contentsOf: nextValue())
    }
}
