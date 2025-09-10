//
//  LibraryManagerView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct LibraryManagerView: View {
    @EnvironmentObject var library: DeviceLibrary
    @State private var selection: Device.ID? = nil
    @State private var activeSheet: DeviceSheet? = nil

    private var selectedDevice: Device? {
        library.devices.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selection) {
                ForEach(library.devices) { device in
                    DeviceSidebarRow(device: device)
                        .tag(device.id as Device.ID?)
                }
                .onDelete { indexSet in
                    indexSet.map { library.devices[$0] }.forEach(library.delete)
                    if let selected = selection,
                       !library.devices.contains(where: { $0.id == selected }) {
                        selection = nil
                    }
                }
            }
            .navigationTitle("Device Library")
            .frame(minWidth: 220)
        } detail: {
            // Detail view
            Group {
                if let device = selectedDevice {
                    VStack(spacing: 12) {
                        FaceplatePreview(device: device)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary, lineWidth: 0.5))
                        
                        DeviceEditorView(
                            editableDevice: EditableDevice(device: device),
                            onCommit: { updated in
                            library.update(updated)
                            }, onCancel: { activeSheet = nil }
                            )
                        .padding()
                    }
                }
                 else {
                    VStack {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 10)
                        Text("Select a device to edit, or add a new one.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    activeSheet = .chooser
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button(role: .destructive) {
                    if let device = selectedDevice {
                        library.delete(device)
                        selection = nil
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedDevice == nil)
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .chooser:
                NewDeviceChooser { newDevice in
                    activeSheet = .editor(EditableDevice(device: newDevice))
                }
            case .editor(let editable):
                NavigationStack {
                    DeviceEditorView(
                        editableDevice: editable,
                        onCommit: { newDevice in
                            if library.devices.contains(where: { $0.id == newDevice.id }) {
                                library.update(newDevice)
                            } else {
                                library.add(newDevice)
                            }
                            activeSheet = nil
                        },
                        onCancel: { activeSheet = nil }
                    )
                    .padding()
                    .navigationTitle("New Device")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { activeSheet = nil }
                        }
                    }
                }
                .frame(minWidth: 500, minHeight: 400)
            }
        }
    }
}
