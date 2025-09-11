//
//  SessionManager.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var currentSession: Session? = nil

    private unowned let library: DeviceLibrary
    
    private let saveURL: URL
    private let lastSessionKey = "lastActiveSessionID"

    // ✅ Initialize directly from UserDefaults
    @Published var lastRackSlotCount: Int {
        didSet { UserDefaults.standard.set(lastRackSlotCount, forKey: "lastRackSlotCount") }
    }

    @Published var lastChassisSlotCount: Int {
        didSet { UserDefaults.standard.set(lastChassisSlotCount, forKey: "lastChassisSlotCount") }
    }

    init(library: DeviceLibrary) {
        self.library = library
        
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = documents.appendingPathComponent("sessions.json")

        // Initialize defaults before calling methods
        let savedRack = UserDefaults.standard.integer(forKey: "lastRackSlotCount")
        self.lastRackSlotCount = savedRack > 0 ? savedRack : 8

        let savedChassis = UserDefaults.standard.integer(forKey: "lastChassisSlotCount")
        self.lastChassisSlotCount = savedChassis > 0 ? savedChassis : 10

        loadSessions()
		migrateControlStatesToMatchLibrary()
        restoreLastSession()
    }

    // MARK: - Session lifecycle

    func newSession(name: String, rackSlotCounts: [Int] = [], series500SlotCounts: [Int] = []) {
        let racks = rackSlotCounts.map { Rack(slotCount: $0) }
        let series = series500SlotCounts.enumerated().map { (i, count) in
            Series500Chassis(name: "Chassis \(i+1)", slotCount: count)
        }

        let session = Session(name: name, racks: racks, series500Chassis: series)
        sessions.append(session)
        switchSession(to: session)
        saveSessions()
    }


    func switchSession(to session: Session) {
        currentSession = session
        saveSessions()
        saveLastSessionID(session.id)
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }

        if currentSession?.id == session.id {
            if let first = sessions.first {
                switchSession(to: first)
            } else {
                currentSession = nil
                clearLastSessionID()
            }
        }

        saveSessions()
    }

    // MARK: - Persistence

    func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            print("❌ Failed to save sessions: \(error)")
        }
    }

    func loadSessions() {
        do {
            let data = try Data(contentsOf: saveURL)
            sessions = try JSONDecoder().decode([Session].self, from: data)
            currentSession = sessions.first
        } catch {
            print("ℹ️ No saved sessions found or failed to load: \(error)")
            sessions = []
            currentSession = nil
        }
    }

    // MARK: - Last Session Tracking

    private func saveLastSessionID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: lastSessionKey)
    }

    private func restoreLastSession() {
        if let idString = UserDefaults.standard.string(forKey: lastSessionKey),
           let uuid = UUID(uuidString: idString),
           let match = sessions.first(where: { $0.id == uuid }) {
            currentSession = match
        } else {
            currentSession = sessions.first
        }
    }

    private func clearLastSessionID() {
        UserDefaults.standard.removeObject(forKey: lastSessionKey)
    }
}

extension SessionManager {
    // ✅ add rack with remembered default
    func addRack(slotCount: Int? = nil) {
        guard let session = currentSession else { return }
        let count = slotCount ?? lastRackSlotCount
        lastRackSlotCount = count
        let newRack = Rack(slotCount: count)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].racks.append(newRack)
            currentSession = sessions[idx]
            saveSessions()
        }
    }
    
    // ✅ add chassis with remembered default
    func addSeries500Chassis(name: String = "New Chassis", slotCount: Int? = nil) {
        guard let session = currentSession else { return }
        let count = slotCount ?? lastChassisSlotCount
        lastChassisSlotCount = count
        let newChassis = Series500Chassis(name: name, slotCount: count)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].series500Chassis.append(newChassis)
            currentSession = sessions[idx]
            saveSessions()
        }
    }
}

extension SessionManager {
	func reconcileDevices(with updated: Device) {
		for s in sessions.indices {
			// Clear missing-library devices (existing behavior)
			for r in sessions[s].racks.indices {
				for i in sessions[s].racks[r].slots.indices {
					if var inst = sessions[s].racks[r].slots[i], inst.deviceID == updated.id {
						// re-sync keys
						var map = inst.controlStates
						var changed = false
						
						for control in updated.controls where map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
						let valid = Set(updated.controls.map(\.id))
						let stale = map.keys.filter { !valid.contains($0) }
						if !stale.isEmpty {
							stale.forEach { map.removeValue(forKey: $0) }
							changed = true
						}
						if changed {
							inst.controlStates = map
							sessions[s].racks[r].slots[i] = inst
						}
					}
				}
			}
			for c in sessions[s].series500Chassis.indices {
				for i in sessions[s].series500Chassis[c].slots.indices {
					if var inst = sessions[s].series500Chassis[c].slots[i], inst.deviceID == updated.id {
						var map = inst.controlStates
						var changed = false
						
						for control in updated.controls where map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
						let valid = Set(updated.controls.map(\.id))
						let stale = map.keys.filter { !valid.contains($0) }
						if !stale.isEmpty {
							stale.forEach { map.removeValue(forKey: $0) }
							changed = true
						}
						if changed {
							inst.controlStates = map
							sessions[s].series500Chassis[c].slots[i] = inst
						}
					}
				}
			}
		}
		saveSessions()
	}
}

