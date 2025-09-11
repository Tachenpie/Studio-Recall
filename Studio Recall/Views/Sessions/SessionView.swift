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
	@State private var lastMagnification: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray.opacity(0.1)
					.ignoresSafeArea()
					.contentShape(Rectangle())

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
					.scaleEffect(CGFloat(session.canvasZoom.wrappedValue))
					.offset(CGSize(width: session.canvasPan.wrappedValue.x,
								   height: session.canvasPan.wrappedValue.y))
					.gesture(magnifyGesture(session: session))
					.simultaneousGesture(backgroundPanGesture(session: session))
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
				ToolbarItem(placement: .status) {
					HStack(spacing: 8) {
						Image(systemName: "minus.magnifyingglass")
						Slider(value: Binding(
							get: { sessionManager.currentSession.map { Double($0.canvasZoom) } ?? 1.2 },
							set: { new in
								if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
									sessionManager.sessions[i].canvasZoom = clamp(new, 0.6, 2.0)
									sessionManager.saveSessions()
								}
							}
						), in: 0.6...2.0)
							.frame(width: 140)
							   Image(systemName: "plus.magnifyingglass")
						Button {
							if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
								withAnimation {
									sessionManager.sessions[i].canvasZoom = 1.2
									sessionManager.sessions[i].canvasPan = .zero
								}
								sessionManager.saveSessions()
							}
						} label: {
							Image(systemName: "arrow.counterclockwise")
								.help("Reset zoom & pan")
						}
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

	// MARK: - Gestures
	private func magnifyGesture(session: Binding<Session>) -> some Gesture {
		        MagnificationGesture()
		            .onChanged { value in
			                // incremental magnification
			                let delta = value / lastMagnification
						session.wrappedValue.canvasZoom = clamp(
							session.wrappedValue.canvasZoom * delta, 0.6, 2.0
						)
			                lastMagnification = value
			            }
		         .onEnded { _ in
					lastMagnification = 1.0
					 sessionManager.saveSessions()
				}
		 }
	
	private func backgroundPanGesture(session: Binding<Session>) -> some Gesture {
		        DragGesture(minimumDistance: 2)
		            .onChanged { value in
						session.wrappedValue.canvasPan.x += value.translation.width
						session.wrappedValue.canvasPan.y += value.translation.height
			            }
					.onEnded { _ in
						sessionManager.saveSessions()
					}
		    }
	
	    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
		        min(max(v, lo), hi)
		    }
	
    private func dragGesture(forRackAt idx: Int, in sessionIndex: Int) -> some Gesture {
        DragGesture()
            .onEnded { value in
                sessionManager.sessions[sessionIndex].racks[idx].position = value.location
				sessionManager.saveSessions()
            }
    }

    private func dragGesture(forChassisAt idx: Int, in sessionIndex: Int) -> some Gesture {
        DragGesture()
            .onEnded { value in
                sessionManager.sessions[sessionIndex].series500Chassis[idx].position = value.location
				sessionManager.saveSessions()
            }
    }
}
