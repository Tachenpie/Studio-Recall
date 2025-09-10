//
//  ChassisView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

//struct ChassisView: View {
//    var chassis: Chassis
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            Text(chassis.name)
//                .font(.title2)
//                .foregroundColor(.white)
//                .padding(.bottom, 8)
//            
//            if chassis.type == .rack {
//                VStack(spacing: 4) {
//                    ForEach(fullRackDevices) { $device in
//                        EditableDeviceView(device: $device)
//                    }
//                }
//            } else {
//                HStack(spacing: 4) {
//                    ForEach(fullSeriesDevices) { device in
//                        DeviceView(device: device)
//                    }
//                }
//            }
//        }
//        .padding()
//        .background(chassisBackground)
//        .cornerRadius(12)
//        .shadow(radius: 6)
//    }
//    
//    private var fullRackDevices: [Device] {
//        guard let maxU = chassis.totalRackUnits else { return chassis.devices }
//        let usedU = chassis.devices.compactMap { $0.rackUnits }.reduce(0, +)
//        let fillers = max(0, maxU - usedU)
//        
//        return chassis.devices + (fillers > 0 ? [
//            Device(name: "Blank Panel", type: .rack, controls: [],
//                   rackUnits: fillers, isFiller: true)
//        ] : [])
//    }
//    
//    private var fullSeriesDevices: [Device] {
//        guard let maxSlots = chassis.totalSlots else { return chassis.devices }
//        let usedSlots = chassis.devices.compactMap { $0.slotWidth }.reduce(0, +)
//        let fillers = max(0, maxSlots - usedSlots)
//        
//        return chassis.devices + (fillers > 0 ? [
//            Device(name: "Empty Slot", type: .series500, controls: [],
//                   slotWidth: fillers, isFiller: true)
//        ] : [])
//    }
//    
//    private var chassisBackground: some View {
//        switch chassis.type {
//        case .rack:
//            return AnyView(
//                LinearGradient(colors: [.black, .gray.opacity(0.7)],
//                               startPoint: .top,
//                               endPoint: .bottom)
//            )
//        case .series500:
//            return AnyView(
//                LinearGradient(colors: [.gray.opacity(0.8), .black],
//                               startPoint: .leading,
//                               endPoint: .trailing)
//            )
//        }
//    }
//}




struct DeviceDragDropDemo: View {
    @State private var rack = Rack(slots: [])
    @State private var chassis = Series500Chassis(slots: [
        Device(name: "Empty Slot", type: .series500, controls: [], slotWidth: 1, isFiller: true),
        Device(name: "Empty Slot", type: .series500, controls: [], slotWidth: 1, isFiller: true),
        Device(name: "Empty Slot", type: .series500, controls: [], slotWidth: 2, isFiller: true)
    ])
    
    private let availableDevices = [
        Device(name: "EQ", type: .rack, controls: [], rackUnits: 2),
        Device(name: "Compressor", type: .rack, controls: [], rackUnits: 3),
        Device(name: "Preamp", type: .series500, controls: [], slotWidth: 1),
        Device(name: "Saturator", type: .series500, controls: [], slotWidth: 2)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rack Units").foregroundColor(.white)
            RackChassisView(rack: $rack)
                .frame(height: 300)
            
            Text("500 Series").foregroundColor(.white)
            Series500ChassisView(chassis: $chassis)
                .frame(height: 160)
            
            Spacer()
            
            DevicePalette(devices: availableDevices)
        }
        .padding()
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

#Preview {
    DeviceDragDropDemo()
}


//struct EditableChassisView: View {
//    @State var chassis: Chassis
//    @State private var selectedDevice: Device? = nil
//    
//    var body: some View {
//        VStack {
//            ChassisView(chassis: chassis)
//                .onTapGesture {
//                    // just demo: select first device
//                    selectedDevice = chassis.devices.first
//                }
//            
////            if let device = Binding($selectedDevice) {
////                DeviceEditorScreen(device: device)
////            }
//        }
//    }
//}
