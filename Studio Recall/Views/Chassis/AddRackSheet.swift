//
//  AddRackSheet.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct AddRackSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var rows: Int = 0
    
    var body: some View {
        Form {
            Stepper("Units: \(rows)", value: $rows, in: 1...64)
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    sessionManager.addRack(rows: rows)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear {
            rows = sessionManager.lastRackSlotCount
        }
    }
}
