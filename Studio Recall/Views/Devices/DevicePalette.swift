//
//  DevicePalette.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import UniformTypeIdentifiers
import SwiftUI

struct DevicePalette: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary
    
    var body: some View {
        VStack {
            HStack {
                Text("Device Library")
                    .font(.headline)
                Spacer()
                Button("+") {
                    // open DeviceEditorView in a sheet
                }
            }
            
            List {
                ForEach(library.devices) { device in
                    Text(device.name)
                        .onDrag {
                            if let data = try? JSONEncoder().encode(device.id) {
                                let provider = NSItemProvider()
                                provider.registerDataRepresentation(forTypeIdentifier: UTType.deviceID.identifier,
                                                                    visibility: .all) { completion in
                                    completion(data, nil)
                                    return nil
                                }
                                return provider
                            }
                            return NSItemProvider()
                        }

                }
                .onDelete(perform: library.delete)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
}
