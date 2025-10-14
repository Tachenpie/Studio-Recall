//
//  AddSeries500Sheet.swift
//  Studio Recall
//
//  Created by True Jackie on 8/29/25.
//
import SwiftUI

struct AddSeries500Sheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var slotCount: Int = 0

    var body: some View {
        Form {
            TextField("Chassis Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)

            Stepper("Slots: \(slotCount)", value: $slotCount, in: 1...20)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    let chassisName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    sessionManager.addSeries500Chassis(name: chassisName.isEmpty ? nil : chassisName, slotCount: slotCount)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear {
            slotCount = sessionManager.lastChassisSlotCount
            name = ""
        }
    }
}
