//
//  Studio_RecallApp.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
	@State private var importingSession = false
	@State private var exportingSession = false
	@State private var exportingSessionSaveAs = false
	@State private var showingSaveAsTemplate = false
    
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
					importingSession: $importingSession,
					exportingSession: $exportingSession,
					exportingSessionSaveAs: $exportingSessionSaveAs,
					showingSaveAsTemplate: $showingSaveAsTemplate
                )
                #else
                RootView(
                    showingNewSession: $showingNewSession,
                    showingAddRack: $showingAddRack,
                    showingAddChassis: $showingAddChassis,
                    showingLibraryEditor: $showingLibraryEditor,
					showingReviewChanges: $showingReviewChanges,
					importingSession: $importingSession,
					exportingSession: $exportingSession,
					exportingSessionSaveAs: $exportingSessionSaveAs,
					showingSaveAsTemplate: $showingSaveAsTemplate
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
				importingSession: $importingSession,
				exportingSession: $exportingSession,
				exportingSessionSaveAs: $exportingSessionSaveAs,
				showingSaveAsTemplate: $showingSaveAsTemplate
			)
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

// MARK: - FileDocument for session export
struct SessionDocument: FileDocument {
	static var readableContentTypes: [UTType] { [.json] }

	let session: Session

	init(session: Session) {
		self.session = session
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		session = try JSONDecoder().decode(Session.self, from: data)
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let data = try JSONEncoder().encode(session)
		return FileWrapper(regularFileWithContents: data)
	}
}

struct RootView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var library: DeviceLibrary

    @Binding var showingNewSession: Bool
    @Binding var showingAddRack: Bool
    @Binding var showingAddChassis: Bool
	@Binding var showingReviewChanges: Bool
	@Binding var importingSession: Bool
	@Binding var exportingSession: Bool
	@Binding var exportingSessionSaveAs: Bool
	@Binding var showingSaveAsTemplate: Bool

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
			.fileImporter(
				isPresented: $importingSession,
				allowedContentTypes: [.json],
				allowsMultipleSelection: false
			) { result in
				switch result {
				case .success(let urls):
					guard let url = urls.first else { return }
					sessionManager.openSession(from: url)
				case .failure(let error):
					print("❌ Import failed: \(error)")
				}
			}
			.fileExporter(
				isPresented: $exportingSession,
				document: sessionManager.currentSession.map { SessionDocument(session: $0) },
				contentType: .json,
				defaultFilename: (sessionManager.currentSession?.name ?? "Untitled") + ".session.json"
			) { result in
				if case .success(let url) = result {
					sessionManager.currentSessionFileURL = url
				} else if case .failure(let error) = result {
					print("❌ Save failed: \(error)")
				}
			}
			.fileExporter(
				isPresented: $exportingSessionSaveAs,
				document: sessionManager.currentSession.map { SessionDocument(session: $0) },
				contentType: .json,
				defaultFilename: (sessionManager.currentSession?.name ?? "Untitled") + ".session.json"
			) { result in
				if case .success(let url) = result {
					sessionManager.currentSessionFileURL = url
				} else if case .failure(let error) = result {
					print("❌ Save As failed: \(error)")
				}
			}
			.sheet(isPresented: $showingSaveAsTemplate) {
				SaveTemplateNameSheet(sessionManager: sessionManager)
			}
    }
}
