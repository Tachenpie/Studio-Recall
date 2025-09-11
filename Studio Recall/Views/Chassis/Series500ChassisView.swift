//
//  Series500ChassisView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct Series500ChassisView: View {
    @Binding var chassis: Series500Chassis
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    @State private var hoveredIndex: Int? = nil
    @State private var hoveredValid: Bool = false
    @State private var hoveredRange: Range<Int>? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            chassisContent
        }
        .background(Color.black)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 2))
    }
    
    private var chassisContent: some View {
        var views: [AnyView] = []
        var index = 0
        
		while index < chassis.slots.count {
			if let instance = chassis.slots[index],
			   let device = library.device(for: instance.deviceID) {
				
				let slotWidth = device.slotWidth ?? 1
				views.append(
					AnyView(
						Series500ChassisSlotView(
							index: index,
							instance: instance,
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid
						)
						.frame(width: DeviceMetrics
							.moduleSize(units: slotWidth, scale: settings.pointsPerInch).width)
					)
				)
				index += slotWidth
			} else {
				views.append(
					AnyView(
						Series500ChassisSlotView(
							index: index,
							instance: nil,
							slots: $chassis.slots,
							hoveredIndex: $hoveredIndex,
							hoveredRange: $hoveredRange,
							hoveredValid: $hoveredValid
						)
					)
				)
				index += 1
			}
		}

        return HStack(spacing: 4) {
            ForEach(Array(views.enumerated()), id: \.offset) { _, view in
                view
            }
        }
    }
}
