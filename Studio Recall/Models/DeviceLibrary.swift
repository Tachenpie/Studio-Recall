//
//  DeviceLibrary.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
import Foundation

@MainActor
final class DeviceLibrary: ObservableObject {
    @Published var devices: [Device] = []
    @Published var instances: [DeviceInstance] = []
    @Published var categories: Set<String> = []
    
    private let saveURL: URL
    
    init() {
        let libraryDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = libraryDir.appendingPathComponent("DeviceLibrary.json")
        load()
    }
    
    func device(for id: UUID?) -> Device? {
        guard let id = id else { return nil }
        return devices.first { $0.id == id }
    }
    
    func add(_ device: Device) {
        devices.append(device)
        categories.formUnion(device.categories)
        save()
    }
    
    func update(_ device: Device, sessionManager: SessionManager? = nil) {
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
        categories.formUnion(device.categories)
        save()
        
        sessionManager?.reconcileDevices(with: device)
    }
    
    func delete(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        save()
    }
    
    func delete(_ device: Device) {
        devices.removeAll { $0.id == device.id }
        instances.removeAll { $0.deviceID == device.id }
        save()
    }
    
    func replace(in slots: inout [UUID?], at index: Int, with device: Device) {
        update(device)   // makes sure the library has the latest version
        slots[index] = device.id
        save()
    }
    
    // MARK: Instances
    
    func createInstance(of device: Device) -> DeviceInstance {
        let instance = DeviceInstance(deviceID: device.id)
        instances.append(instance)
        save()
        return instance
    }
    
    func delete(_ instance: DeviceInstance) {
        instances.removeAll { $0.id == instance.id }
        save()
    }
    
    func device(for instance: DeviceInstance?) -> Device? {
        guard let instance else { return nil }
        return devices.first { $0.id == instance.deviceID }
    }
    
    
    // MARK: Persistance
    private struct SaveData: Codable {
        var devices: [Device]
        var instances: [DeviceInstance]
    }
    
    private func save() {
        do {
            let saveData = SaveData(devices: devices, instances: instances)
            let data = try JSONEncoder().encode(saveData)
            try data.write(to: saveURL)
        } catch {
            print("Error saving device library: \(error)")
        }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
       if let decoded = try? JSONDecoder().decode(SaveData.self, from: data) {
           self.devices = decoded.devices
           self.instances = decoded.instances
        }
    }
    
    // MARK: Sorting helpers

    enum GroupingMode {
        case hardwareType   // rack vs 500
        case category       // user-defined tags
    }
    
    @Published var groupingMode: GroupingMode = .hardwareType
    @Published var sortAscending: Bool = true
    
    var allCategories: [String] {
        let sets = devices.flatMap { $0.categories }
        return Array(Set(sets)).sorted()
    }
}
