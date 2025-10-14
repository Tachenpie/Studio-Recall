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
	@Published var templates: [SessionTemplate] = []
	@Published var defaultTemplateId: UUID? {
		didSet { UserDefaults.standard.set(defaultTemplateId?.uuidString, forKey: "DefaultTemplateID") }
	}
	@Published var currentSessionFileURL: URL? = nil  // Track file location for Save

	@Published var showTemplateManager: Bool = false
	@Published var renderStyle: RenderStyle {
		didSet { UserDefaults.standard.set(renderStyle.rawValue, forKey: "renderStyle") }
	}
	
	/// Convenience to find current session index quickly.
	var currentSessionIndex: Int? {
		guard let id = currentSession?.id else { return nil }
		return sessions.firstIndex(where: { $0.id == id })
	}
	
    private unowned let library: DeviceLibrary
    
    private let saveURL: URL
    private let lastSessionKey = "lastActiveSessionID"
	private var appSupportURL: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
#if os(macOS)
		let bundleID = Bundle.main.bundleIdentifier ?? "Studio Recall"
#else
		let bundleID = "Studio Recall"
#endif
		return base.appendingPathComponent(bundleID, isDirectory: true)
	}

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

		let raw = UserDefaults.standard.string(forKey: "renderStyle")
		self.renderStyle = RenderStyle(rawValue: raw ?? "") ?? .photoreal
		
        loadSessions()
		loadTemplates()
		if let raw = UserDefaults.standard.string(forKey: "DefaultTemplateID"),
		   let id = UUID(uuidString: raw) {
			defaultTemplateId = id
		}
		migrateControlStatesToMatchLibrary()
        restoreLastSession()
    }

    // MARK: - Session lifecycle
    func newSession(name: String, rackRowCounts: [Int] = [], series500SlotCounts: [Int] = []) {
        let racks = rackRowCounts.map { Rack(rows: $0) }
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

// MARK: - Rack grid helpers (rows × 6)
private extension SessionManager {
	/// Width in grid columns for a device (full=6, half=3, third=2).
	func spanCols(for device: Device) -> Int { max(1, device.rackWidth.rawValue) }
	
	/// Height in rows (U) for a device.
	func spanRows(for device: Device) -> Int { max(1, device.rackUnits ?? 1) }
	
	/// True if (r,c) is the top-left anchor of this instance in the grid.
	func isAnchor(_ rack: Rack, instanceId: UUID, r: Int, c: Int) -> Bool {
		guard rack.slots.indices.contains(r),
			  (0..<RackGrid.columnsPerRow).contains(c),
			  rack.slots[r][c]?.id == instanceId else { return false }
		let topFree  = (r == 0) || (rack.slots[r-1][c]?.id != instanceId)
		let leftFree = (c == 0) || (rack.slots[r][c-1]?.id != instanceId)
		return topFree && leftFree
	}
	
	/// Returns the anchor (r,c) for the first occurrence of an instance in a rack.
	func anchor(of instanceId: UUID, in rack: Rack) -> (Int, Int)? {
		for r in rack.slots.indices {
			for c in 0..<RackGrid.columnsPerRow where rack.slots[r][c]?.id == instanceId {
				if isAnchor(rack, instanceId: instanceId, r: r, c: c) { return (r,c) }
			}
		}
		return nil
	}
	
	/// Writes an instance into its full span starting at (r0,c0).
	func writeSpan(_ instance: DeviceInstance, device: Device, inSession s: Int, rackIndex: Int, r0: Int, c0: Int) {
		let rows = spanRows(for: device)
		let cols = spanCols(for: device)
		let rMax = min(r0 + rows, sessions[s].racks[rackIndex].slots.count)
		let cMax = min(c0 + cols, RackGrid.columnsPerRow)
		for r in r0..<rMax {
			for c in c0..<cMax {
				sessions[s].racks[rackIndex].slots[r][c] = instance
			}
		}
	}
	
	/// Clears a previously placed span for an instance (no-op if not placed).
	func clearSpan(of instanceId: UUID, inSession s: Int, rackIndex: Int) {
		for r in sessions[s].racks[rackIndex].slots.indices {
			for c in 0..<RackGrid.columnsPerRow {
				if sessions[s].racks[rackIndex].slots[r][c]?.id == instanceId {
					sessions[s].racks[rackIndex].slots[r][c] = nil
				}
			}
		}
	}
}

extension SessionManager {
    // ✅ add rack with remembered default and optional name
    func addRack(rows: Int? = nil, name: String? = nil) {
        guard let session = currentSession else { return }
        let count = rows ?? lastRackSlotCount
        lastRackSlotCount = count
        var newRack = Rack(rows: count)
        newRack.name = name
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].racks.append(newRack)
            currentSession = sessions[idx]
            saveSessions()
        }
    }
    
    // ✅ add chassis with remembered default and optional name
    func addSeries500Chassis(name: String? = nil, slotCount: Int? = nil) {
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

	// ✅ add pedalboard with default dimensions
	func addPedalboard(name: String? = nil, widthInches: Double = 24, heightInches: Double = 12) {
		guard let session = currentSession else { return }
		let newPedalboard = Pedalboard(name: name, widthInches: widthInches, heightInches: heightInches)
		if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
			sessions[idx].pedalboards.append(newPedalboard)
			currentSession = sessions[idx]
			saveSessions()
		}
	}
}