extension SessionManager {
	/// Place a library device into a rack slot and auto-seed controlStates.
	func placeDevice(_ device: Device, intoRack rackID: UUID, slot: Int) {
		guard let sIdx = sessions.firstIndex(where: { $0.id == currentSession?.id }) else { return }
		guard let rIdx = sessions[sIdx].racks.firstIndex(where: { $0.id == rackID }) else { return }
		guard sessions[sIdx].racks[rIdx].slots.indices.contains(slot) else { return }
		
		let instance = DeviceInstance(deviceID: device.id, device: device)
		sessions[sIdx].racks[rIdx].slots[slot] = instance
		currentSession = sessions[sIdx]
		saveSessions()
	}
	
	/// Place a library device into a 500-series chassis slot and auto-seed controlStates.
	func placeDevice(_ device: Device, intoChassis chassisID: UUID, slot: Int) {
		guard let sIdx = sessions.firstIndex(where: { $0.id == currentSession?.id }) else { return }
		guard let cIdx = sessions[sIdx].series500Chassis.firstIndex(where: { $0.id == chassisID }) else { return }
		guard sessions[sIdx].series500Chassis[cIdx].slots.indices.contains(slot) else { return }
		
		let instance = DeviceInstance(deviceID: device.id, device: device)
		sessions[sIdx].series500Chassis[cIdx].slots[slot] = instance
		currentSession = sessions[sIdx]
		saveSessions()
	}
	
	/// Update a single control value on an instance (rack or chassis), then save.
	func setControlValue(instanceID: UUID, controlID: UUID, to newValue: ControlValue) {
		for s in sessions.indices {
			// Racks
			for r in sessions[s].racks.indices {
				for i in sessions[s].racks[r].slots.indices {
					if var inst = sessions[s].racks[r].slots[i], inst.id == instanceID {
						inst.controlStates[controlID] = newValue
						sessions[s].racks[r].slots[i] = inst
						if sessions[s].id == currentSession?.id { currentSession = sessions[s] }
						saveSessions()
						return
					}
				}
			}
			// 500-series
			for c in sessions[s].series500Chassis.indices {
				for i in sessions[s].series500Chassis[c].slots.indices {
					if var inst = sessions[s].series500Chassis[c].slots[i], inst.id == instanceID {
						inst.controlStates[controlID] = newValue
						sessions[s].series500Chassis[c].slots[i] = inst
						if sessions[s].id == currentSession?.id { currentSession = sessions[s] }
						saveSessions()
						return
					}
				}
			}
		}
	}
	
	/// After decoding sessions, ensure every instance's controlStates match the current library device definition.
	func migrateControlStatesToMatchLibrary() {
		for s in sessions.indices {
			// Racks
			for r in sessions[s].racks.indices {
				for i in sessions[s].racks[r].slots.indices {
					guard var inst = sessions[s].racks[r].slots[i] else { continue }
					guard let device = library.device(for: inst.deviceID) else {
						// device removed from library → drop slot (same behavior as reconcile)
						sessions[s].racks[r].slots[i] = nil
						continue
					}
					var map = inst.controlStates
					var changed = false
					
					// Add any new controls
					for control in device.controls {
						if map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
					}
					// Remove any stale controls
					let valid = Set(device.controls.map(\.id))
					let stale = map.keys.filter { !valid.contains($0) }
					if !stale.isEmpty {
						stale.forEach { map.removeValue(forKey: $0) }
						changed = true
					}
					
					if changed {
						inst.controlStates = map
						sessions[s].racks[r].slots[i] = inst
					}
				}
			}
			// 500-series
			for c in sessions[s].series500Chassis.indices {
				for i in sessions[s].series500Chassis[c].slots.indices {
					guard var inst = sessions[s].series500Chassis[c].slots[i] else { continue }
					guard let device = library.device(for: inst.deviceID) else {
						sessions[s].series500Chassis[c].slots[i] = nil
						continue
					}
					var map = inst.controlStates
					var changed = false
					
					for control in device.controls {
						if map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
					}
					let valid = Set(device.controls.map(\.id))
					let stale = map.keys.filter { !valid.contains($0) }
					if !stale.isEmpty {
						stale.forEach { map.removeValue(forKey: $0) }
						changed = true
					}
					
					if changed {
						inst.controlStates = map
						sessions[s].series500Chassis[c].slots[i] = inst
					}
				}
			}
		}
		// Persist any fixes
		saveSessions()
	}
}

