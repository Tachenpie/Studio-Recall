//
//  RackChassisSlotView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/2/25.
//
import UniformTypeIdentifiers
import SwiftUI

struct RackChassisSlotView: View {
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
        let units = device.rackUnits ?? 1
        let rackSize = DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch)
        let topIndex = indexOfInstance(instance)

        return DeviceView(device: device)
                .frame(width: rackSize.width, height: rackSize.height)
                .onDrag {
                    let payload = DragPayload(instanceId: instance.id, deviceId: device.id)
                    DragContext.shared.beginDrag(payload: payload)
                        if let data = try? JSONEncoder().encode(payload) {
                        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.deviceDragPayload.identifier)
                    }
                    return NSItemProvider()
                }
                preview: {
                    DeviceView(device: device)
                        .frame(width: 80, height: 40)
                        .shadow(radius: 4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(highlightColor(forTopIndex: topIndex), lineWidth: 3)
                        
                )
    }

    private func emptySlotView(units: Int = 1) -> some View {
        let rackSize = DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch)

        return Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: rackSize.width, height: rackSize.height)
            .onDrop(
                of: [UTType.deviceDragPayload],
                delegate: ChassisDropDelegate(
                    currentIndex: index,
                    slots: $slots,
                    hoveredIndex: $hoveredIndex,
                    hoveredValid: $hoveredValid,
                    hoveredRange: $hoveredRange,
                    library: library,
                    measure: { $0.rackUnits ?? 1 },
                    kind: .rack
                )
            )
    }

    private func indexOfInstance(_ instance: DeviceInstance) -> Int? {
        slots.firstIndex(where: { $0?.id == instance.id })
    }
    
    private func highlightColor(forTopIndex topIndex: Int?) -> Color {
        if let range = hoveredRange, range.contains(index) {
            return hoveredValid ? .green : .red
        }
        return .clear
    }

}
