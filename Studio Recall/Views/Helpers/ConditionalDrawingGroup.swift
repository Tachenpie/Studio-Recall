//
//  ConditionalDrawingGroup.swift
//  Studio Recall
//
//  Created by True Jackie on 9/29/25.
//


import SwiftUI

/// Flattens a subtree while `active` is true. Use on faces/devices during pan/zoom/drag.
struct ConditionalDrawingGroup: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.compositingGroup().drawingGroup(opaque: false, colorMode: .linear)
        } else {
            content
        }
    }
}
