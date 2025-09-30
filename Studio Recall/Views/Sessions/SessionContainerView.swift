//
//  SessionContainerView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct SessionContainerView: View {
    @State private var selectedDevice: Device? = nil
    @EnvironmentObject var library: DeviceLibrary
   
	@State private var libraryIsEditing: Bool = false
	
    var body: some View {
        NavigationSplitView {
            DeviceLibraryView()
                .environmentObject(library)
				.onPreferenceChange(LibraryEditingDeviceKey.self) { editing in
					libraryIsEditing = editing
				}
        } detail: {
            SessionView()
                .environmentObject(library)
				.environment(\.isInteracting, libraryIsEditing)
        }
    }
}
