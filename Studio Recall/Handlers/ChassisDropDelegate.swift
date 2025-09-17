//
//  ChassisDropDelegate.swift
//  Studio Recall
//

//
//  ChassisDropDelegate.swift
//  Studio Recall
//

import SwiftUI
import UniformTypeIdentifiers

struct ChassisDropDelegate: DropDelegate {
	// EITHER pass currentIndex (per-slot usage) OR indexFor (chassis-level usage)
	let currentIndex: Int?
	let indexFor: ((CGPoint) -> Int)?
	
	@Binding var slots: [DeviceInstance?]
	@Binding var hoveredIndex: Int?
	@Binding var hoveredValid: Bool
	@Binding var hoveredRange: Range<Int>?
	
	let library: DeviceLibrary
	let measure: (Device) -> Int?
	let kind: DeviceType
	var onCommit: (() -> Void)? = nil   // optional: e.g. { sessionManager.saveSessions() }
	
	// MARK: - Helpers
	
	private func index(from info: DropInfo) -> Int {
		if let i = currentIndex { return i }
		if let f = indexFor { return max(0, f(info.location)) }
		return 0
	}
	
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
			if let occ = slots[i], occ.id == instanceID { slots[i] = nil }
		}
	}
	
	// MARK: - DropDelegate
	
	func validateDrop(info: DropInfo) -> Bool {
		info.hasItemsConforming(to: [UTType.deviceDragPayload])
	}
	
	func dropEntered(info: DropInfo) {
		let idx = index(from: info)
		hoveredIndex = idx
		hoveredValid = false
		hoveredRange = nil
		
		guard let payload = DragContext.shared.currentPayload,
			  let device  = library.device(for: payload.deviceId),
			  isValidType(device) else { return }
		
		let units = measure(device) ?? 1
		let start = min(idx, max(0, slots.count - 1))
		let end   = min(start + units, slots.count)
		let range = start..<end
		
		hoveredValid = canPlace(range: range, ignoring: payload.instanceId)
		hoveredRange = range
	}
	
	func dropUpdated(info: DropInfo) -> DropProposal? {
		guard let payload = DragContext.shared.currentPayload,
			  let device  = library.device(for: payload.deviceId),
			  isValidType(device) else {
			hoveredIndex = index(from: info)
			hoveredRange = nil
			hoveredValid = false
			return DropProposal(operation: .copy)
		}
		
		let idx   = index(from: info)
		let units = measure(device) ?? 1
		let start = max(0, min(idx, slots.count - 1))
		let end   = min(start + units, slots.count)
		let range = start..<end
		
		hoveredIndex = idx
		hoveredRange = range
		hoveredValid = canPlace(range: range, ignoring: payload.instanceId)
		
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
				  let payload = try? JSONDecoder().decode(DragPayload.self, from: data),
				  let device  = library.device(for: payload.deviceId),
				  isValidType(device) else { return }
			
			Task { @MainActor in
				let idx   = index(from: info)
				let units = measure(device) ?? 1
				let start = max(0, min(idx, slots.count - 1))
				let end   = min(start + units, slots.count)
				let range = start..<end
				
				guard canPlace(range: range, ignoring: payload.instanceId) else { return }
				
				if let movingId = payload.instanceId {
					// MOVE: reuse existing instance (preserve controlStates)
					guard let instance =
							slots.first(where: { $0?.id == movingId }) ??
							library.instances.first(where: { $0.id == movingId })
					else { return }
					
					// clear old span if currently placed
					if let oldIndex = slots.firstIndex(where: { $0?.id == movingId }),
					   let oldDev   = library.device(for: instance.deviceID) {
						let oldUnits = measure(oldDev) ?? 1
						for i in oldIndex ..< min(oldIndex + oldUnits, slots.count) { slots[i] = nil }
					}
					
					// place same instance at new span
					for i in range { slots[i] = nil }
					slots[start] = instance
					
				} else {
					// COPY: new instance from library/palette
					let instance = library.createInstance(of: device)
					for i in range { slots[i] = nil }
					slots[start] = instance
				}
				
				onCommit?() // e.g. saveSessions()
			}
		}
		
		return true
	}
}
