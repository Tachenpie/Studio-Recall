//
//  DeviceView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct DeviceView: View {
    let device: Device
    
    var body: some View {
        ZStack {
            if let data = device.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: device.type == .series500 ?
                            CGFloat((device.slotWidth ?? 1) * 120) : nil,
                        height: device.type == .rack ?
                            CGFloat((device.rackUnits ?? 1) * 60) : nil
                    )
                    .cornerRadius(4)
            } else {
                drawnDevice
            }
        }
    }
    
    private var drawnDevice: some View {
        VStack(spacing: 16) {
            if device.isFiller {
                Spacer()
            } else {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 20) {
                    ForEach(device.controls) { control in
                        ControlView(control: .constant(control))
                    }
                }
            }
        }
        .padding()
        .frame(
            width: device.type == .series500 ?
                CGFloat((device.slotWidth ?? 1) * 120) : nil,
            height: device.type == .rack ?
                CGFloat((device.rackUnits ?? 1) * 60) : nil
        )
        .background(deviceBackground)
        .cornerRadius(4)
    }
    
    private var deviceBackground: some View {
        if device.isFiller {
            return AnyView(Color.black.opacity(0.3))
        }
        
        switch device.type {
        case .rack:
            return AnyView(
                LinearGradient(colors: [.gray.opacity(0.9), .black],
                               startPoint: .top,
                               endPoint: .bottom)
            )
        case .series500:
            return AnyView(
                LinearGradient(colors: [.black, .gray.opacity(0.6)],
                               startPoint: .leading,
                               endPoint: .trailing)
            )
        @unknown default:
            return AnyView(Color.gray)
        }
    }
}

struct EditableDeviceView: View {
    @Binding var device: Device
    @State private var editorModel: EditableDevice? = nil   // for sheet

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Faceplate image or gradient fallback
                if let data = device.imageData {
                    #if os(macOS)
                    if let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                    #else
                    if let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                    #endif
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [.black, .gray],
                                             startPoint: .top,
                                             endPoint: .bottom))
                        .cornerRadius(8)
                }

                // Draggable controls
                ForEach($device.controls, id: \.id) { $control in
                    ControlView(control: $control)
                        .position(x: control.x * geo.size.width,
                                  y: control.y * geo.size.height)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    control.x = min(max(0, value.location.x / geo.size.width), 1)
                                    control.y = min(max(0, value.location.y / geo.size.height), 1)
                                }
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                // open full editor with a class-wrapped copy
                editorModel = EditableDevice(device: device)
            }
            .onDrop(of: [.text], isTargeted: nil) { providers, location in
                if let provider = providers.first {
                    provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                        if let data = item as? Data,
                           let typeString = String(data: data, encoding: .utf8),
                           let type = ControlType(rawValue: typeString) {

                            let new = Control(
                                name: type.rawValue,
                                type: type,
                                x: location.x / geo.size.width,
                                y: location.y / geo.size.height
                            )
                            DispatchQueue.main.async {
                                device.controls.append(new)
                            }
                        }
                    }
                    return true
                }
                return false
            }
        }
        // Present the full editor
        .sheet(item: $editorModel) { editable in
            DeviceEditorView(
                        editableDevice: editable,
                        onCommit: { updated in
                            editorModel = nil
                        },
                        onCancel: {
                            editorModel = nil
                        }
                    )
        }
    }
}
