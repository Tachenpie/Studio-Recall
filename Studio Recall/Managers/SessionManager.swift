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

    func reconcileDevices(with updated: Device) {
        for index in sessions.indices {
            // --- Fix racks ---
            for rackIndex in sessions[index].racks.indices {
                for slotIndex in sessions[index].racks[rackIndex].slots.indices {
                    if let instance = sessions[index].racks[rackIndex].slots[slotIndex] {
                        if library.device(for: instance.deviceID) == nil {
                            // Device no longer in library → clear slot
                            sessions[index].racks[rackIndex].slots[slotIndex] = nil
                        }
                    }
                }
            }
            
            // --- Fix 500-series chassis ---
            for chassisIndex in sessions[index].series500Chassis.indices {
                for slotIndex in sessions[index].series500Chassis[chassisIndex].slots.indices {
                    if let instance = sessions[index].series500Chassis[chassisIndex].slots[slotIndex] {
                        if library.device(for: instance.deviceID) == nil {
                            sessions[index].series500Chassis[chassisIndex].slots[slotIndex] = nil
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Session Commands
struct SessionCommands: Commands {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingNewSession: Bool
    @Binding var showingAddRack: Bool
    @Binding var showingAddChassis: Bool

    var body: some Commands {
        CommandMenu("Session") {
            Button("New Session…") { showingNewSession = true }
                .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Add Rack…") { showingAddRack = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Add 500 Series Chassis…") { showingAddChassis = true }
                .keyboardShortcut("c", modifiers: [.command, .shift])

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
