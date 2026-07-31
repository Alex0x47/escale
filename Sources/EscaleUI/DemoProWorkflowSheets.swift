import EscaleCore
import SwiftUI

struct DemoReleaseNoteTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (String) -> Void

    @State private var selectedTemplateID = templates[0].id

    private static let templates = [
        DemoReleaseNoteTemplate(
            id: "feature-launch",
            name: "Feature launch",
            body: "Discover a faster, more focused experience with new tools designed around your feedback. We’ve also improved reliability across the app."
        ),
        DemoReleaseNoteTemplate(
            id: "maintenance",
            name: "Polished maintenance",
            body: "This update includes performance improvements, smoother navigation, and fixes for issues reported by our community."
        ),
        DemoReleaseNoteTemplate(
            id: "thank-you",
            name: "Community thank-you",
            body: "Thanks for using the app! This release brings thoughtful refinements inspired by your feedback, plus stability improvements throughout."
        )
    ]

    private var selectedTemplate: DemoReleaseNoteTemplate {
        Self.templates.first(where: { $0.id == selectedTemplateID }) ?? Self.templates[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            demoHeader(
                title: "What’s New templates",
                subtitle: "Choose reusable release copy and apply it to the current demo locale.",
                icon: "doc.on.doc.fill"
            )

            Picker("Template", selection: $selectedTemplateID) {
                ForEach(Self.templates) { template in
                    Text(template.name).tag(template.id)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTemplate.name.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                Text(selectedTemplate.body)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
            }
            .padding(15)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onApply(selectedTemplate.body)
                    dismiss()
                } label: {
                    Label("Apply template", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 590)
    }
}

struct DemoAndroidVersionSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var versionCode = "241"
    @State private var releaseName = "2.4.1"
    @State private var track = "internal"
    @State private var isCreating = false

    private var isValid: Bool {
        !versionCode.isEmpty && versionCode.allSatisfy(\.isNumber)
            && !releaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            demoHeader(
                title: "Create an Android version",
                subtitle: "Preview the Escale Pro bundle-upload workflow. No file or store is modified.",
                icon: "shippingbox.fill"
            )

            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.title2)
                    .foregroundStyle(StorePlatform.playStore.tint)
                    .frame(width: 42, height: 42)
                    .background(StorePlatform.playStore.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Northstar-2.4.1.aab").font(.subheadline.weight(.semibold))
                    Text("Demo bundle · package and signing key ready").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Valid", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(14)
            .cardStyle(cornerRadius: 12)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VERSION CODE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    TextField("241", text: $versionCode).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("RELEASE NAME").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    TextField("2.4.1", text: $releaseName).textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TRACK").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Picker("Track", selection: $track) {
                    Text("Internal testing").tag("internal")
                    Text("Closed testing").tag("closed")
                    Text("Open testing").tag("open")
                    Text("Production").tag("production")
                }
                .pickerStyle(.segmented)
            }

            Label("The tagged Google Play release notes from the listing workspace will be attached to this draft.", systemImage: "text.document")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    isCreating = true
                    Task {
                        if await store.previewDemoGooglePlayDraft(
                            versionCode: versionCode,
                            releaseName: releaseName,
                            track: track
                        ) {
                            dismiss()
                        }
                        isCreating = false
                    }
                } label: {
                    if isCreating {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Creating draft…")
                        }
                    } else {
                        Label("Create demo draft", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(StorePlatform.playStore.tint)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isCreating)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

private struct DemoReleaseNoteTemplate: Identifiable {
    let id: String
    let name: String
    let body: String
}

private func demoHeader(title: String, subtitle: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
        Image(systemName: icon)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
            Text("DEMO · ESCALE PRO")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(Theme.accent)
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}
