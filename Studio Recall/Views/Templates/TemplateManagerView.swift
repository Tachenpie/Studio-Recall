//
//  TemplateManagerView.swift
//  Studio Recall
//
//  Created by True Jackie on 9/23/25.
//


import SwiftUI

struct TemplateManagerView: View {
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var localTemplates: [SessionTemplate] = []
    @State private var localDefaultID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Templates").font(.title2).bold()
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            if localTemplates.isEmpty {
                ContentUnavailableView("No Templates",
                                       systemImage: "doc.on.doc",
                                       description: Text("Use “Save Current as Template…” to create one."))
                    .frame(minHeight: 200)
            } else {
				List {
					ForEach(localTemplates.indices, id: \.self) { idx in
						HStack {
							// star (default)
							Button {
								localDefaultID = localTemplates[idx].id
							} label: {
								Image(systemName: localDefaultID == localTemplates[idx].id ? "star.fill" : "star")
									.foregroundStyle(localDefaultID == localTemplates[idx].id ? .yellow : .secondary)
							}
							.buttonStyle(.plain)
							.help("Set as default")
							
							// rename
							TextField("Template name", text: $localTemplates[idx].name)
								.textFieldStyle(.roundedBorder)
								.frame(minWidth: 240)
							
							Spacer()
							
							// (optional) inline delete button; safe because we use idx
							Button(role: .destructive) {
								let id = localTemplates[idx].id
								withAnimation {
									localTemplates.remove(at: idx)
									if localDefaultID == id { localDefaultID = nil }
								}
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
					.onDelete { offsets in
						// Support Delete key / context “Delete” on macOS lists
						withAnimation {
							for o in offsets.sorted(by: >) {
								let id = localTemplates[o].id
								localTemplates.remove(at: o)
								if localDefaultID == id { localDefaultID = nil }
							}
						}
					}
				}
				.listStyle(.inset)
				.frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    // Commit changes back to SessionManager and persist
                    sessionManager.templates = localTemplates
                    sessionManager.defaultTemplateId = localDefaultID
                    sessionManager.saveTemplates()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            localTemplates = sessionManager.templates
            localDefaultID = sessionManager.defaultTemplateId
        }
    }
}
