//
//  DeviceSidebarRow.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//

import SwiftUI

struct DeviceSidebarRow: View {
    let device: Device
    
    var body: some View {
        HStack(spacing: 12) {
            // Faceplate thumbnail
            FaceplatePreview(device: device)
                .frame(width: 60, height: 30) // small thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 0.5))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                    .lineLimit(1)
                
                Text(device.type == .rack
                     ? "\(device.rackUnits ?? 1)U"
                     : "\(device.slotWidth ?? 1) slots")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
