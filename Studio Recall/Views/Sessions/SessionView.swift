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
	@State private var showingSaveTemplateName = false
	@State private var panStart: CGPoint? = nil
	@State private var lastMagnification: CGFloat = 1.0
	@State private var showMinimap = true
	@State private var rackDragStart: [UUID: CGPoint] = [:]
	@State private var chassisDragStart: [UUID: CGPoint] = [:]
	@State private var rackRects: [RackRect] = []

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
						if let i = sessionManager.sessions.firstIndex(where: { $0.id == sessionManager.currentSession?.id }) {
							// 1) Precompute rects & positions ONCE
							let session = $sessionManager.sessions[i]
							let unitRow = DeviceMetrics.rackSize(units: 1, scale: settings.pointsPerInch)
							let unitMod = DeviceMetrics.moduleSize(units: 1, scale: settings.pointsPerInch)
							let topBarH: CGFloat = 24
							
							let rackRectsCG: [CGRect] = session.wrappedValue.racks.map { r in
								let rows = r.slots.count
								let h = CGFloat(rows) * unitRow.height
								+ CGFloat(max(0, rows - 1)) * 4   // row spacing
								+ 32                               // face padding (16 per side)
								+ topBarH                          // tabletop above
								let w = unitRow.width + 32
								return CGRect(x: r.position.x - w/2, y: r.position.y - h/2, width: w, height: h)
							}
							
							let chassisRectsCG: [CGRect] = session.wrappedValue.series500Chassis.map { c in
								let slots = c.slots.count
								let w = CGFloat(slots) * unitMod.width + CGFloat(max(0, slots - 1)) * 4
								let h = unitMod.height + 8              // existing vertical padding on face
								+ topBarH                         // tabletop above
								return CGRect(x: c.position.x - w/2, y: c.position.y - h/2, width: w, height: h)
							}
							let rackPositions   = session.wrappedValue.racks.map(\.position)
							let chassisPositions = session.wrappedValue.series500Chassis.map(\.position)
							
							SessionCanvasLayer(session: session, canvasSize: geo.size, rackRects: rackRects)
								.environment(\.canvasZoom, CGFloat(session.wrappedValue.canvasZoom))
								.scaleEffect(session.wrappedValue.canvasZoom, anchor: .topLeading)
								.offset(x: session.wrappedValue.canvasPan.x, y: session.wrappedValue.canvasPan.y)
							
							// 3) Minimap stays separate and short
							Group {
								if showMinimap, !(rackRectsCG.isEmpty && chassisRectsCG.isEmpty) {
									MinimapOverlay(
										rackRects: rackRectsCG,
										chassisRects: chassisRectsCG,
										rackPositions: rackPositions,
										chassisPositions: chassisPositions,
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
					.onPreferenceChange(RackRectsKey.self) { rackRects = $0 }
				}
			} else {
				Text("No session loaded")
					.foregroundColor(.secondary)
			}
		}
            .navigationTitle("Session")
            .toolbar {
				ToolbarItemGroup(placement: .automatic) {
					Button {
						sessionManager.addRack()
					} label: {
						Label("Add Rack", systemImage: "square.grid.3x2")
					}
					.help("Add Rack")
					
					Button {
						sessionManager.addSeries500Chassis()
					} label: {
						Label("Add 500-series Chassis", systemImage: "rectangle.3.offgrid")
					}
					.help("Add 500-series Chassis")
					
					Button {
						let new = SessionLabel(
							anchor: .session,
							offset: CGPoint(x: 40, y: 40),
							text: "",
							style: .preset(.plasticLabelMaker)
						)
						sessionManager.addLabel(new)
					} label: {
						Label("Create Label", systemImage: "tag")
					}
					.help("Create Label")
				}
				
				ToolbarItemGroup(placement: .automatic) {
					Button {
						showMinimap.toggle()
					} label: {
						Label(showMinimap ? "Hide Minimap" : "Show Minimap",
							  systemImage: showMinimap ? "map" : "map.fill")
					}
					.help(showMinimap ? "Hide Minimap" : "Show Minimap")
				
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
									let clamped = min(max(newZoom, 0.5), 4.0)
									
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
							in: 0.5...4.0
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
							Label("Reset Zoom & Pan", systemImage: "arrow.counterclockwise")
								.help("Reset Zoom & Pan")
						}
					}
				}
				
				ToolbarItemGroup(placement: .automatic) {
					Menu {
						// Apply (non-destructive replace of the layout)
						ForEach(sessionManager.templates) { t in
							Button(t.name) { sessionManager.applyTemplate(t) }
						}
						Divider()
						Button("Save Current as Template…") {
							showingSaveTemplateName = true
						}
						.help("Save Current as Template...")
#if os(macOS)
						Button("Manage Templates…") { sessionManager.showTemplateManager = true }
							.help("Manage Templates...")
#endif
						Divider()
						// Default template selector
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
					} label: {
						Label("Templates", systemImage: "doc.on.doc")
							.help("Templates")
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
			.sheet(isPresented: $sessionManager.showTemplateManager) {
				TemplateManagerView(sessionManager: sessionManager)
			}
			.sheet(isPresented: $showingSaveTemplateName) {
				SaveTemplateNameSheet(sessionManager: sessionManager)
			}
    }

	// MARK: - Gestures
	private func magnifyGesture(session: Binding<Session>) -> some Gesture {
		        MagnificationGesture()
		            .onChanged { value in
			                // incremental magnification
			                let delta = value / lastMagnification
						session.wrappedValue.canvasZoom = clamp(
							session.wrappedValue.canvasZoom * delta, 0.5, 4.0
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
}

// MARK: - Mini-map
private struct MinimapOverlay: View {
	// NEW: world-space bounds for each element
	let rackRects: [CGRect]
	let chassisRects: [CGRect]
	let topBarHeight: CGFloat = 24
	
	// (keep these so we can still show dots)
	let rackPositions: [CGPoint]
	let chassisPositions: [CGPoint]
	
	@Binding var zoom: Double
	@Binding var pan: CGPoint
	let canvasSize: CGSize
	
	private let mapSize = CGSize(width: 180, height: 120)
	private let padding: CGFloat = 8
	
	var body: some View {
		// Content bounds from REAL rectangles, not centers
		let allRects = rackRects + chassisRects
		// Safe default if something is empty (shouldn’t be, given your guard)
		let contentRect = allRects.dropFirst().reduce(allRects.first ?? CGRect(x: 0, y: 0, width: 1000, height: 800)) { $0.union($1) }
		
		// Viewport in world coords
		let viewW = canvasSize.width / zoom
		let viewH = canvasSize.height / zoom
		let viewOriginWorld = CGPoint(x: -pan.x / zoom, y: -pan.y / zoom)
		let viewRectWorld = CGRect(origin: viewOriginWorld, size: CGSize(width: viewW, height: viewH))
		
		// World rect: use content as the baseline; only grow if viewport extends past it
		var worldRect = contentRect
		if !worldRect.contains(viewRectWorld) {
			worldRect = worldRect.union(viewRectWorld)
		}
		worldRect = worldRect.insetBy(dx: -8, dy: -8) // small buffer
		
		func mapPoint(_ p: CGPoint) -> CGPoint {
			let nx = (p.x - worldRect.minX) / worldRect.width
			let ny = (p.y - worldRect.minY) / worldRect.height
			return CGPoint(x: nx * mapSize.width, y: ny * mapSize.height)
		}
		
		let tl = mapPoint(viewRectWorld.origin)
		let br = mapPoint(CGPoint(x: viewRectWorld.maxX, y: viewRectWorld.maxY))
		let viewRectMini = CGRect(x: min(tl.x, br.x),
								  y: min(tl.y, br.y),
								  width: abs(br.x - tl.x),
								  height: abs(br.y - tl.y))
		
		return ZStack(alignment: .topLeading) {
			// background
			RoundedRectangle(cornerRadius: 10)
				.fill(Color.black.opacity(0.55))
				.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25), lineWidth: 1))
				.frame(width: mapSize.width + 2*padding, height: mapSize.height + 2*padding)
			
			// world layer (inside padding)
			ZStack {
				// dots
				ForEach(Array(rackPositions.enumerated()), id: \.offset) { _, p in
					Circle().fill(Color.blue.opacity(0.9)).frame(width: 5, height: 5).position(mapPoint(p))
				}
				ForEach(Array(chassisPositions.enumerated()), id: \.offset) { _, p in
					Rectangle().fill(Color.green.opacity(0.9)).frame(width: 5, height: 5).position(mapPoint(p))
				}
				// viewport
				Path { $0.addRect(viewRectMini) }
					.stroke(Color.yellow.opacity(0.9), lineWidth: 2)
			}
			.frame(width: mapSize.width, height: mapSize.height)
			.clipped()
			.padding(padding)
		}
		// your existing drag-to-center mapping stays correct (it already uses worldRect)
		.contentShape(Rectangle())
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { value in
					let loc = CGPoint(x: value.location.x - padding, y: value.location.y - padding)
					let clampedX = max(0, min(mapSize.width, loc.x))
					let clampedY = max(0, min(mapSize.height, loc.y))
					let nx = clampedX / mapSize.width
					let ny = clampedY / mapSize.height
					let worldX = worldRect.minX + nx * worldRect.width
					let worldY = worldRect.minY + ny * worldRect.height
					pan.x = canvasSize.width/2  - worldX * zoom
					pan.y = canvasSize.height/2 - worldY * zoom
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

