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
    // ✅ add rack with remembered default
    func addRack(rows: Int? = nil) {
        guard let session = currentSession else { return }
        let count = rows ?? lastRackSlotCount
        lastRackSlotCount = count
        let newRack = Rack(rows: count)
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
	/// Append a label to the current session, persist, and keep currentSession in sync.
	func addLabel(_ label: SessionLabel) {
		guard let s = currentSessionIndex else { return }
		sessions[s].labels.append(label)
		currentSession = sessions[s]
		saveSessions()
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
