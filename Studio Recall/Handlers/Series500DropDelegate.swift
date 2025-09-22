//
//  Series500DropDelegate.swift
//  Studio Recall
//
//  Created by True Jackie on 9/17/25.
//
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct Series500DropDelegate: DropDelegate {
	/// EITHER pass a fixed slot index (per-slot .onDrop)
	/// OR provide a mapper from CGPoint -> slot index (chassis-level .onDrop)
	let fixedIndex: Int?
	let indexFor: ((CGPoint) -> Int)?
	
	@Binding var slots: [DeviceInstance?]
	@Binding var hoveredIndex: Int?
	@Binding var hoveredRange: Range<Int>?
	@Binding var hoveredValid: Bool
	
	let library: DeviceLibrary
	var onCommit: (() -> Void)? = nil   // e.g., { sessionManager.saveSessions() }
	
	// MARK: - Helpers
	
	private func targetIndex(from info: DropInfo) -> Int {
		if let f = fixedIndex { return max(0, min(f, max(0, slots.count - 1))) }
		if let map = indexFor { return max(0, min(map(info.location), max(0, slots.count - 1))) }
		return 0
	}
	
	private func width(of device: Device) -> Int { max(1, device.slotWidth ?? 1) }
	
	private func canPlace(range: Range<Int>, ignoring id: UUID?) -> Bool {
		guard range.lowerBound >= 0, range.upperBound <= slots.count else { return false }
		for i in range {
			if let occ = slots[i], occ.id != id { return false }
		}
		return true
	}
	
	private func clearSpan(of instanceId: UUID) {
		guard let start = slots.firstIndex(where: { $0?.id == instanceId }) else { return }
		if let inst = slots[start],
		   let dev = library.device(for: inst.deviceID) {
			let w = width(of: dev)
			for i in start ..< min(start + w, slots.count) { slots[i] = nil }
		} else {
			slots[start] = nil
		}
	}
	
	private func place(_ instance: DeviceInstance, range: Range<Int>) {
		for i in range { slots[i] = instance }
	}
	
	// MARK: - DropDelegate
	
	func validateDrop(info: DropInfo) -> Bool {
		info.hasItemsConforming(to: [UTType.deviceDragPayload])
	}
	
	func dropEntered(info: DropInfo) {
		let idx = targetIndex(from: info)
		hoveredIndex = idx
		hoveredRange = nil
		hoveredValid = false
		
		guard let payload = DragContext.shared.currentPayload,
			  let device  = library.device(for: payload.deviceId) else { return }
		
		let span = idx ..< min(idx + width(of: device), slots.count)
		hoveredRange = span
		hoveredValid = canPlace(range: span, ignoring: payload.instanceId)
	}
	
	func dropUpdated(info: DropInfo) -> DropProposal? {
		guard let payload = DragContext.shared.currentPayload,
			  let device  = library.device(for: payload.deviceId) else {
			let idx = targetIndex(from: info)
			hoveredIndex = idx
			hoveredRange = nil
			hoveredValid = false
			return DropProposal(operation: .copy)
		}
		
		let idx = targetIndex(from: info)
		let span = idx ..< min(idx + width(of: device), slots.count)
		hoveredIndex = idx
		hoveredRange = span
		hoveredValid = canPlace(range: span, ignoring: payload.instanceId)
		
		let op: DropOperation = hoveredValid
		? (payload.instanceId == nil ? .copy : .move)
		: .forbidden
		return DropProposal(operation: op)
	}
	
	func dropExited(info: DropInfo) {
		hoveredIndex = nil
		hoveredRange = nil
		hoveredValid = false
	}
	
	func performDrop(info: DropInfo) -> Bool {
		// Compute index up-front to avoid capturing DropInfo in background callback
		let anchorIndex = targetIndex(from: info)
		
		defer {
			hoveredIndex = nil
			hoveredRange = nil
			hoveredValid = false
			DragContext.shared.endDrag()
		}
		
		guard let provider = info.itemProviders(for: [UTType.deviceDragPayload]).first else { return false }
		
		provider.loadDataRepresentation(forTypeIdentifier: UTType.deviceDragPayload.identifier) { data, _ in
			guard let data,
				  let payload = try? JSONDecoder().decode(DragPayload.self, from: data) else { return }
			
			Task { @MainActor in
				guard let device = library.device(for: payload.deviceId) else { return }
				let span = anchorIndex ..< min(anchorIndex + width(of: device), slots.count)
				guard canPlace(range: span, ignoring: payload.instanceId) else { return }
				
				if let moving = payload.instanceId {
					// MOVE existing (preserve controlStates)
					let instance =
					slots.first(where: { $0?.id == moving }) ??
					library.instances.first(where: { $0.id == moving })
					guard let inst = instance else { return }
					clearSpan(of: moving)
					place(inst, range: span)
				} else {
					// COPY new from library/palette
					let inst = library.createInstance(of: device)
					place(inst, range: span)
				}
				
				onCommit?()
			}
		}
		
		return true
	}
}