extension SessionManager {
	func reconcileDevices(with updated: Device) {
		for s in sessions.indices {
			// Racks (2D)
			for r in sessions[s].racks.indices {
				for row in sessions[s].racks[r].slots.indices {
					for col in 0..<RackGrid.columnsPerRow {
						guard var inst = sessions[s].racks[r].slots[row][col],
							  inst.deviceID == updated.id,
							  isAnchor(sessions[s].racks[r], instanceId: inst.id, r: row, c: col)
						else { continue }
						
						var map = inst.controlStates
						var changed = false
						
						// add any new controls
						for control in updated.controls where map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
						// remove stale controls
						let valid = Set(updated.controls.map(\.id))
						let stale = map.keys.filter { !valid.contains($0) }
						if !stale.isEmpty {
							stale.forEach { map.removeValue(forKey: $0) }
							changed = true
						}
						
						if changed {
							inst.controlStates = map
							// fan out to the entire span
							writeSpan(inst, device: updated, inSession: s, rackIndex: r, r0: row, c0: col)
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
	/// NEW: place by (row,col) anchor; fills the span.
	func placeDevice(_ device: Device, intoRack rackID: UUID, row: Int, col: Int) {
		guard let sIdx = sessions.firstIndex(where: { $0.id == currentSession?.id }) else { return }
		guard let rIdx = sessions[sIdx].racks.firstIndex(where: { $0.id == rackID }) else { return }
		
		let rows = spanRows(for: device)
		let cols = spanCols(for: device)
		guard sessions[sIdx].racks[rIdx].slots.indices.contains(row),
			  (0..<RackGrid.columnsPerRow).contains(col),
			  row + rows <= sessions[sIdx].racks[rIdx].slots.count,
			  col + cols <= RackGrid.columnsPerRow else { return }
		
		let instance = DeviceInstance(deviceID: device.id, device: device)
		// clear & place
		for r in row..<(row+rows) {
			for c in col..<(col+cols) {
				sessions[sIdx].racks[rIdx].slots[r][c] = nil
			}
		}
		for r in row..<(row+rows) {
			for c in col..<(col+cols) {
				sessions[sIdx].racks[rIdx].slots[r][c] = instance
			}
		}
		currentSession = sessions[sIdx]
		saveSessions()
	}
	
	/// OLD: back-compat — interpret `slot` as a row anchor; place at col 0 spanning width.
	@available(*, deprecated, message: "Use placeDevice(_:intoRack:row:col:) for 2D racks.")
	func placeDevice(_ device: Device, intoRack rackID: UUID, slot: Int) {
		placeDevice(device, intoRack: rackID, row: slot, col: 0)
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
				if let (row, col) = anchor(of: instanceID, in: sessions[s].racks[r]),
				   var inst = sessions[s].racks[r].slots[row][col],
				   let device = library.device(for: inst.deviceID) {
					
					inst.controlStates[controlID] = newValue
					writeSpan(inst, device: device, inSession: s, rackIndex: r, r0: row, c0: col)
					
					if sessions[s].id == currentSession?.id { currentSession = sessions[s] }
					saveSessions()
					return
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
				for row in sessions[s].racks[r].slots.indices {
					for col in 0..<RackGrid.columnsPerRow {
						guard var inst = sessions[s].racks[r].slots[row][col],
							  isAnchor(sessions[s].racks[r], instanceId: inst.id, r: row, c: col)
						else { continue }
						
						guard let device = library.device(for: inst.deviceID) else {
							// device removed from library → drop this span
							sessions[s].racks[r].slots[row][col] = nil
							continue
						}
						
						var map = inst.controlStates
						var changed = false
						
						for control in device.controls where map[control.id] == nil {
							map[control.id] = ControlValue.initialValue(for: control)
							changed = true
						}
						let valid = Set(device.controls.map(\.id))
						let stale = map.keys.filter { !valid.contains($0) }
						if !stale.isEmpty {
							stale.forEach { map.removeValue(forKey: $0) }
							changed = true
						}
						
						if changed {
							inst.controlStates = map
							writeSpan(inst, device: device, inSession: s, rackIndex: r, r0: row, c0: col)
						}
					}
				}
			}
			
			// 500-series
			for c in sessions[s].series500Chassis.indices {
				for i in sessions[s].series500Chassis[c].slots.indices {
					guard let inst = sessions[s].series500Chassis[c].slots[i] else { continue }
					guard let device = library.device(for: inst.deviceID) else {
						sessions[s].series500Chassis[c].slots[i] = nil
						continue
					}
					var map = inst.controlStates
					var changed = false
					for control in device.controls where map[control.id] == nil {
						map[control.id] = ControlValue.initialValue(for: control)
						changed = true
					}
					let valid = Set(device.controls.map(\.id))
					let stale = map.keys.filter { !valid.contains($0) }
					if !stale.isEmpty {
						stale.forEach { map.removeValue(forKey: $0) }
						changed = true
					}
					if changed { sessions[s].series500Chassis[c].slots[i] = inst }
				}
			}
		}
		saveSessions()
	}

}

extension SessionManager {
	/// Gather all diffs in the current session vs. library defaults
	func diffsForCurrentSession() -> [InstanceDiff] {
		guard let session = currentSession else { return [] }
		var result: [InstanceDiff] = []
		
		// Racks (list anchors only)
		for (rackIndex, rack) in session.racks.enumerated() {
			for r in rack.slots.indices {
				for c in 0..<RackGrid.columnsPerRow {
					guard let inst = rack.slots[r][c],
						  isAnchor(rack, instanceId: inst.id, r: r, c: c),
						  let device = library.device(for: inst.deviceID) else { continue }
					
					let diffs = inst.diffs(vs: device)
					if !diffs.isEmpty {
						result.append(
							InstanceDiff(
								instanceID: inst.id,
								deviceName: device.name,
								location: "Rack \(rackIndex+1) Row \(r+1) Col \(c+1)",
								diffs: diffs
							)
						)
					}
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
	/// Open a session from a file
	func openSession(from url: URL) {
		do {
			guard url.startAccessingSecurityScopedResource() else {
				print("❌ Could not access security-scoped resource at: \(url.path)")
				return
			}
			defer { url.stopAccessingSecurityScopedResource() }

			print("📂 Opening session from: \(url.path)")
			let data = try Data(contentsOf: url)
			print("📊 Read \(data.count) bytes")

			let decoder = JSONDecoder()
			let session = try decoder.decode(Session.self, from: data)
			print("✅ Successfully decoded session: \(session.name)")

			// Update or add to sessions list
			if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
				sessions[idx] = session
			} else {
				sessions.append(session)
			}

			currentSession = session
			currentSessionFileURL = url
			saveSessions()  // Save to internal list

			print("✅ Session opened and set as current")
		} catch let error as DecodingError {
			print("❌ JSON Decoding Error: \(error)")
			switch error {
			case .keyNotFound(let key, let context):
				print("  Missing key '\(key.stringValue)' - \(context.debugDescription)")
			case .typeMismatch(let type, let context):
				print("  Type mismatch for type \(type) - \(context.debugDescription)")
			case .valueNotFound(let type, let context):
				print("  Value not found for type \(type) - \(context.debugDescription)")
			case .dataCorrupted(let context):
				print("  Data corrupted - \(context.debugDescription)")
			@unknown default:
				print("  Unknown decoding error")
			}
		} catch {
			print("❌ Failed to open session: \(error.localizedDescription)")
		}
	}

	/// Save current session to its file location (if it has one)
	func saveCurrentSessionToFile() -> Bool {
		guard let session = currentSession,
			  let url = currentSessionFileURL else {
			return false
		}

		do {
			let data = try JSONEncoder().encode(session)
			try data.write(to: url, options: [.atomic])
			return true
		} catch {
			print("❌ Failed to save session: \(error)")
			return false
		}
	}
}
#endif

// MARK: - Immediate, visible update + persist
extension SessionManager {
	func updateValueAndSave(instanceID: UUID, controlID: UUID, to newValue: ControlValue) {
		// Try racks (rows × cols)
		for s in sessions.indices {
			for r in sessions[s].racks.indices {
				if let (row, col) = anchor(of: instanceID, in: sessions[s].racks[r]),
				   var inst = sessions[s].racks[r].slots[row][col],
				   let device = library.device(for: inst.deviceID) {
					
					// update value
					inst.controlStates[controlID] = newValue
					
					// write back across the full span for this device
					writeSpan(inst, device: device, inSession: s, rackIndex: r, r0: row, c0: col)
					
					// keep currentSession in sync + persist
					if sessions[s].id == currentSession?.id { currentSession = sessions[s] }
					saveSessions()
					return
				}
			}
			
			// Try 500-series (still 1D)
			for c in sessions[s].series500Chassis.indices {
				for i in sessions[s].series500Chassis[c].slots.indices {
					if var inst = sessions[s].series500Chassis[c].slots[i],
					   inst.id == instanceID {
						
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
}

extension SessionManager {
	/// Mount a 500-series chassis into a rack at a specific row
	/// Requires 3U of vertical space. Returns true if successful.
	func mount500SeriesIntoRack(chassisID: UUID, targetRackID: UUID, startRow: Int) -> Bool {
		guard let s = currentSessionIndex else { return false }
		guard let chassisIdx = sessions[s].series500Chassis.firstIndex(where: { $0.id == chassisID }) else { return false }
		guard let rackIdx = sessions[s].racks.firstIndex(where: { $0.id == targetRackID }) else { return false }

		let rack = sessions[s].racks[rackIdx]

		// Check if we have 3U of space starting at startRow
		let requiredRows = 3

		// First try the requested row
		if startRow + requiredRows <= rack.rows {
			var spaceAvailable = true
			for r in startRow..<(startRow + requiredRows) {
				for c in 0..<RackGrid.columnsPerRow {
					if rack.slots[r][c] != nil {
						spaceAvailable = false
						break
					}
				}
				if !spaceAvailable { break }
			}

			if spaceAvailable {
				// Space is available at requested row - mount here
				sessions[s].series500Chassis[chassisIdx].mountedInRack = targetRackID
				sessions[s].series500Chassis[chassisIdx].mountedAtRow = startRow

				// Update the chassis position to match where it will be visually displayed
				// This prevents jump when starting a drag
				updateChassisPositionForMount(chassisIdx: chassisIdx, rackIdx: rackIdx, startRow: startRow, sessionIdx: s)

				// Block the rack slots with a special placeholder
				let chassisID = sessions[s].series500Chassis[chassisIdx].id
				blockRackSlotsForMountedChassis(chassisID: chassisID, rackIdx: rackIdx, startRow: startRow, sessionIdx: s)

				currentSession = sessions[s]
				saveSessions()
				return true
			}
		}

		// Requested row didn't work, search for any 3U space
		for tryRow in 0...(rack.rows - requiredRows) {
			var spaceAvailable = true
			for r in tryRow..<(tryRow + requiredRows) {
				for c in 0..<RackGrid.columnsPerRow {
					if rack.slots[r][c] != nil {
						spaceAvailable = false
						break
					}
				}
				if !spaceAvailable { break }
			}

			if spaceAvailable {
				// Found space at this row
				sessions[s].series500Chassis[chassisIdx].mountedInRack = targetRackID
				sessions[s].series500Chassis[chassisIdx].mountedAtRow = tryRow

				// Update the chassis position to match where it will be visually displayed
				updateChassisPositionForMount(chassisIdx: chassisIdx, rackIdx: rackIdx, startRow: tryRow, sessionIdx: s)

				// Block the rack slots with a special placeholder
				let chassisID = sessions[s].series500Chassis[chassisIdx].id
				blockRackSlotsForMountedChassis(chassisID: chassisID, rackIdx: rackIdx, startRow: tryRow, sessionIdx: s)

				currentSession = sessions[s]
				saveSessions()
				return true
			}
		}

		// No 3U space found
		return false
	}

	/// Unmount a 500-series chassis from a rack
	func unmount500Series(chassisID: UUID) {
		guard let s = currentSessionIndex else { return }
		guard let chassisIdx = sessions[s].series500Chassis.firstIndex(where: { $0.id == chassisID }) else { return }

		// Clear the blocked slots from the rack
		if let rackID = sessions[s].series500Chassis[chassisIdx].mountedInRack,
		   let rackIdx = sessions[s].racks.firstIndex(where: { $0.id == rackID }) {
			clearRackSlotsForMountedChassis(chassisID: chassisID, rackIdx: rackIdx, sessionIdx: s)
		}

		sessions[s].series500Chassis[chassisIdx].mountedInRack = nil
		sessions[s].series500Chassis[chassisIdx].mountedAtRow = nil

		currentSession = sessions[s]
		saveSessions()
	}

	/// Update the mounting row for a chassis (used during wing drag)
	/// Does NOT save - caller should save when drag ends
	func updateMountingRow(chassisID: UUID, newRow: Int) {
		guard let s = currentSessionIndex else {
			print("⚠️ [SessionManager.updateMountingRow] No current session")
			return
		}
		guard let chassisIdx = sessions[s].series500Chassis.firstIndex(where: { $0.id == chassisID }) else {
			print("⚠️ [SessionManager.updateMountingRow] Chassis not found")
			return
		}
		guard sessions[s].series500Chassis[chassisIdx].isMounted else {
			print("⚠️ [SessionManager.updateMountingRow] Chassis not mounted")
			return
		}
		guard let rackID = sessions[s].series500Chassis[chassisIdx].mountedInRack else {
			print("⚠️ [SessionManager.updateMountingRow] No rack ID")
			return
		}
		guard let rackIdx = sessions[s].racks.firstIndex(where: { $0.id == rackID }) else {
			print("⚠️ [SessionManager.updateMountingRow] Rack not found")
			return
		}

		// Only update if the row actually changed
		let oldRow = sessions[s].series500Chassis[chassisIdx].mountedAtRow
		let oldPos = sessions[s].series500Chassis[chassisIdx].position

		if oldRow != newRow {
			print("🔄 [SessionManager.updateMountingRow] Moving from row \(oldRow ?? -1) to \(newRow)")

			// Check if new position has space (3U × 6 columns)
			// Must check BEFORE clearing old position in case we're moving to overlapping rows
			let requiredRows = 3
			var spaceAvailable = true
			for r in newRow..<min(newRow + requiredRows, sessions[s].racks[rackIdx].slots.count) {
				for c in 0..<RackGrid.columnsPerRow {
					if let inst = sessions[s].racks[rackIdx].slots[r][c] {
						// Allow if it's our own placeholder (we're moving within rack)
						if inst.id != chassisID {
							spaceAvailable = false
							print("⚠️ [SessionManager.updateMountingRow] Row \(newRow) occupied by device at [\(r),\(c)]")
							break
						}
					}
				}
				if !spaceAvailable { break }
			}

			// Only move if space is available
			if spaceAvailable {
				// Clear old position
				clearRackSlotsForMountedChassis(chassisID: chassisID, rackIdx: rackIdx, sessionIdx: s)

				// Update row
				sessions[s].series500Chassis[chassisIdx].mountedAtRow = newRow

				// Update the chassis position to match the new row
				updateChassisPositionForMount(chassisIdx: chassisIdx, rackIdx: rackIdx, startRow: newRow, sessionIdx: s)

				let newPos = sessions[s].series500Chassis[chassisIdx].position
				print("📍 [SessionManager.updateMountingRow] Position updated: \(Int(oldPos.y)) → \(Int(newPos.y))")

				// Block new position
				blockRackSlotsForMountedChassis(chassisID: chassisID, rackIdx: rackIdx, startRow: newRow, sessionIdx: s)

				currentSession = sessions[s]
			} else {
				print("❌ [SessionManager.updateMountingRow] Cannot move to row \(newRow) - space occupied")
			}
		} else {
			print("⏭️ [SessionManager.updateMountingRow] Row unchanged (\(newRow)), skipping update")
		}
	}

	// MARK: - Helpers for blocking rack slots and position management

	/// Update chassis.position to match its visual position when mounted
	/// This prevents jumps when starting a drag
	private func updateChassisPositionForMount(chassisIdx: Int, rackIdx: Int, startRow: Int, sessionIdx: Int) {
		let rack = sessions[sessionIdx].racks[rackIdx]

		// These constants match the calculation in SessionCanvasLayer
		let rackFacePadding: CGFloat = 16
		let dragStripHeight: CGFloat = 32
		let ppi: CGFloat = 80 // Default PPI from AppSettings.pointsPerInch
		let rowHeight = 1.75 * ppi // 1U = 1.75 inches
		let rowSpacing: CGFloat = 1

		// Calculate total rack height
		let faceHeight = rackFacePadding * 2
			+ CGFloat(rack.rows) * rowHeight
			+ CGFloat(max(0, rack.rows - 1)) * rowSpacing
		let totalRackHeight = dragStripHeight + faceHeight

		// rack.position is the CENTER of the entire rack view
		let rackTop = rack.position.y - totalRackHeight / 2

		// Calculate Y position of the top of the mounted row
		let rowTopY = rackTop + dragStripHeight + rackFacePadding + CGFloat(startRow) * (rowHeight + rowSpacing)

		// Chassis spans 3U
		let chassisHeight = 3 * rowHeight + 2 * rowSpacing

		// Position is at CENTER of chassis
		let chassisCenterY = rowTopY + chassisHeight / 2

		// X position: center of rack
		let chassisCenterX = rack.position.x

		// Update the chassis position
		sessions[sessionIdx].series500Chassis[chassisIdx].position = CGPoint(x: chassisCenterX, y: chassisCenterY)
	}

	/// Block rack slots occupied by a mounted 500-series chassis
	private func blockRackSlotsForMountedChassis(chassisID: UUID, rackIdx: Int, startRow: Int, sessionIdx: Int) {
		// Create a placeholder device instance with the chassis ID as both instance and device ID
		// This allows us to identify and clear it later
		let placeholder = DeviceInstance(id: chassisID, deviceID: chassisID, device: nil)

		// Fill 3U × 6 columns - ONLY in empty slots
		for r in startRow..<min(startRow + 3, sessions[sessionIdx].racks[rackIdx].slots.count) {
			for c in 0..<RackGrid.columnsPerRow {
				// Only place placeholder if slot is empty (don't overwrite existing devices!)
				if sessions[sessionIdx].racks[rackIdx].slots[r][c] == nil {
					sessions[sessionIdx].racks[rackIdx].slots[r][c] = placeholder
				}
			}
		}
	}

	/// Clear rack slots occupied by a mounted 500-series chassis
	private func clearRackSlotsForMountedChassis(chassisID: UUID, rackIdx: Int, sessionIdx: Int) {
		// Remove all instances with this chassis ID
		for r in sessions[sessionIdx].racks[rackIdx].slots.indices {
			for c in 0..<RackGrid.columnsPerRow {
				if sessions[sessionIdx].racks[rackIdx].slots[r][c]?.id == chassisID {
					sessions[sessionIdx].racks[rackIdx].slots[r][c] = nil
				}
			}
		}
	}

	/// Append a label to the current session, persist, and keep currentSession in sync.
	func addLabel(_ label: SessionLabel) {
		guard let s = currentSessionIndex else { return }
		sessions[s].labels.append(label)
		currentSession = sessions[s]
		saveSessions()
	}

	/// Update all labels linked to a preset with the new style
	func updateLabelsWithPreset(id: UUID, newStyle: LabelStyleSpec) {
		guard let s = currentSessionIndex else { return }
		for i in sessions[s].labels.indices {
			if sessions[s].labels[i].linkedPresetId == id {
				sessions[s].labels[i].style = newStyle
			}
		}
		currentSession = sessions[s]
		saveSessions()
	}

	/// Clear an instance from its source rack/chassis across the current session
	/// Used when moving devices between racks/chassis to remove from source
	func clearInstanceFromCurrentSession(id: UUID) {
		guard let s = currentSessionIndex else { return }

		// Search and clear from all racks
		for r in sessions[s].racks.indices {
			for row in sessions[s].racks[r].slots.indices {
				for col in 0..<RackGrid.columnsPerRow {
					if sessions[s].racks[r].slots[row][col]?.id == id {
						// Found it - clear the entire span
						clearSpan(of: id, inSession: s, rackIndex: r)
						currentSession = sessions[s]
						return
					}
				}
			}
		}

		// Search and clear from all 500-series chassis
		for c in sessions[s].series500Chassis.indices {
			for i in sessions[s].series500Chassis[c].slots.indices {
				if sessions[s].series500Chassis[c].slots[i]?.id == id {
					// Found it - clear this position and any multi-slot span
					let inst = sessions[s].series500Chassis[c].slots[i]!
					if let dev = library.device(for: inst.deviceID) {
						let width = max(1, dev.slotWidth ?? 1)
						// Clear the entire span
						for j in i..<min(i + width, sessions[s].series500Chassis[c].slots.count) {
							if sessions[s].series500Chassis[c].slots[j]?.id == id {
								sessions[s].series500Chassis[c].slots[j] = nil
							}
						}
					}
					currentSession = sessions[s]
					return
				}
			}
		}
	}
}

extension SessionManager {
	// Saving sessions (you already have saveSessions(); add revert)
	func revertCurrentSession() {
		guard let i = currentSessionIndex else { return }
		currentSession = sessions[i]
	}
	
	// New session from template (used by File ▸ New Session from Template… too)
	func newSession(from template: SessionTemplate?) {
		let new: Session
		if let t = template {
			new = t.session.snapshotWithNewIDs()
		} else if let defaultID = defaultTemplateId,
				  let t = templates.first(where: { $0.id == defaultID }) {
			new = t.session.snapshotWithNewIDs()
		} else {
			// 👇 supply the required initializer arguments for a blank session
			new = Session(name: "Untitled Session", racks: [], series500Chassis: [])
		}
		sessions.append(new)
		currentSession = new
		saveSessions()
	}
	
	func applyTemplate(_ t: SessionTemplate) {
		let new = t.session.snapshotWithNewIDs()
		if let i = currentSessionIndex {
			sessions[i] = new          // ← assign a concrete Session
		} else {
			sessions.append(new)
		}
		currentSession = new
		saveSessions()
	}
	
	// Create/save template
	func promptSaveAsTemplate() {
		// present an NSAlert / sheet to ask for a name; call saveAsTemplate(name:)
		// (wire this to a small SwiftUI sheet in SessionView if you prefer)
	}
	
	func saveAsTemplate(name: String) {
		guard let session = currentSession else { return }
		let skeleton = session.skeletonizedForTemplate()
		let t = SessionTemplate(name: name, session: skeleton)
		templates.append(t)
		saveTemplates()
	}

	func deleteTemplate(_ t: SessionTemplate) {
		templates.removeAll { $0.id == t.id }
		if defaultTemplateId == t.id { defaultTemplateId = nil }
		saveTemplates()
	}
}

extension Session {
	func snapshotWithNewIDs() -> Session {
		var s = self
		s.id = UUID()                // add if you don't have one already
		// generate fresh IDs for racks/chassis/labels if they carry identity
		s.racks = s.racks.map { var r = $0; r.id = UUID(); return r }
		s.series500Chassis = s.series500Chassis.map { var c = $0; c.id = UUID(); return c }
		s.labels = s.labels.map { var l = $0; l.id = UUID(); return l }
		return s
	}
	
	func skeletonizedForTemplate() -> Session {
		// Strip transient data you don't want replicated:
		// - runtime control states? (keep layout, remove per-take tweaks)
		// - audio recordings / analysis results (if any)
		// - maybe clear inline label text? (usually keep text)
		// Keep layout/pan/zoom/labels/racks/devices.
		return self
	}
}

extension SessionManager {
	private var templatesURL: URL {
		appSupportURL.appendingPathComponent("templates.json")
	}
	
	func loadTemplates() {
		do {
			let data = try Data(contentsOf: templatesURL)
			templates = try JSONDecoder().decode([SessionTemplate].self, from: data)
		} catch {
			templates = []
		}
	}
	
	func saveTemplates() {
		do {
			let data = try JSONEncoder().encode(templates)
			try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
			try data.write(to: templatesURL, options: .atomic)
		} catch {
			print("saveTemplates error:", error)
		}
	}
}


// MARK: - Session Commands
struct SessionCommands: Commands {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingNewSession: Bool
    @Binding var showingAddRack: Bool
    @Binding var showingAddChassis: Bool
	@Binding var showingReviewChanges: Bool
	@Binding var importingSession: Bool
	@Binding var exportingSession: Bool
	@Binding var exportingSessionSaveAs: Bool
	@Binding var showingSaveAsTemplate: Bool

	var body: some Commands {
		// Add to File menu after New
		CommandGroup(after: .newItem) {
			Button("New Session…") { showingNewSession = true }
				.keyboardShortcut("n", modifiers: [.command])

			Menu("New Session from Template") {
				ForEach(sessionManager.templates) { t in
					Button(t.name) { sessionManager.newSession(from: t) }
				}
				Divider()
				Button("Blank Session") { sessionManager.newSession(from: nil) }
			}

			Divider()

			Button("Open Session…") {
				importingSession = true
			}
			.keyboardShortcut("o", modifiers: [.command])

			Divider()

			Button("Save") {
				if !sessionManager.saveCurrentSessionToFile() {
					// No file location, trigger Save As
					exportingSession = true
				}
			}
			.keyboardShortcut("s", modifiers: [.command])

			Button("Save As…") {
				exportingSessionSaveAs = true
			}
			.keyboardShortcut("s", modifiers: [.command, .shift])

			Divider()
		}

		// Templates section in File menu
		CommandGroup(before: .importExport) {
			Button("Save Current as Template…") {
				showingSaveAsTemplate = true
			}
			.keyboardShortcut("t", modifiers: [.command, .shift])

			Menu("Default Template") {
				Button(sessionManager.defaultTemplateId == nil ? "• None" : "None") {
					sessionManager.defaultTemplateId = nil
				}
				ForEach(sessionManager.templates) { t in
					Button((sessionManager.defaultTemplateId == t.id ? "• " : "") + t.name) {
						sessionManager.defaultTemplateId = t.id
					}
				}
			}

#if os(macOS)
			Button("Manage Templates…") { sessionManager.showTemplateManager = true }
#endif

			Divider()
		}

		// View menu for view-related commands
		CommandMenu("View") {
			Button("Photoreal Mode") {
				sessionManager.renderStyle = .photoreal
			}
			.keyboardShortcut("1", modifiers: [.command])

			Button("Representative Mode") {
				sessionManager.renderStyle = .representative
			}
			.keyboardShortcut("2", modifiers: [.command])
		}

		// Session menu for session-specific operations
		CommandMenu("Session") {
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
