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
    @State private var name: String = ""

    var body: some View {
        Form {
            TextField("Rack Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)

            Stepper("Units: \(rows)", value: $rows, in: 1...64)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    let rackName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    sessionManager.addRack(rows: rows, name: rackName.isEmpty ? nil : rackName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear {
            rows = sessionManager.lastRackSlotCount
            name = ""
        }
    }
}
