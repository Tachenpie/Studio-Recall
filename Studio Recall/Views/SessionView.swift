//
//  SessionView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct SessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: DeviceLibrary

    @State private var showingNewSession = false
    @State private var showingLibraryEditor = false
    @State private var showingAddRack = false
    @State private var showingAddChassis = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray.opacity(0.1).ignoresSafeArea()

                if let sessionIndex = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
                    let session = $sessionManager.sessions[sessionIndex]

                    ZStack {
                        // Racks
                        ForEach(session.racks.indices, id: \.self) { idx in
                            RackChassisView(rack: session.racks[idx])
                                .position(session.racks[idx].position.wrappedValue)
                                .gesture(dragGesture(forRackAt: idx, in: sessionIndex))
                        }

                        // 500 Series Chassis
                        ForEach(session.series500Chassis.indices, id: \.self) { idx in
                            Series500ChassisView(chassis: session.series500Chassis[idx])
                                .position(session.series500Chassis[idx].position.wrappedValue)
                                .gesture(dragGesture(forChassisAt: idx, in: sessionIndex))
                        }
                    }
                } else {
                    Text("No session loaded")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Session")
            .toolbar {
                ToolbarItem() { //placement: .primaryAction) {
                    Button {
                        showingNewSession = true
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingLibraryEditor = true
                    } label: {
                        Label("Edit Library", systemImage: "books.vertical")
                    }
                }
            }
            .sheet(isPresented: $showingNewSession) {
                NewSessionView()
                    .environmentObject(sessionManager)
            }
            .sheet(isPresented: $showingLibraryEditor) {
                NavigationStack {
                    LibraryManagerView()
                    .environmentObject(library)
                }
            }
            .sheet(isPresented: $showingAddRack) {
                AddRackSheet()
                    .environmentObject(sessionManager)
            }
            .sheet(isPresented: $showingAddChassis) {
                AddSeries500Sheet()
                    .environmentObject(sessionManager)
            }
        }
    }

    // MARK: - Drag Gestures

    private func dragGesture(forRackAt idx: Int, in sessionIndex: Int) -> some Gesture {
        DragGesture()
            .onEnded { value in
                sessionManager.sessions[sessionIndex].racks[idx].position = value.location
            }
    }

    private func dragGesture(forChassisAt idx: Int, in sessionIndex: Int) -> some Gesture {
        DragGesture()
            .onEnded { value in
                sessionManager.sessions[sessionIndex].series500Chassis[idx].position = value.location
            }
    }
}
