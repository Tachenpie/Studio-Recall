import SwiftUI

struct DiffReviewSheet: View {
    @EnvironmentObject var sessionManager: SessionManager

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
            .frame(minWidth: 420, minHeight: 320)
        }
    }
}
