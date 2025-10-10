//
//  Studio_RecallApp.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
import SwiftData

@main
struct Studio_RecallApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var library = DeviceLibrary()
    @StateObject private var sessionManager: SessionManager
    
    @State private var showingLibraryEditor = false
    @State private var showingNewSession = false
    @State private var showingAddRack = false
    @State private var showingAddChassis = false
	@State private var showingReviewChanges = false
	@State private var showingSaveOptions = false
    
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    
    init() {
        let library = DeviceLibrary()
        _library = StateObject(wrappedValue: library)
        _sessionManager = StateObject(wrappedValue: SessionManager(library: library))
		
		// Register built-in sprite assets once
		SpriteLibrary.shared.registerBuiltinsIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                RootView(
                    showingNewSession: $showingNewSession,
                    showingAddRack: $showingAddRack,
                    showingAddChassis: $showingAddChassis,
					showingReviewChanges: $showingReviewChanges,
					showingSaveOptions: $showingSaveOptions
                )
                #else
                RootView(
                    showingNewSession: $showingNewSession,
                    showingAddRack: $showingAddRack,
                    showingAddChassis: $showingAddChassis,
                    showingLibraryEditor: $showingLibraryEditor,
					showingReviewChanges: $showingReviewChanges,
					showingSaveOptions: $showingSaveOptions
                )
                #endif
            }
            .environmentObject(settings)
            .environmentObject(sessionManager)
            .environmentObject(library)
        }
		.commands {
			SessionCommands(
				sessionManager: sessionManager,
				showingNewSession: $showingNewSession,
				showingAddRack: $showingAddRack,
				showingAddChassis: $showingAddChassis,
				showingReviewChanges: $showingReviewChanges,
				showingSaveOptions: $showingSaveOptions
			)
			
			// File ▸ New from Template
			CommandGroup(after: .newItem) {
				Menu("New Session from Template") {
					ForEach(sessionManager.templates) { t in
						Button(t.name) { sessionManager.newSession(from: t) }
					}
					Divider()
					Button("Blank Session") { sessionManager.newSession(from: nil) }
				}
			}
			
			// Templates menu
			CommandMenu("Templates") {
				Button("Save Current as Template…") {
					sessionManager.saveCurrentSessionAsTemplate()
				}
				Divider()
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
				Divider()
				Button("Manage Templates…") { sessionManager.showTemplateManager = true }
#endif
			}
		}

        
        #if os(macOS)
        Window("Library Manager", id: "library") {
            LibraryManagerView()
                .environmentObject(library)
        }
        .defaultPosition(.center)
        .defaultSize(width: 600, height: 400)

		WindowGroup(id: "control-editor", for: UUID.self) { $deviceId in
			if let id = deviceId,
			   let device = library.devices.first(where: { $0.id == id }) {
				ControlEditorWindow(editableDevice: EditableDevice(device: device))
					.frame(minWidth: 900, minHeight: 560)
			} else {
			Text("No device selected")
					.frame(minWidth: 600, minHeight: 300)
			}
		}
		.windowStyle(.titleBar)
		.windowToolbarStyle(.unifiedCompact)
		
		
        Settings {
            PreferencesView()
                .environmentObject(settings)
        }
        #endif
    }
}

/// Cross-platform menu button with single closure
private struct LibraryMenuButton: View {
    let action: () -> Void
    
    var body: some View {
        Button("Edit Library…", action: action)
            .keyboardShortcut("1", modifiers: [.command, .shift])
    }
}

/// Helper that lives in a View context, so we can use @Environment(\.openWindow)
#if os(macOS)
private struct OpenLibraryWindowAction: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Color.clear
            .task {
                openWindow(id: "library")
            }
    }
}
#endif

struct RootView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var library: DeviceLibrary
    
    @Binding var showingNewSession: Bool
    @Binding var showingAddRack: Bool
    @Binding var showingAddChassis: Bool
	@Binding var showingReviewChanges: Bool
	@Binding var showingSaveOptions: Bool
    
    #if !os(macOS)
    @Binding var showingLibraryEditor: Bool
    #endif
    
    var body: some View {
        SessionContainerView()
            .environmentObject(sessionManager)
            .environmentObject(library)
            .sheet(isPresented: $showingNewSession) {
                NewSessionView().environmentObject(sessionManager)
            }
            .sheet(isPresented: $showingAddRack) {
                AddRackSheet().environmentObject(sessionManager)
            }
            .sheet(isPresented: $showingAddChassis) {
                AddSeries500Sheet().environmentObject(sessionManager)
            }
            #if !os(macOS)
            .sheet(isPresented: $showingLibraryEditor) {
                DeviceLibraryView()
                    .environmentObject(library)
            }
            #endif
			.sheet(isPresented: $showingReviewChanges) {
				DiffReviewSheet().environmentObject(sessionManager)
			}
			.confirmationDialog("Save Session",
								isPresented: $showingSaveOptions,
								titleVisibility: .visible) {
				Button("Save", role: .none) {
					sessionManager.saveAll()    // persists sessions.json
				}
#if os(macOS)
				Button("Save As…") {
					sessionManager.saveCurrentSessionAs()
				}
				Button("Save As Template…") {
					sessionManager.saveCurrentSessionAsTemplate()
				}
#endif
				Button("Cancel", role: .cancel) { }
			}
    }
}
