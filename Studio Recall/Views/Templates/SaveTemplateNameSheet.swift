//
//  SaveTemplateNameSheet.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

struct SaveTemplateNameSheet: View {
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        _name = State(initialValue: sessionManager.currentSession?.name.appending(" Template") ?? "New Template")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Current as Template").font(.title3).bold()
            TextField("Template name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
                .frame(minWidth: 320)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
    }

    private func save() {
        sessionManager.saveAsTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
