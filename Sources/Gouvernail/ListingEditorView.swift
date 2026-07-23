import AppKit
import SwiftUI

struct ListingEditorView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedLocalizationID: UUID?
    @State private var selectedField: ListingMetadataField = .promotionalText
    @State private var isTranslating = false
    @State private var translatingFields: Set<ListingMetadataField> = []
    @State private var isTranslatingPlayReleaseNotes = false
    @State private var isCreatingVersion = false
    @State private var showingNewVersion = false
    @State private var newVersionNumber = ""

    var body: some View {
        HSplitView {
            localeSidebar.frame(minWidth: 205, idealWidth: 225, maxWidth: 250)
            editor.frame(minWidth: 560)
        }
        .background(Theme.canvas)
        .navigationTitle("Store listing")
        .onAppear {
            if selectedLocalizationID == nil { selectedLocalizationID = store.selectedLocalizations.first?.id }
        }
        .onChange(of: store.selectedAppID) { _, _ in
            selectedLocalizationID = store.selectedLocalizations.first?.id
        }
        .onChange(of: store.selectedLocalizations.map(\.id)) { _, ids in
            if selectedLocalizationID.map(ids.contains) != true {
                selectedLocalizationID = ids.first
            }
        }
        .sheet(isPresented: $showingNewVersion) { newVersionSheet }
    }

    private var localeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LOCALIZATIONS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                Text("\(store.selectedLocalizations.count) languages").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.selectedLocalizations) { localization in
                        let completion = localization.completion(for: store.selectedEditingPlatforms)
                        Button {
                            selectedLocalizationID = localization.id
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
                                    Circle()
                                        .trim(from: 0, to: completion)
                                        .stroke(completion == 1 ? Color.green : Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(completion * 100))")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(localization.language).font(.subheadline.weight(.semibold))
                                        if localization.id == store.selectedPrimaryLocalization?.id {
                                            Text("PRIMARY")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(Theme.accent)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Theme.accent.opacity(0.1), in: Capsule())
                                        }
                                    }
                                    Text(localization.locale).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !localization.dirtyPlatforms.isEmpty {
                                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(selectedLocalizationID == localization.id ? Theme.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            Divider()
            Menu {
                ForEach(supportedLocales, id: \.code) { item in
                    Button(item.name) {
                        store.addLocalization(locale: item.code, language: item.name)
                        selectedLocalizationID = store.selectedLocalizations.first(where: { $0.locale == item.code })?.id
                    }
                    .disabled(store.selectedLocalizations.contains(where: { $0.locale == item.code }))
                }
            } label: {
                Label("Add localization", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(15)
        }
        .background(Theme.sidebar.opacity(0.75))
    }

    private var supportedLocales: [(code: String, name: String)] {
        [
            ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("ar-SA", "Arabic"), ("ca", "Catalan"),
            ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"), ("hr", "Croatian"),
            ("cs", "Czech"), ("da", "Danish"), ("nl-NL", "Dutch"), ("fi", "Finnish"),
            ("fr-FR", "French"), ("fr-CA", "French (Canada)"), ("de-DE", "German"), ("el", "Greek"),
            ("he", "Hebrew"), ("hi", "Hindi"), ("hu", "Hungarian"), ("id", "Indonesian"),
            ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("ms", "Malay"), ("no", "Norwegian"),
            ("pl", "Polish"), ("pt-BR", "Portuguese (Brazil)"), ("pt-PT", "Portuguese (Portugal)"),
            ("ro", "Romanian"), ("ru", "Russian"), ("sk", "Slovak"), ("es-ES", "Spanish"),
            ("es-MX", "Spanish (Mexico)"), ("sv", "Swedish"), ("th", "Thai"), ("tr", "Turkish"),
            ("uk", "Ukrainian"), ("vi", "Vietnamese")
        ]
    }

    @ViewBuilder
    private var editor: some View {
        if let selectedLocalizationID,
           let localization = store.selectedLocalizations.first(where: { $0.id == selectedLocalizationID }) {
            let binding = store.localizationBinding(id: selectedLocalizationID)
            VStack(spacing: 0) {
                editorHeader(localization)
                Divider()
                HSplitView {
                    fields(binding: binding)
                    storePreview(localization: binding.wrappedValue)
                        .frame(minWidth: 310, idealWidth: 350, maxWidth: 420)
                }
            }
        } else {
            VStack(spacing: 14) {
                EmptyState(icon: "character.book.closed", title: "No localization", message: "Create an iOS version or add a language to begin editing your store listing.")
                if let apple = store.selectedApp?.appStoreApp, !apple.hasEditableMetadataVersion {
                    Button {
                        newVersionNumber = suggestedNextVersion(from: apple.version)
                        showingNewVersion = true
                    } label: { Label("Create iOS version", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func editorHeader(_ localization: ListingLocalization) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.language).font(.title3.weight(.bold))
                HStack(spacing: 6) {
                    Text(localization.locale).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if localization.id == store.selectedPrimaryLocalization?.id {
                        Text("Primary locale").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    if !localization.dirtyPlatforms.isEmpty {
                        Text("Unsaved changes").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    } else {
                        Text("Synced").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            if let apple = store.selectedApp?.appStoreApp, !apple.hasEditableMetadataVersion {
                Button {
                    newVersionNumber = suggestedNextVersion(from: apple.version)
                    showingNewVersion = true
                } label: { Label("New iOS version", systemImage: "plus.circle") }
                .buttonStyle(.bordered)
            } else if let apple = store.selectedApp?.appStoreApp {
                Text("iOS \(apple.version) draft").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Button {
                guard let source = store.selectedPrimaryLocalization else { return }
                isTranslating = true
                Task {
                    await store.translateLocalization(id: localization.id, from: source.id)
                    isTranslating = false
                }
            } label: {
                if isTranslating { ProgressView().controlSize(.small) } else { Label("Translate full listing", systemImage: "sparkles") }
            }
            .buttonStyle(.bordered)
            .disabled(
                localization.id == store.selectedPrimaryLocalization?.id
                    || isTranslating
                    || !translatingFields.isEmpty
                    || store.selectedPrimaryLocalization == nil
            )
            Button {
                Task { await store.saveLocalization(id: localization.id) }
            } label: {
                Label("Save to stores", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(localization.dirtyPlatforms.isEmpty || !metadataViolations(localization).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.card.opacity(0.55))
    }

    private func fields(binding: Binding<ListingLocalization>) -> some View {
        let localization = binding.wrappedValue
        return ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Text("Metadata").font(.headline)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(store.platformFilter.platforms.sorted(by: { $0.rawValue < $1.rawValue })) { platform in
                            PlatformBadge(platform: platform)
                        }
                    }
                }
                field(text: binding.title, limit: 30, axis: .horizontal, focus: .title, localization: localization)
                field(text: binding.subtitle, limit: limits.subtitle, axis: .horizontal, focus: .subtitle, localization: localization)
                if store.selectedEditingPlatforms.contains(.appStore) {
                    field(text: binding.promotionalText, limit: 170, axis: .vertical, focus: .promotionalText, localization: localization, minHeight: 88)
                }
                field(text: binding.description, limit: 4_000, axis: .vertical, focus: .description, localization: localization, minHeight: 175)
                if store.selectedEditingPlatforms.contains(.appStore) {
                    field(text: binding.keywords, limit: 100, axis: .vertical, focus: .keywords, localization: localization, minHeight: 70)
                    field(text: binding.releaseNotes, limit: 4_000, axis: .vertical, focus: .releaseNotes, localization: localization, minHeight: 110)
                }
                if store.selectedEditingPlatforms.contains(.playStore) {
                    googlePlayReleaseNotesEditor(localization: localization)
                }
            }
            .padding(22)
            .frame(maxWidth: 760)
        }
    }

    private func googlePlayReleaseNotesEditor(localization: ListingLocalization) -> some View {
        let locale = store.googlePlayReleaseNoteLocale(for: localization)
        let note = store.googlePlayReleaseNoteBinding(locale: locale)
        let primary = store.selectedGooglePrimaryLocalization
        let isPrimary = localization.id == primary?.id
        let sourceLocale = primary.map(store.googlePlayReleaseNoteLocale) ?? ""
        let sourceText = googlePlayReleaseNote(in: store.selectedGooglePlayReleaseNotesBlock, locale: sourceLocale)
        let block = store.selectedGooglePlayReleaseNotesBlock
        let issues = googlePlayReleaseNotesValidationIssues(block)

        return VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 2)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GOOGLE PLAY · WHAT’S NEW").font(.caption2.weight(.bold)).tracking(0.65).foregroundStyle(.secondary)
                    Text("Release notes for the bundle-upload workflow · <\(locale)>")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard !sourceLocale.isEmpty else { return }
                    isTranslatingPlayReleaseNotes = true
                    Task {
                        await store.translateGooglePlayReleaseNotes(
                            from: sourceLocale,
                            to: isPrimary ? nil : locale
                        )
                        isTranslatingPlayReleaseNotes = false
                    }
                } label: {
                    if isTranslatingPlayReleaseNotes {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text(isPrimary ? "Translating all…" : "Translating…")
                        }
                    } else if isPrimary {
                        Label("AI · Translate to all", systemImage: "character.book.closed.fill")
                    } else {
                        Label("AI · From primary", systemImage: "arrow.right.circle.fill")
                    }
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(isPrimary ? Theme.accent : Color.blue)
                .disabled(
                    isTranslatingPlayReleaseNotes
                        || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || primary == nil
                )
                Text("\(note.wrappedValue.count) / \(googlePlayReleaseNoteCharacterLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(note.wrappedValue.count > googlePlayReleaseNoteCharacterLimit ? .red : .secondary)
            }

            TextEditor(text: note)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(9)
                .frame(minHeight: 105)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(note.wrappedValue.count > googlePlayReleaseNoteCharacterLimit ? Color.red.opacity(0.7) : Theme.border)
                )

            Text("Saved locally as part of one tagged block. It is not sent by Save to stores; copy the block into Google Play when preparing a release.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if isPrimary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PLAY CONSOLE TAGGED BLOCK").font(.caption2.weight(.bold)).tracking(0.65).foregroundStyle(.secondary)
                        Spacer()
                        if issues.isEmpty, !block.isEmpty {
                            Label("Valid", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(block, forType: .string)
                            store.showToast("Release notes copied", detail: "Paste the tagged block into Google Play’s release notes field.", kind: .success)
                        } label: {
                            Label("Copy block", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextEditor(text: store.googlePlayReleaseNotesBlockBinding())
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 190)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(issues.isEmpty ? Theme.border : Color.red.opacity(0.7))
                        )

                    if let issue = issues.first {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Each language tag is kept on its own line. Google Play allows up to \(googlePlayReleaseNoteCharacterLimit) characters per language.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Theme.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border))
            }
        }
    }

    private var limits: ListingMetadataLimits {
        ListingMetadataLimits(platforms: store.platformFilter.platforms.intersection(store.selectedAvailablePlatforms))
    }

    private func metadataViolations(_ localization: ListingLocalization) -> [String] {
        limits.violations(in: localization, platforms: store.platformFilter.platforms.intersection(store.selectedAvailablePlatforms))
    }

    private var newVersionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Create an iOS version", subtitle: "Creates an editable App Store Connect draft. Gouvernail will not submit it for review.", eyebrow: "App Store Connect")
            TextField("Version, for example 2.4.0", text: $newVersionNumber)
                .textFieldStyle(.roundedBorder)
            Text("The previous live version’s promotional text is loaded automatically for every matching localization.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { showingNewVersion = false }.keyboardShortcut(.cancelAction)
                Button("Create version") {
                    isCreatingVersion = true
                    Task {
                        if await store.createAppStoreVersion(newVersionNumber) { showingNewVersion = false }
                        isCreatingVersion = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newVersionNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingVersion)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func suggestedNextVersion(from version: String) -> String {
        var parts = version.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return "1.0.0" }
        while parts.count < 3 { parts.append(0) }
        parts[parts.count - 1] += 1
        return parts.map(String.init).joined(separator: ".")
    }

    private func field(
        text: Binding<String>,
        limit: Int,
        axis: Axis,
        focus: ListingMetadataField,
        localization: ListingLocalization,
        minHeight: CGFloat = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(focus.displayName.uppercased()).font(.caption2.weight(.bold)).tracking(0.65).foregroundStyle(.secondary)
                Spacer()
                fieldTranslationButton(focus, localization: localization)
                Text("\(text.wrappedValue.count) / \(limit)").font(.caption.monospacedDigit()).foregroundStyle(text.wrappedValue.count > limit ? .red : .secondary)
            }
            TextField(focus.displayName, text: text, axis: axis)
                .textFieldStyle(.plain)
                .lineLimit(axis == .vertical ? 2...12 : 1...1)
                .padding(12)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(selectedField == focus ? Theme.accent.opacity(0.55) : Theme.border))
                .onTapGesture { selectedField = focus }
        }
    }

    private func fieldTranslationButton(
        _ field: ListingMetadataField,
        localization: ListingLocalization
    ) -> some View {
        let primary = store.selectedPrimaryLocalization
        let isPrimary = localization.id == primary?.id
        let isRunning = translatingFields.contains(field)
        let sourceIsEmpty = primary.map {
            field.value(in: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        let hasTargets = store.selectedLocalizations.contains(where: { $0.id != localization.id })

        return Button {
            guard let primary else { return }
            translatingFields.insert(field)
            Task {
                if isPrimary {
                    await store.translateFieldToAllLocales(field, from: primary.id)
                } else {
                    await store.translateField(field, from: primary.id, to: localization.id)
                }
                translatingFields.remove(field)
            }
        } label: {
            if isRunning {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(isPrimary ? "Translating all…" : "Translating…")
                }
            } else if isPrimary {
                Label("AI · Translate to all", systemImage: "character.book.closed.fill")
            } else {
                Label("AI · From primary", systemImage: "arrow.right.circle.fill")
            }
        }
        .font(.caption2.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(isPrimary ? Theme.accent : Color.blue)
        .disabled(
            isTranslating
                || !translatingFields.isEmpty
                || sourceIsEmpty
                || primary == nil
                || (isPrimary && !hasTargets)
        )
        .help(
            isPrimary
                ? "Translate only \(field.displayName.lowercased()) from the primary locale into every other locale."
                : "Replace only \(field.displayName.lowercased()) with an AI translation of the primary locale."
        )
    }

    private func storePreview(localization: ListingLocalization) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LIVE PREVIEW").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                PlatformBadge(platform: store.platformFilter == .playStore ? .playStore : .appStore)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 13) {
                        if let app = store.selectedApp { AppMark(app: app, size: 60) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localization.title).font(.headline).lineLimit(2)
                            Text(localization.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { _ in Image(systemName: "star.fill") }
                            }
                            .font(.system(size: 8)).foregroundStyle(.orange)
                        }
                    }
                    if store.platformFilter != .playStore {
                        Text(localization.promotionalText).font(.subheadline).lineSpacing(3)
                    }
                    Divider()
                    if store.platformFilter != .playStore {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("What’s New").font(.headline)
                            Text(localization.releaseNotes).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("About this app").font(.headline)
                        Text(localization.description).font(.caption).foregroundStyle(.secondary).lineSpacing(3).lineLimit(12)
                    }
                }
                .padding(18)
            }
        }
        .background(Color.primary.opacity(0.025))
    }
}
