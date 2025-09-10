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
    
    var body: some View {
        NavigationSplitView {
            DeviceLibraryView()
                .environmentObject(library)
        } detail: {
            SessionView()
                .environmentObject(library)
                .onDrop(of: ["public.device", "public.index"], isTargeted: nil) { _ in false }
        }
    }
}
