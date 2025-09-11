//
//  MoveHandle.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//

import SwiftUI

struct MoveHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.001)) // invisible but hittable
            .overlay(
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(2)
            )
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .help("Drag to move this device")
    }
}
