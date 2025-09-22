//
//  NewSessionView.swift
//  Studio Recall
//
//  Created by True Jackie on 8/28/25.
//

import SwiftUI

struct NewSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Session")
                .font(.headline)
            
            Form {
                TextField("Session Name", text: $name)
            }
            .frame(width: 300)
            
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    sessionManager.newSession(
                        name: name.isEmpty ? "Untitled" : name
                    )
                    dismiss()
                }
            }
        }
        .padding()
    }
}

