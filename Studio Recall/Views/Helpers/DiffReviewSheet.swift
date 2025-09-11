//
//  DiffReviewSheet.swift
//  Studio Recall
//
//  Created by True Jackie on 9/11/25.
//

import SwiftUI

struct DiffReviewSheet: View {
	@EnvironmentObject var sessionManager: SessionManager
	@Environment(\.dismiss) private var dismiss
	
	var body: some View {
		let diffs = sessionManager.diffsForCurrentSession()
		NavigationStack {
			List {
				if diffs.isEmpty {
					Section {
						Label("No changes from defaults", systemImage: "checkmark.seal")
							.foregroundStyle(.secondary)
					}
				} else {
					ForEach(Array(diffs.enumerated()), id: \.offset) { _, item in
						Section("\(item.deviceName) • \(item.location)") {
							ForEach(Array(item.diffs.enumerated()), id: \.offset) { _, d in
								HStack(spacing: 8) {
									Text(d.name)
									Spacer()
									Text(verbatim: d.before.description)
										.foregroundStyle(.secondary)
									Image(systemName: "arrow.right")
										.font(.caption)
										.foregroundStyle(.tertiary)
									Text(verbatim: d.after.description)
								}
								.font(.callout)
							}
						}
					}
				}
			}
			.navigationTitle("Session Changes")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
						.keyboardShortcut(.cancelAction)        // Esc and ⌘.
						.keyboardShortcut("w", modifiers: .command) // (optional) ⌘W
				}
			}
			.frame(minWidth: 420, minHeight: 320)
#if os(macOS)
			.onExitCommand { dismiss() } // extra safety: Esc/“Exit” command
#endif
		}
	}
}
