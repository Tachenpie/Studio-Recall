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
    @State private var rackCount: Int = 1
    @State private var seriesCount: Int = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Session")
                .font(.headline)
            
            Form {
                TextField("Session Name", text: $name)
                Stepper("Rack Chassis: \(rackCount)", value: $rackCount, in: 0...10)
                Stepper("500-Series Chassis: \(seriesCount)", value: $seriesCount, in: 0...10)
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
                .disabled(rackCount == 0 && seriesCount == 0)
            }
        }
        .padding()
    }
}