extension SessionManager {
	/// Gather all diffs in the current session vs. library defaults
	func diffsForCurrentSession() -> [InstanceDiff] {
		guard let session = currentSession else { return [] }
		var result: [InstanceDiff] = []
		
		// Racks
		for (rackIndex, rack) in session.racks.enumerated() {
			for (slotIndex, inst) in rack.slots.enumerated() {
				guard let inst = inst,
					  let device = library.device(for: inst.deviceID) else { continue }
				
				let diffs = inst.diffs(vs: device)
				if !diffs.isEmpty {
					result.append(
						InstanceDiff(
							instanceID: inst.id,
							deviceName: device.name,
							location: "Rack \(rackIndex+1) Slot \(slotIndex+1)",
							diffs: diffs
						)
					)
				}
			}
		}
		
		// 500-series chassis
		for (chassisIndex, chassis) in session.series500Chassis.enumerated() {
			for (slotIndex, inst) in chassis.slots.enumerated() {
				guard let inst = inst,
					  let device = library.device(for: inst.deviceID) else { continue }
				
				let diffs = inst.diffs(vs: device)
				if !diffs.isEmpty {
					result.append(
						InstanceDiff(
							instanceID: inst.id,
							deviceName: device.name,
							location: "Chassis \(chassisIndex+1) Slot \(slotIndex+1)",
							diffs: diffs
						)
					)
				}
			}
		}
		
		return result
	}
}

// MARK: - Save/Export Current Session (macOS)
#if os(macOS)
import AppKit
import UniformTypeIdentifiers

extension SessionManager {
	/// Saves the whole app sessions.json as-is (you already have this).
	func saveAll() {
		saveSessions()
	}
	
	/// Export only the current session via Save Panel as JSON.
	func saveCurrentSessionAs() {
		guard let session = currentSession else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [UTType.json]
		panel.nameFieldStringValue = "\(session.name).session.json"
		if panel.runModal() == .OK, let url = panel.url {
			do {
				let data = try JSONEncoder().encode(session)
				try data.write(to: url, options: [.atomic])
			} catch {
				print("❌ Export failed: \(error)")
			}
		}
	}
	
	/// Export current session as a "template" JSON (same structure, different default name).
	func saveCurrentSessionAsTemplate() {
		guard let session = currentSession else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [UTType.json]
		panel.nameFieldStringValue = "\(session.name).template.json"
		if panel.runModal() == .OK, let url = panel.url {
			do {
				let data = try JSONEncoder().encode(session)
				try data.write(to: url, options: [.atomic])
			} catch {
				print("❌ Template export failed: \(error)")
			}
		}
	}
}
#endif


// MARK: - Session Commands
struct SessionCommands: Commands {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingNewSession: Bool
    @Binding var showingAddRack: Bool
    @Binding var showingAddChassis: Bool
	@Binding var showingReviewChanges: Bool
	@Binding var showingSaveOptions: Bool

	var body: some Commands {
		CommandMenu("Session") {
			Button("New Session…") { showingNewSession = true }
				.keyboardShortcut("n", modifiers: [.command])
			
			Divider()
			
			Button("Add Rack…") { showingAddRack = true }
				.keyboardShortcut("r", modifiers: [.command, .shift])
			
			Button("Add 500 Series Chassis…") { showingAddChassis = true }
				.keyboardShortcut("c", modifiers: [.command, .shift])
			
			Divider()
			
			// Not-intrusive diffs viewer
			Button("Review Changes…") {
				showingReviewChanges = true
			}
			.keyboardShortcut("d", modifiers: [.command, .shift])
			
			// One dialog with three choices (Save / Save As / Save As Template)
			Button("Save Options…") {
				showingSaveOptions = true
			}
			.keyboardShortcut("s", modifiers: [.command])
			
			if !sessionManager.sessions.isEmpty {
				Divider()
				Text("Recent Sessions")
				ForEach(sessionManager.sessions) { session in
					Menu(session.name) {
						Button("Open") {
							sessionManager.switchSession(to: session)
						}
						.disabled(sessionManager.currentSession?.id == session.id)
						
						Divider()
						
						Menu("Delete…") {
							Button("Cancel", role: .cancel) { }
							Button("Confirm Delete", role: .destructive) {
								sessionManager.deleteSession(session)
							}
						}
					}
				}
			}
		}
	}
}
