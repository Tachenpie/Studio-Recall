//
//  RackChassisView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import UniformTypeIdentifiers
import SwiftUI

struct RackChassisView: View {
    @Binding var rack: Rack
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            chassisContent
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
    
    private var chassisContent: some View {
        var views: [AnyView] = []
        var index = 0
        
        while index < rack.slots.count {
            if let instance = rack.slots[index],
               let device = library.device(for: instance.deviceID) {
                
                let units = device.rackUnits ?? 1
                views.append(
                    AnyView(
                        RackChassisSlotView(
                            index: index,
                            instance: instance,
                            slots: $rack.slots,
                            hoveredIndex: $hoveredIndex,
                            hoveredRange: $hoveredRange,
                            hoveredValid: $hoveredValid
                        )
                        .frame(height: DeviceMetrics.rackSize(units: units, scale: settings.pointsPerInch).height)
                    )
                )
                index += units // skip occupied slots
            } else {
                views.append(
                    AnyView(
                        RackChassisSlotView(
                            index: index,
                            instance: nil,
                            slots: $rack.slots,
                            hoveredIndex: $hoveredIndex,
                            hoveredRange: $hoveredRange,
                            hoveredValid: $hoveredValid
                        )
                    )
                )
                index += 1
            }
        }

    
    return VStack(spacing: 4) {
        ForEach(Array(views.enumerated()), id: \.offset) { _, view in
            view
        }
    }
}
}
