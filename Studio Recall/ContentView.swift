//
//  ContentView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var sessionToDelete: Session?
    @Binding var showingDeleteConfirm: Bool
    
    var body: some View {
        VStack {
            if let session = sessionManager.currentSession {
                Text("Active Session: \(session.name)")
            } else {
                Text("No active session")
            }
        }
        .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    sessionManager.deleteSession(session)
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to delete the session “\(session.name)”? This cannot be undone.")
            }
        }
    }
}
//
//#Preview {
//    ContentView()
//        .modelContainer(for: Item.self, inMemory: true)
//}
