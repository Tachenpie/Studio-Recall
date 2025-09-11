//
//  Series500ChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI

struct Series500ChassisSlotView: View {
    let index: Int
    let instance: DeviceInstance?
    @Binding var slots: [DeviceInstance?]
    
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    @Binding var hoveredIndex: Int?
    @Binding var hoveredRange: Range<Int>?
    @Binding var hoveredValid: Bool

    var body: some View {
        Group {
            if let instance, let device = library.device(for: instance.deviceID) {
                deviceView(device, instance: instance)
            } else {
                emptySlotView()
            }
        }
    }

    private func deviceView(_ device: Device, instance: DeviceInstance) -> some View {
        let units = device.slotWidth ?? 1
        let moduleSize = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)

        return EditableDeviceView(device: .constant(device))
                .frame(width: moduleSize.width, height: moduleSize.height)
                .padding(.vertical, 4)
                .onDrag {
                    let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
                    DragContext.shared.beginDrag(payload: payload)
                    if let data = try? JSONEncoder().encode(payload) {
                        return NSItemProvider(item: data as NSData,
                                              typeIdentifier: UTType.deviceDragPayload.identifier)
                    }
                    return NSItemProvider()
                } preview: {
                    DeviceView(device: device)
                        .frame(width: 60, height: 80)
                        .shadow(radius: 4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(highlightColor(), lineWidth: 3)
                )
    }

    private func emptySlotView(units: Int = 1) -> some View {
        let moduleSize = DeviceMetrics.moduleSize(units: units, scale: settings.pointsPerInch)

        return Rectangle()
            .fill(Color.clear)
            .frame(width: moduleSize.width, height: moduleSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .onDrop(
                of: [UTType.deviceDragPayload],
                delegate: ChassisDropDelegate(
                    currentIndex: index,
                    slots: $slots,
                    hoveredIndex: $hoveredIndex,
                    hoveredValid: $hoveredValid,
                    hoveredRange: $hoveredRange,
                    library: library,
                    measure: { $0.slotWidth ?? 1 },
                    kind: .series500
                )
            )
    }

    private func highlightColor() -> Color {
        if let range = hoveredRange, range.contains(index) {
            return hoveredValid ? .green : .red
        }
        return .clear
    }
}
