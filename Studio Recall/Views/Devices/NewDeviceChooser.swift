//
//  NewDeviceChooser.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import SwiftUI

struct NewDeviceChooser: View {
    var onChoose: (Device) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Device Type")
                .font(.headline)
                .padding(.top)

            Button {
                let rackDevice = Device(
                    name: "New Rack Device",
                    type: .rack,
                    rackUnits: 1
                )
                onChoose(rackDevice)
            } label: {
                Label("Rack Gear", systemImage: "rectangle.3.offgrid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                let slotDevice = Device(
                    name: "New 500-Series Module",
                    type: .series500,
                    slotWidth: 1
                )
                onChoose(slotDevice)
            } label: {
                Label("500-Series Module", systemImage: "square.grid.3x1.folder.fill.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 300, height: 220)
    }
}
