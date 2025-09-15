//
//  CanvasContent.swift
//  Studio Recall
//
//  Created by True Jackie on 9/4/25.
//


import SwiftUI

struct CanvasContent: View {
    @ObservedObject var editableDevice: EditableDevice
    let canvasSize: CGSize
    @Binding var selectedControlId: UUID?
    @Binding var draggingControlId: UUID?
    let gridStep: CGFloat
	let showBadges: Bool

    var body: some View {
        ZStack {
            // Faceplate
            if let data = editableDevice.device.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                Text("No Faceplate Image").foregroundColor(.white.opacity(0.7))
            }

            // Controls
            ForEach($editableDevice.device.controls) { $control in
                ControlItemView(
                    control: $control,
                    geoSize: canvasSize,
                    editableDevice: editableDevice,
                    selectedControlId: $selectedControlId,
                    draggingControlId: $draggingControlId,
                    gridStep: gridStep,
					showBadges: showBadges
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}
