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

struct NewAndroidVersionSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.escaleCommercialActions) private var commercialActions
    @Environment(\.openURL) private var openURL
    @State private var isCreating = false
    @State private var showingBundleImporter = false
    @State private var bundleURL: URL?
    @State private var bundleSelectionError: String?
    @State private var releaseName = ""
    @State private var releaseTrack: AndroidReleaseTrack = .production
    @State private var showsOfficialDownloadPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(
                "Create an Android version",
                subtitle: "Uploads a signed Android App Bundle and creates an editable Google Play draft. Escale will not submit it for review or release it.",
                eyebrow: "Google Play"
            )

            if !hasProPlan {
                proCallout
            }

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("SIGNED APP BUNDLE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: bundleURL == nil ? "shippingbox" : "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(bundleURL == nil ? Theme.accent : .green)
                            .frame(width: 38, height: 38)
                            .background(
                                (bundleURL == nil ? Theme.accent : Color.green).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bundleURL?.lastPathComponent ?? "No bundle selected")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("Google Play validates the package name, signing key, and version code.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(bundleURL == nil ? "Choose .aab…" : "Replace…") {
                            showingBundleImporter = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border))

                    if let bundleSelectionError {
                        Label(bundleSelectionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("TARGET TRACK")
                            .font(.caption2.weight(.bold))
                            .tracking(0.65)
                            .foregroundStyle(.secondary)
                        Picker("Target track", selection: $releaseTrack) {
                            ForEach(AndroidReleaseTrack.allCases) { track in
                                Text(track.title).tag(track)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("RELEASE NAME · OPTIONAL")
                            .font(.caption2.weight(.bold))
                            .tracking(0.65)
                            .foregroundStyle(.secondary)
                        TextField("Google can derive it from the bundle", text: $releaseName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    let issues = googlePlayReleaseNotesValidationIssues(store.selectedGooglePlayReleaseNotesBlock)
                    let noteCount = googlePlayReleaseNotes(in: store.selectedGooglePlayReleaseNotesBlock)
                        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .count
                    Label(
                        issues.isEmpty
                            ? "\(noteCount) localized release note\(noteCount == 1 ? "" : "s") will be attached."
                            : "Release notes are invalid and will be skipped: \(issues[0])",
                        systemImage: issues.isEmpty ? "text.document" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(issues.isEmpty ? Color.secondary : Color.orange)
                    Text("The bundle is saved as a draft on \(releaseTrack.title). Existing users will not receive it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!hasProPlan)
            .opacity(hasProPlan ? 1 : 0.55)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    guard let bundleURL else { return }
                    isCreating = true
                    Task {
                        let created = await store.createGooglePlayDraftRelease(
                            bundleFileURL: bundleURL,
                            track: releaseTrack.rawValue,
                            releaseName: releaseName
                        )
                        isCreating = false
                        if created {
                            dismiss()
                        }
                    }
                } label: {
                    if isCreating {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Uploading bundle…")
                        }
                    } else {
                        Label(
                            "Upload and create draft",
                            systemImage: hasProPlan ? "shippingbox.fill" : "lock.fill"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasProPlan || bundleURL == nil || isCreating)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear {
            if !hasProPlan {
                store.track(.proGateViewed(feature: .uploadGooglePlayBundle))
            }
        }
        .fileImporter(
            isPresented: $showingBundleImporter,
            allowedContentTypes: [UTType(filenameExtension: "aab") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.pathExtension.caseInsensitiveCompare("aab") == .orderedSame else {
                    bundleURL = nil
                    bundleSelectionError = "Choose an Android App Bundle with the .aab extension."
                    return
                }
                bundleURL = url
                bundleSelectionError = nil
            case .failure(let error):
                bundleSelectionError = error.localizedDescription
            }
        }
        .alert("Download the official Escale app", isPresented: $showsOfficialDownloadPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Open download page") {
                openURL(Self.downloadPageURL)
            }
        } message: {
            Text("Uploading Google Play bundles is an Escale Pro feature. Download the official app to upgrade; your Community workspace will remain available.")
        }
    }

    private static let downloadPageURL = URL(string: "https://escale.app/")!

    private var hasProPlan: Bool {
        store.entitlements.plan == .pro
    }

    private var proCallout: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Android bundle uploads require Pro")
                    .font(.subheadline.weight(.semibold))
                Text("Only Escale Pro users can upload Android bundles and create Google Play drafts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Unlock Escale Pro") {
                if let commercialActions {
                    commercialActions.openLicenceManagement()
                } else {
                    showsOfficialDownloadPrompt = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(13)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.accent.opacity(0.22))
        )
    }
}

enum AndroidReleaseTrack: String, CaseIterable, Identifiable {
    case production
    case internalTesting = "internal"
    case closedTesting = "alpha"
    case openTesting = "beta"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .production: "Production"
        case .internalTesting: "Internal testing"
        case .closedTesting: "Closed testing"
        case .openTesting: "Open testing"
        }
    }
}
