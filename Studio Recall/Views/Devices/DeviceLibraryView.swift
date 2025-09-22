//
//  DeviceLibraryView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import UniformTypeIdentifiers
import SwiftUI

enum DeviceSheet: Identifiable {
    case chooser
    case editor(EditableDevice)
    
    var id: String {
        switch self {
        case .chooser:
            return "chooser"
        case .editor:
            return "editor"
        }
    }
}

struct DeviceLibraryView: View {
    @EnvironmentObject var library: DeviceLibrary
    @State private var editingDevice: EditableDevice? = nil
    @State private var activeSheet: DeviceSheet? = nil

    var body: some View {
        var groupedDevices: [(String, [Device])] {
            switch library.groupingMode {
            case .hardwareType:
                let groups = Dictionary(grouping: library.devices) { $0.type.displayName }
                return groups
                    .map { (key, value) in
                        (key, value.sorted { library.sortAscending ? $0.name < $1.name: $0.name > $1.name})
                    }
                    .sorted { $0.0 < $1.0 }
            case .category:
                let groups = Dictionary(grouping: library.devices) { device in
                    device.categories.isEmpty ? "Uncategorized" : device.categories.first!
                }
                return groups
                    .map { (key, value) in
                        (key, value.sorted { library.sortAscending ? $0.name < $1.name: $0.name > $1.name})
                    }
                    .sorted { $0.0 < $1.0 }
            }
        }
        List {
            ForEach(groupedDevices, id: \.0) { group, devices in
                Section(header: Text(group)) {
                    ForEach(devices) { device in
                        deviceRow(for: device)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeSheet = .editor(EditableDevice(device: device))
                            }
                    }
                    .onDelete { indexSet in
                        indexSet.map { library.devices[$0] }
                            .forEach(library.delete)
                    }
                }
            }
        }
        .navigationTitle("Device Library")
        .toolbar {
            ToolbarItemGroup() { //placement: .primaryAction) {
                    Menu {
                        Picker("Group By", selection: $library.groupingMode) {
                            Text("Hardware Type").tag(DeviceLibrary.GroupingMode.hardwareType)
                            Text("Category").tag(DeviceLibrary.GroupingMode.category)
                        }
                    } label: {
                        Image(systemName: "info.circle")
                    }

                    Button {
                        library.sortAscending.toggle()
                    } label: {
                        Image(systemName: library.sortAscending ? "arrow.up" : "arrow.down")
                    }
                    Button {
                        activeSheet = .chooser
                    } label: {
                        Label("Create New Device", systemImage: "plus")
                    }
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
                                        onCommit: { device in
                                            if library.devices.contains(where: { $0.id == device.id }) {
                                                library.update(device)
                                            } else {
                                                library.add(device)
                                            }
                                            activeSheet = nil
                                        },
                                        onCancel: { activeSheet = nil }
                                    )
                                }
                                .frame(minWidth: 1000, minHeight: 400)
                            }
        }
    }

    // MARK: - Device Row
    private func deviceRow(for device: Device) -> some View {
        VStack(spacing: 6) {
            // --- Device Preview (draggable visual) ---
            DeviceView(device: device)
                .frame(width: 80, height: 40)
                .shadow(radius: 3)

            // --- Metadata below preview ---
            VStack(spacing: 2) {
                Text(device.name)
                    .font(.caption)
					.foregroundColor(.secondary)
					.fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)

				if device.type == .rack {
					Text("\(device.rackUnits ?? 1)U, \(device.rackWidth.label) Rack")
					.font(.caption)
					.fontWeight(.medium)
				} else {
					Text("\(device.slotWidth ?? 1) slots")
						.font(.caption)
				}
					
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(HoverHighlight())
        .cornerRadius(8)
        .contentShape(Rectangle())
		.onDrag {
			let payload = DragPayload(deviceId: device.id)
			DragContext.shared.beginDrag(payload: payload)
			
			let provider = NSItemProvider()
			// primary custom type
			provider.registerDataRepresentation(
				forTypeIdentifier: UTType.deviceDragPayload.identifier,
				visibility: .all
			) { completion in
				completion(try? JSONEncoder().encode(payload), nil); return nil
			}
			// fallbacks
			provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .all) { completion in
				completion(Data(), nil); return nil
			}
			provider.registerDataRepresentation(forTypeIdentifier: UTType.item.identifier, visibility: .all) { completion in
				completion(Data(), nil); return nil
			}
			provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
				completion(Data("device".utf8), nil); return nil
			}
			
//			print("📦 onDrag start – device=\(device.name) utis=\(provider.registeredTypeIdentifiers)")
			return provider
		} preview: {
			DeviceView(device: device)
//				.frame(width: 80, height: 40)
				.shadow(radius: 4)
		}
    }

    // MARK: - Editor Sheet
    @ViewBuilder
    private func editorSheet(for editableDevice: EditableDevice) -> some View {
        NavigationStack {
            DeviceEditorView(
                editableDevice: editableDevice,
                onCommit: { newDevice in
                    if library.devices.contains(where: { $0.id == newDevice.id }) {
                        library.update(newDevice)
                    } else {
                        library.add(newDevice)
                    }
                    editingDevice = nil // dismiss
                },
                onCancel: {
                    editingDevice = nil // dismiss
                }
            )
        }
    }
    
    private func groupedDevices() -> [(String, [Device])] {
        let devices = library.devices.sorted {
            library.sortAscending
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
        }

        switch library.groupingMode {
        case .hardwareType:
            return Dictionary(grouping: devices) { $0.type.displayName }
                .map { ($0.key, $0.value) }
                .sorted { $0.0 < $1.0 }

        case .category:
            var grouped: [String: [Device]] = [:]
            for device in devices {
                if device.categories.isEmpty {
                    grouped["Uncategorized", default: []].append(device)
                } else {
                    for category in device.categories {
                        grouped[category, default: []].append(device)
                    }
                }
            }
            return grouped
                .map { ($0.key, $0.value) }
                .sorted { $0.0 < $1.0 }
        }
    }

}
