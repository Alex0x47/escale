import EscaleCore
import SwiftUI
import UniformTypeIdentifiers

struct NewIOSVersionRequest: Identifiable {
    let id = UUID()
    let suggestedVersion: String
}
struct NewIOSVersionSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var versionNumber: String
    @State private var isCreating = false

    init(initialVersion: String) {
        _versionNumber = State(initialValue: initialVersion)
    }

    private var cleanVersionNumber: String {
        versionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                "Create an iOS version",
                subtitle: "Creates an editable App Store Connect draft. Escale will not submit it for review.",
                eyebrow: "App Store Connect"
            )
            TextField("Version, for example 2.4.0", text: $versionNumber)
                .textFieldStyle(.roundedBorder)

            if !cleanVersionNumber.isEmpty, !isValidAppStoreVersion(cleanVersionNumber) {
                Label("Use one to three numeric components separated by periods.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("The previous live version’s promotional text is loaded automatically for every matching localization.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    isCreating = true
                    Task {
                        if await store.createAppStoreVersion(cleanVersionNumber) {
                            dismiss()
                        }
                        isCreating = false
                    }
                } label: {
                    if isCreating {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Creating version…")
                        }
                    } else {
                        Label(
                            "Create version",
                            systemImage: "plus.circle.fill"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidAppStoreVersion(cleanVersionNumber) || isCreating)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
