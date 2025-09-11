//
//  ChassisDropDelegate.swift
//  Studio Recall
//

import SwiftUI
import UniformTypeIdentifiers

struct ChassisDropDelegate: DropDelegate {
    let currentIndex: Int
    @Binding var slots: [DeviceInstance?]

    @Binding var hoveredIndex: Int?
    @Binding var hoveredValid: Bool
    @Binding var hoveredRange: Range<Int>?

    let library: DeviceLibrary
    let measure: (Device) -> Int?
    let kind: DeviceType

    func validateDrop(info: DropInfo) -> Bool {
		print("validate drop")
		print(info)
        return info.hasItemsConforming(to: [UTType.deviceDragPayload])
    }

    func dropEntered(info: DropInfo) {
        hoveredIndex = currentIndex
        hoveredValid = false
        hoveredRange = nil

        guard let payload = DragContext.shared.currentPayload,
              let device = library.device(for: payload.deviceId),
              device.type == kind else { return }
        
          let units = measure(device) ?? 1
        print(units)
        print(device.name)
        let range = currentIndex ..< (currentIndex + units)
        hoveredValid = canPlace(range: range, ignoring: payload.instanceId)
        hoveredRange = range
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Use the cached payload set in onDrag (DeviceLibraryView / slot views)
        guard let payload = DragContext.shared.currentPayload,
              let device  = library.device(for: payload.deviceId) else {
            // Fall back to a conservative default if we can't resolve the payload yet
            return DropProposal(operation: .copy)
        }

        // Type guard (rack vs 500-series)
        guard isValidType(device) else {
            hoveredIndex = currentIndex
            hoveredRange = nil
            hoveredValid = false
            return DropProposal(operation: .forbidden)
        }

        // Compute the prospective range at this hover index
        let units = measure(device) ?? 1
        let start = max(0, min(currentIndex, slots.count - 1))
        let end   = min(start + units, slots.count)
        let range = start..<end

        // Update hover state synchronously
        hoveredIndex = currentIndex
        hoveredRange = range
        hoveredValid = canPlace(range: range, ignoring: payload.instanceId)

        // Choose operation: copy (from library) vs move (existing instance)
        let op: DropOperation = hoveredValid
            ? (payload.instanceId == nil ? .copy : .move)
            : .forbidden

        return DropProposal(operation: op)
    }


    func dropExited(info: DropInfo) {
        hoveredIndex = nil
        hoveredValid = false
        hoveredRange = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            hoveredIndex = nil
            hoveredValid = false
            hoveredRange = nil
            DragContext.shared.endDrag()
        }

        guard let provider = info.itemProviders(for: [UTType.deviceDragPayload]).first else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.deviceDragPayload.identifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(DragPayload.self, from: data) else { return }
            
            Task { @MainActor in
                switch payload.source {
                case .library:
                    // New device, create new instance
                    if let device = library.device(for: payload.deviceId) {
                        let units = measure(device) ?? 1
                        let instance = library.createInstance(of: device)
                        let range = currentIndex ..< (currentIndex + units)
                        guard canPlace(range: range) else { return }
                        place(instance, in: range)
                    }
                case .instance:
                    // Move existing
                    if let instanceId = payload.instanceId,
                       let instance = slots.first(where: { $0?.id == instanceId }) ?? library.instances.first(where: { $0.id == instanceId }),
                       let device = library.device(for: instance.deviceID) {
                        let units = measure(device) ?? 1
                        let range = currentIndex ..< (currentIndex + units)
                        guard canPlace(range: range, ignoring: instanceId) else { return }
                        clear(instanceID: instanceId)
                        place(instance, in: range)
                    }
                }
            }
        }
        DragContext.shared.endDrag()
        return true
    }

    // MARK: - Helpers

    private func isValidType(_ device: Device) -> Bool {
        device.type == kind
    }

    private func canPlace(range: Range<Int>, ignoring ignoreID: UUID? = nil) -> Bool {
        guard range.lowerBound >= 0, range.upperBound <= slots.count else { return false }
        for i in range {
            if let occ = slots[i], occ.id != ignoreID { return false }
        }
        return true
    }

    private func place(_ instance: DeviceInstance, in range: Range<Int>) {
        for i in range { slots[i] = instance }
    }

    private func clear(instanceID: UUID) {
        for i in slots.indices {
            if let occ = slots[i], occ.id == instanceID {
                slots[i] = nil
            }
        }
    }
}
