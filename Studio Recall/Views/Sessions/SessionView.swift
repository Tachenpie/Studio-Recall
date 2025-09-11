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
	@State private var panStart: CGPoint? = nil
	@State private var lastMagnification: CGFloat = 1.0
	@State private var showMinimap = true
	@State private var rackDragStart: [UUID: CGPoint] = [:]
	@State private var chassisDragStart: [UUID: CGPoint] = [:]

    var body: some View {
		NavigationStack {
			if let sessionIndex = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
				let session = $sessionManager.sessions[sessionIndex]
				ZStack {
					Color.gray.opacity(0.1)
						.ignoresSafeArea()
						.contentShape(Rectangle())
						.gesture(backgroundPanGesture(session: session))
						.simultaneousGesture(magnifyGesture(session: session))
#if os(macOS)
						.overlay(
							ScrollWheelPanOverlay { delta in
								if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
									sessionManager.sessions[i].canvasPan.x += delta.width
									sessionManager.sessions[i].canvasPan.y -= delta.height   // invert Y so “scroll up” moves view up
									sessionManager.saveSessions()
								}
							}
								.allowsHitTesting(false) // don't block clicks
						)
#endif
					
					GeometryReader { geo in
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
						Group {
							if showMinimap, !(session.wrappedValue.racks.isEmpty && session.wrappedValue.series500Chassis.isEmpty) {
								MinimapOverlay(
									rackPositions: session.wrappedValue.racks.map(\.position),
									chassisPositions: session.wrappedValue.series500Chassis.map(\.position),
									zoom: session.canvasZoom,
									pan: session.canvasPan,
									canvasSize: geo.size
								)
								.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
								.allowsHitTesting(true)
							}
						}
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
				ToolbarItem(placement: .status) {
					Button {
						showMinimap.toggle()
					} label: {
						Label(showMinimap ? "Hide Minimap" : "Show Minimap",
							  systemImage: showMinimap ? "map" : "map.fill")
					}
					.help(showMinimap ? "Hide Minimap" : "Show Minimap")
				}
				ToolbarItem(placement: .status) {
					HStack(spacing: 8) {
						Image(systemName: "minus.magnifyingglass")
						// --- Slider binding (inside ToolbarItem .status) ---
						Slider(
							value: Binding(
								get: {
									if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
										return sessionManager.sessions[i].canvasZoom
									} else {
										return 1.2
									}
								},
								set: { newZoom in
									guard let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) else { return }
									let oldZoom = sessionManager.sessions[i].canvasZoom
									let clamped = min(max(newZoom, 0.6), 3.0)
									
									// keep center stable
									if let window = NSApp.keyWindow {
										let canvasSize = window.contentView?.bounds.size ?? .zero
										let screenCenter = CGPoint(x: canvasSize.width/2, y: canvasSize.height/2)
										let oldPan = sessionManager.sessions[i].canvasPan
										let worldCenterX = (screenCenter.x - oldPan.x) / oldZoom
										let worldCenterY = (screenCenter.y - oldPan.y) / oldZoom
										let newPan = CGPoint(
											x: screenCenter.x - worldCenterX * clamped,
											y: screenCenter.y - worldCenterY * clamped
										)
										sessionManager.sessions[i].canvasPan = newPan
									}
									
									sessionManager.sessions[i].canvasZoom = clamped
								}
							),
							in: 0.6...3.0
						)
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

	// MARK: - Gestures
	private func magnifyGesture(session: Binding<Session>) -> some Gesture {
		        MagnificationGesture()
		            .onChanged { value in
			                // incremental magnification
			                let delta = value / lastMagnification
						session.wrappedValue.canvasZoom = clamp(
							session.wrappedValue.canvasZoom * delta, 0.6, 3.0
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
						if panStart == nil { panStart = session.wrappedValue.canvasPan }
						let start = panStart ?? .zero
						session.wrappedValue.canvasPan = CGPoint(x: start.x + value.translation.width,
						y: start.y + value.translation.height)
			            }
					.onEnded { _ in
						panStart = nil
						sessionManager.saveSessions()
					}
		    }
	
	    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
		        min(max(v, lo), hi)
		    }
	
	private func dragGesture(forRackAt idx: Int, in sessionIndex: Int) -> some Gesture {
		DragGesture(minimumDistance: 1)
			.onChanged { value in
				let z = sessionManager.sessions[sessionIndex].canvasZoom
				let id = sessionManager.sessions[sessionIndex].racks[idx].id
				if rackDragStart[id] == nil {
					rackDragStart[id] = sessionManager.sessions[sessionIndex].racks[idx].position
				}
				let start = rackDragStart[id]!
				sessionManager.sessions[sessionIndex].racks[idx].position = CGPoint(
					x: start.x + value.translation.width  / z,
					y: start.y + value.translation.height / z
				)
			}
			.onEnded { _ in
				let id = sessionManager.sessions[sessionIndex].racks[idx].id
				rackDragStart[id] = nil
				sessionManager.saveSessions()
			}
	}
	
	private func dragGesture(forChassisAt idx: Int, in sessionIndex: Int) -> some Gesture {
		DragGesture(minimumDistance: 1)
			.onChanged { value in
				let z = sessionManager.sessions[sessionIndex].canvasZoom
				let id = sessionManager.sessions[sessionIndex].series500Chassis[idx].id
				if chassisDragStart[id] == nil {
					chassisDragStart[id] = sessionManager.sessions[sessionIndex].series500Chassis[idx].position
				}
				let start = chassisDragStart[id]!
				sessionManager.sessions[sessionIndex].series500Chassis[idx].position = CGPoint(
					x: start.x + value.translation.width  / z,
					y: start.y + value.translation.height / z
				)
			}
			.onEnded { _ in
				let id = sessionManager.sessions[sessionIndex].series500Chassis[idx].id
				chassisDragStart[id] = nil
				sessionManager.saveSessions()
			}
	}
}

// MARK: - Mini-map
private struct MinimapOverlay: View {
	// World elements (positions are in the same space you pass to .position(_:))
	let rackPositions: [CGPoint]
	let chassisPositions: [CGPoint]
	@Binding var zoom: Double
	@Binding var pan: CGPoint
	
	// Size of the visible canvas (pixels) – used to compute viewport box
	let canvasSize: CGSize
	
	private let mapSize = CGSize(width: 180, height: 120)
	private let padding: CGFloat = 8
	
	var body: some View {
		// Derive world bounds from element positions (with padding)
		let xs = (rackPositions + chassisPositions).map(\.x)
		let ys = (rackPositions + chassisPositions).map(\.y)
		var minX = (xs.min() ?? 0) - 80
		var maxX = (xs.max() ?? 1000) + 80
		var minY = (ys.min() ?? 0) - 80
		var maxY = (ys.max() ?? 800) + 80
		
		// Compute the current viewport (in world coords)
		let viewW = canvasSize.width / zoom
		let viewH = canvasSize.height / zoom
		let viewOriginWorld = CGPoint(x: -pan.x / zoom, y: -pan.y / zoom)
		let viewRectWorld = CGRect(origin: viewOriginWorld, size: CGSize(width: viewW, height: viewH))
		
		// IMPORTANT: include the viewport in bounds BEFORE computing worldW/H
		minX = min(minX, viewRectWorld.minX)
		maxX = max(maxX, viewRectWorld.maxX)
		minY = min(minY, viewRectWorld.minY)
		maxY = max(maxY, viewRectWorld.maxY)
		
		// Now compute final world span
		let worldW = max(maxX - minX, 1)
		let worldH = max(maxY - minY, 1)
		
		func mapPoint(_ p: CGPoint) -> CGPoint {
			let nx = (p.x - minX) / worldW
			let ny = (p.y - minY) / worldH
			return CGPoint(x: nx * mapSize.width, y: ny * mapSize.height)
		}
		
		// Map viewport rect to minimap coords
		let tl = mapPoint(viewRectWorld.origin)
		let br = mapPoint(CGPoint(x: viewRectWorld.maxX, y: viewRectWorld.maxY))
		let viewRectMini = CGRect(x: min(tl.x, br.x),
								  y: min(tl.y, br.y),
								  width: abs(br.x - tl.x),
								  height: abs(br.y - tl.y))
		
		return ZStack(alignment: .topLeading) {
			// map background
			RoundedRectangle(cornerRadius: 10)
				.fill(Color.black.opacity(0.55))
				.overlay(
					RoundedRectangle(cornerRadius: 10)
						.stroke(Color.white.opacity(0.25), lineWidth: 1)
				)
				.frame(width: mapSize.width + 2*padding, height: mapSize.height + 2*padding)
			
			// world layer
			ZStack {
				// elements
				ForEach(Array(rackPositions.enumerated()), id: \.offset) { _, p in
					let mp = mapPoint(p)
					Circle().fill(Color.blue.opacity(0.9))
						.frame(width: 5, height: 5)
						.position(mp)
				}
				ForEach(Array(chassisPositions.enumerated()), id: \.offset) { _, p in
					let mp = mapPoint(p)
					Rectangle().fill(Color.green.opacity(0.9))
						.frame(width: 6, height: 6)
						.position(mp)
				}
				
				// viewport rectangle
				RoundedRectangle(cornerRadius: 2)
					.stroke(Color.yellow, lineWidth: 1)
					.frame(width: viewRectMini.width, height: viewRectMini.height)
					.position(x: viewRectMini.midX, y: viewRectMini.midY)
			}
			.frame(width: mapSize.width, height: mapSize.height)
			.padding(padding)
		}
		// Click to center the canvas on that world point
		.contentShape(Rectangle())
		.gesture(
			DragGesture(minimumDistance: 0)
				.onEnded { value in
					// Convert click point in minimap back to world point
					let loc = value.location - CGPoint(x: padding, y: padding)
					let nx = min(max(loc.x / mapSize.width, 0), 1)
					let ny = min(max(loc.y / mapSize.height, 0), 1)
					let worldX = minX + nx * worldW
					let worldY = minY + ny * worldH
					// Set pan so that clicked world point moves to canvas center
					pan.x = canvasSize.width  / 2 - worldX * zoom
					pan.y = canvasSize.height / 2 - worldY * zoom
				}
		)
		.shadow(radius: 3)
		.padding(.trailing, 12)
		.padding(.bottom, 12)
	}
}

private extension CGPoint {
	static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
}

