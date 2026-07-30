import AppKit
import EscaleCore
import SwiftUI

public struct ListingEditorView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedLocalizationID: UUID?
    @State private var preferredEditingPlatform: StorePlatform = .appStore
    @State private var localizationFilter = ""
    @State private var selectedField: ListingMetadataField = .promotionalText
    @State private var isTranslating = false
    @State private var isSavingLocalizations = false
    @State private var translatingFields: Set<ListingMetadataField> = []
    @State private var isTranslatingPlayReleaseNotes = false
    @State private var proFeature: EscaleFeature?
    @State private var templateManagerRequest: ReleaseNoteTemplateManagerRequest?

    public var body: some View {
        HSplitView {
            localeSidebar.frame(minWidth: 205, idealWidth: 225, maxWidth: 250)
            editor.frame(minWidth: 560)
        }
        .background(Theme.canvas)
        .navigationTitle("Store listing")
        .onAppear {
            alignEditingPlatformWithFilter()
            if selectedLocalizationID == nil { selectedLocalizationID = displayedLocalizations.first?.id }
        }
        .onChange(of: store.selectedAppID) { _, _ in
            alignEditingPlatformWithFilter()
            selectedLocalizationID = displayedLocalizations.first?.id
        }
        .onChange(of: store.platformFilter) { _, _ in
            alignEditingPlatformWithFilter()
        }
        .onChange(of: store.selectedAvailablePlatforms) { _, _ in
            alignEditingPlatformWithFilter()
        }
        .onChange(of: displayedLocalizations.map(\.id)) { _, ids in
            if selectedLocalizationID.map(ids.contains) != true {
                selectedLocalizationID = ids.first
            }
        }
        .sheet(item: $proFeature) { feature in
            ProFeatureSheet(feature: feature)
        }
        .sheet(item: $templateManagerRequest) { request in
            ReleaseNoteTemplateManagerView(initialBody: request.initialBody)
                .environmentObject(store)
        }
    }

    private var activeEditingPlatform: StorePlatform {
        let available = store.platformFilter.platforms.intersection(store.selectedAvailablePlatforms)
        if available.contains(preferredEditingPlatform) {
            return preferredEditingPlatform
        }
        return StorePlatform.allCases.first(where: available.contains) ?? preferredEditingPlatform
    }

    private var activeEditingPlatforms: Set<StorePlatform> {
        [activeEditingPlatform]
    }

    private var displayedLocalizations: [ListingLocalization] {
        store.localizations(displaying: activeEditingPlatforms)
    }

    private var primaryLocalization: ListingLocalization? {
        store.primarySelectedLocalization(displaying: activeEditingPlatforms)
    }

    private var selectableEditingPlatforms: [StorePlatform] {
        StorePlatform.allCases.filter {
            store.platformFilter.platforms.contains($0)
                && store.selectedAvailablePlatforms.contains($0)
        }
    }

    private func alignEditingPlatformWithFilter() {
        if let onlyPlatform = selectableEditingPlatforms.count == 1
            ? selectableEditingPlatforms.first
            : nil {
            preferredEditingPlatform = onlyPlatform
        } else if !selectableEditingPlatforms.contains(preferredEditingPlatform),
                  let first = selectableEditingPlatforms.first {
            preferredEditingPlatform = first
        }
    }

    private var localeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LOCALIZATIONS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                Text("\(displayedLocalizations.count) languages").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter languages", text: $localizationFilter)
                    .textFieldStyle(.plain)
                if !localizationFilter.isEmpty {
                    Button {
                        localizationFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredLocalizations) { localization in
                        let completion = localization.completion(for: activeEditingPlatforms)
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
                                        if localization.id == primaryLocalization?.id {
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
                                if localization.dirtyPlatforms.contains(activeEditingPlatform) {
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
                    if filteredLocalizations.isEmpty {
                        Text("No matching languages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(8)
            }
            Divider()
            Menu {
                ForEach(supportedLocales, id: \.code) { item in
                    Button(item.name) {
                        store.addLocalization(locale: item.code, language: item.name)
                        selectedLocalizationID = displayedLocalizations.first(where: { $0.locale == item.code })?.id
                    }
                    .disabled(displayedLocalizations.contains(where: { $0.locale == item.code }))
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

    private var filteredLocalizations: [ListingLocalization] {
        let query = localizationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        var localizations = query.isEmpty
            ? displayedLocalizations
            : displayedLocalizations.filter {
                $0.language.localizedStandardContains(query)
                    || $0.locale.localizedStandardContains(query)
            }

        if let primaryID = primaryLocalization?.id,
           let primaryIndex = localizations.firstIndex(where: { $0.id == primaryID }) {
            localizations.insert(localizations.remove(at: primaryIndex), at: 0)
        }
        return localizations
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
           let localization = displayedLocalizations.first(where: { $0.id == selectedLocalizationID }) {
            let binding = store.localizationBinding(id: selectedLocalizationID, displaying: activeEditingPlatforms)
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
                EmptyState(icon: "character.book.closed", title: "No localization", message: "Add a language to begin editing your store listing.")
            }
        }
    }

    private func editorHeader(_ localization: ListingLocalization) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.language).font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        Text(localization.locale).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if localization.id == primaryLocalization?.id {
                            Text("Primary locale").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        if localization.dirtyPlatforms.contains(activeEditingPlatform) {
                            Text("Unsaved changes").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        } else {
                            Text("Synced").font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                }
                Spacer()
                Button {
                    guard let source = primaryLocalization else { return }
                    let platforms = activeEditingPlatforms
                    isTranslating = true
                    Task {
                        await store.translateLocalization(
                            id: localization.id,
                            from: source.id,
                            platforms: platforms
                        )
                        isTranslating = false
                    }
                } label: {
                    if isTranslating { ProgressView().controlSize(.small) } else { Label("Translate full listing", systemImage: "sparkles") }
                }
                .buttonStyle(.bordered)
                .disabled(
                    localization.id == primaryLocalization?.id
                        || isTranslating
                        || !translatingFields.isEmpty
                        || primaryLocalization == nil
                )
                Button {
                    let platforms = activeEditingPlatforms
                    isSavingLocalizations = true
                    Task {
                        await store.saveEditedLocalizations(platforms: platforms)
                        isSavingLocalizations = false
                    }
                } label: {
                    if isSavingLocalizations {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Label("Save to \(activeEditingPlatform.rawValue)", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isSavingLocalizations
                        || editedLocalizations.isEmpty
                        || editedLocalizations.contains(where: { !metadataViolations($0).isEmpty })
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if selectableEditingPlatforms.count > 1 {
                Divider().padding(.horizontal, 20)
                HStack(spacing: 12) {
                    Text("EDITING STORE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                    Picker("Editing store", selection: $preferredEditingPlatform) {
                        ForEach(selectableEditingPlatforms) { platform in
                            Label(platform.rawValue, systemImage: platform.icon)
                                .tag(platform)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .background(Theme.card.opacity(0.55))
    }

    private func fields(binding: Binding<ListingLocalization>) -> some View {
        let localization = binding.wrappedValue
        return ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Text("Metadata").font(.headline)
                    Spacer()
                    if selectableEditingPlatforms.count == 1 {
                        PlatformBadge(platform: activeEditingPlatform)
                    }
                }
                field(text: binding.title, limit: 30, axis: .horizontal, focus: .title, localization: localization)
                if activeEditingPlatform == .appStore {
                    field(text: binding.subtitle, limit: limits.subtitle, axis: .horizontal, focus: .subtitle, localization: localization)
                    field(text: binding.promotionalText, limit: 170, axis: .vertical, focus: .promotionalText, localization: localization, minHeight: 88)
                }
                if activeEditingPlatform == .playStore {
                    field(
                        text: shortDescriptionBinding(binding),
                        limit: limits.shortDescription,
                        axis: .vertical,
                        focus: .shortDescription,
                        localization: localization,
                        minHeight: 70
                    )
                }
                field(text: binding.description, limit: 4_000, axis: .vertical, focus: .description, localization: localization, minHeight: 175)
                if activeEditingPlatform == .appStore {
                    field(text: binding.keywords, limit: 100, axis: .vertical, focus: .keywords, localization: localization, minHeight: 70)
                    field(text: binding.releaseNotes, limit: 4_000, axis: .vertical, focus: .releaseNotes, localization: localization, minHeight: 110)
                }
                if activeEditingPlatform == .playStore {
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
                releaseNoteTemplateControl(
                    currentText: note.wrappedValue,
                    targetLimit: googlePlayReleaseNoteCharacterLimit
                ) { template in
                    store.applyReleaseNoteTemplate(id: template.id, toGooglePlayLocale: locale)
                }
                Button {
                    guard !sourceLocale.isEmpty else { return }
                    if isPrimary, !store.hasAccess(to: .bulkTranslations) {
                        proFeature = .bulkTranslations
                        return
                    }
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
                        Label(
                            store.hasAccess(to: .bulkTranslations)
                                ? "AI · Translate to all"
                                : "AI · Translate to all · Pro",
                            systemImage: store.hasAccess(to: .bulkTranslations)
                                ? "character.book.closed.fill"
                                : "lock.fill"
                        )
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
        ListingMetadataLimits(platforms: activeEditingPlatforms)
    }

    private var editedLocalizations: [ListingLocalization] {
        displayedLocalizations.filter { $0.dirtyPlatforms.contains(activeEditingPlatform) }
    }

    private func metadataViolations(_ localization: ListingLocalization) -> [String] {
        limits.violations(in: localization, platforms: activeEditingPlatforms)
    }

    private func shortDescriptionBinding(_ localization: Binding<ListingLocalization>) -> Binding<String> {
        Binding(
            get: { localization.wrappedValue.shortDescription },
            set: { value in
                var updated = localization.wrappedValue
                updated.shortDescription = value
                localization.wrappedValue = updated
            }
        )
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
                if focus == .releaseNotes {
                    releaseNoteTemplateControl(currentText: text.wrappedValue, targetLimit: limit) { template in
                        store.applyReleaseNoteTemplate(id: template.id, toLocalization: localization.id)
                    }
                }
                fieldTranslationButton(focus, localization: localization)
                Text("\(text.wrappedValue.count) / \(limit)").font(.caption.monospacedDigit()).foregroundStyle(text.wrappedValue.count > limit ? .red : .secondary)
            }
            Group {
                if axis == .vertical {
                    TextEditor(text: text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: max(minHeight, 70), alignment: .topLeading)
                } else {
                    TextField(focus.displayName, text: text)
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .padding(12)
                }
            }
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(selectedField == focus ? Theme.accent.opacity(0.55) : Theme.border))
                .onTapGesture { selectedField = focus }
        }
    }

    @ViewBuilder
    private func releaseNoteTemplateControl(
        currentText: String,
        targetLimit: Int,
        apply: @escaping (ReleaseNoteTemplate) -> Void
    ) -> some View {
        if store.hasAccess(to: .releaseNoteTemplates) {
            Menu {
                if store.releaseNoteTemplates.isEmpty {
                    Button {
                        templateManagerRequest = ReleaseNoteTemplateManagerRequest(initialBody: currentText)
                    } label: {
                        Label("Create your first template…", systemImage: "plus")
                    }
                } else {
                    Section("Apply a template") {
                        ForEach(store.releaseNoteTemplates) { template in
                            Button {
                                apply(template)
                            } label: {
                                Label {
                                    Text(
                                        template.body.count <= targetLimit
                                            ? template.name
                                            : "\(template.name) · Too long"
                                    )
                                } icon: {
                                    Image(systemName: "doc.text")
                                }
                            }
                            .disabled(template.body.count > targetLimit)
                        }
                    }
                    Divider()
                    Button {
                        templateManagerRequest = ReleaseNoteTemplateManagerRequest(initialBody: currentText)
                    } label: {
                        Label("Save current text as template…", systemImage: "plus.square.on.square")
                    }
                    .disabled(currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        templateManagerRequest = ReleaseNoteTemplateManagerRequest(initialBody: nil)
                    } label: {
                        Label("Manage templates…", systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                Label(
                    store.releaseNoteTemplates.isEmpty ? "Create template" : "Templates",
                    systemImage: "doc.on.doc.fill"
                )
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(Theme.accent)
            .help("Apply reusable What’s New copy or manage your Escale Pro templates.")
        } else {
            Button {
                store.track(.proGateViewed(feature: .releaseNoteTemplates))
                proFeature = .releaseNoteTemplates
            } label: {
                Label("Templates · Pro", systemImage: "lock.fill")
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(Theme.accent)
            .help("Upgrade to Pro to save and reuse What’s New templates across apps and locales.")
        }
    }

    private func fieldTranslationButton(
        _ field: ListingMetadataField,
        localization: ListingLocalization
    ) -> some View {
        let primary = primaryLocalization
        let isPrimary = localization.id == primary?.id
        let isRunning = translatingFields.contains(field)
        let sourceIsEmpty = primary.map {
            field.value(in: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        let hasTargets = displayedLocalizations.contains(where: { $0.id != localization.id })

        return Button {
            guard let primary else { return }
            if isPrimary, !store.hasAccess(to: .bulkTranslations) {
                proFeature = .bulkTranslations
                return
            }
            translatingFields.insert(field)
            let platforms = activeEditingPlatforms
            Task {
                if isPrimary {
                    await store.translateFieldToAllLocales(
                        field,
                        from: primary.id,
                        platforms: platforms
                    )
                } else {
                    await store.translateField(
                        field,
                        from: primary.id,
                        to: localization.id,
                        platforms: platforms
                    )
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
                Label(
                    store.hasAccess(to: .bulkTranslations)
                        ? "AI · Translate to all"
                        : "AI · Translate to all · Pro",
                    systemImage: store.hasAccess(to: .bulkTranslations)
                        ? "character.book.closed.fill"
                        : "lock.fill"
                )
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
                PlatformBadge(platform: activeEditingPlatform)
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
                    if activeEditingPlatform == .appStore {
                        Text(localization.promotionalText).font(.subheadline).lineSpacing(3)
                    }
                    Divider()
                    if activeEditingPlatform == .appStore {
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

private struct ReleaseNoteTemplateManagerRequest: Identifiable {
    let id = UUID()
    let initialBody: String?
}

private struct ReleaseNoteTemplateManagerView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    let initialBody: String?

    @State private var selectedTemplateID: UUID?
    @State private var isCreating = false
    @State private var name = ""
    @State private var templateBody = ""
    @State private var templatePendingDeletion: ReleaseNoteTemplate?

    private var selectedTemplate: ReleaseNoteTemplate? {
        selectedTemplateID.flatMap { id in
            store.releaseNoteTemplates.first(where: { $0.id == id })
        }
    }

    private var validationIssue: String? {
        releaseNoteTemplateValidationIssue(name: name, body: templateBody)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                templateList
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 270)
                templateEditor
                    .frame(minWidth: 440)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .background(Theme.canvas)
        .onAppear {
            if let initialBody {
                beginNewTemplate(body: initialBody)
            } else if let first = store.releaseNoteTemplates.first {
                select(first)
            } else {
                beginNewTemplate(body: "")
            }
        }
        .alert(
            "Delete this template?",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            presenting: templatePendingDeletion
        ) { template in
            Button("Cancel", role: .cancel) {}
            Button("Delete “\(template.name)”", role: .destructive) {
                guard store.deleteReleaseNoteTemplate(id: template.id) else { return }
                templatePendingDeletion = nil
                if let next = store.releaseNoteTemplates.first {
                    select(next)
                } else {
                    beginNewTemplate(body: "")
                }
            }
        } message: { _ in
            Text("Listings that already use this text will not change.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("What’s New templates")
                    .font(.title2.weight(.bold))
                Text("Write recurring release notes once, then reuse them across apps and locales.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("ESCALE PRO")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.1), in: Capsule())
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(20)
        .background(Theme.card.opacity(0.7))
    }

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEMPLATES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text("\(store.releaseNoteTemplates.count) saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    beginNewTemplate(body: "")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("New template")
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 5) {
                    if isCreating {
                        templateListRow(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "New template"
                                : name,
                            body: templateBody,
                            selected: true
                        )
                    }
                    ForEach(store.releaseNoteTemplates) { template in
                        Button {
                            select(template)
                        } label: {
                            templateListRow(
                                name: template.name,
                                body: template.body,
                                selected: !isCreating && selectedTemplateID == template.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if store.releaseNoteTemplates.isEmpty, !isCreating {
                        Text("No templates yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(8)
            }
        }
        .background(Theme.sidebar.opacity(0.72))
    }

    private func templateListRow(
        name: String,
        body: String,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            Text(templatePreview(body))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            selected ? Theme.accent.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isCreating ? "NEW TEMPLATE" : "EDIT TEMPLATE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                TextField("Template name", text: $name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Use a memorable name, such as “Maintenance update”.")
                    Spacer()
                    Text("\(name.count) / \(releaseNoteTemplateNameCharacterLimit)")
                        .monospacedDigit()
                        .foregroundStyle(
                            name.count > releaseNoteTemplateNameCharacterLimit ? Color.red : Color.secondary
                        )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("RELEASE NOTES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if templateBody.count <= googlePlayReleaseNoteCharacterLimit {
                        Label("Apple + Google Play", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("App Store only", systemImage: "apple.logo")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.weight(.semibold))

                TextEditor(text: $templateBody)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(maxHeight: .infinity)
                    .background(
                        Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                templateBody.count > releaseNoteTemplateBodyCharacterLimit
                                    ? Color.red.opacity(0.7)
                                    : Theme.border
                            )
                    )

                HStack(alignment: .firstTextBaseline) {
                    Text(
                        templateBody.count <= googlePlayReleaseNoteCharacterLimit
                            ? "Ready for both stores."
                            : "Google Play allows \(googlePlayReleaseNoteCharacterLimit) characters; this template remains available for the App Store."
                    )
                    Spacer()
                    Text("\(templateBody.count) / \(releaseNoteTemplateBodyCharacterLimit.formatted())")
                        .monospacedDigit()
                        .foregroundStyle(
                            templateBody.count > releaseNoteTemplateBodyCharacterLimit ? Color.red : Color.secondary
                        )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)

            if let validationIssue {
                Label(validationIssue, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Label(
                    "Templates fill the field locally. You still review and save the listing yourself.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Theme.canvas)
    }

    private var footer: some View {
        HStack {
            if !isCreating, let selectedTemplate {
                Button("Delete", role: .destructive) {
                    templatePendingDeletion = selectedTemplate
                }
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            Button(isCreating ? "Save template" : "Save changes") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(validationIssue != nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.card.opacity(0.75))
    }

    private func beginNewTemplate(body: String) {
        selectedTemplateID = nil
        isCreating = true
        name = ""
        templateBody = body
    }

    private func select(_ template: ReleaseNoteTemplate) {
        selectedTemplateID = template.id
        isCreating = false
        name = template.name
        templateBody = template.body
    }

    private func save() {
        if isCreating {
            guard let id = store.createReleaseNoteTemplate(name: name, body: templateBody),
                  let template = store.releaseNoteTemplates.first(where: { $0.id == id }) else {
                return
            }
            select(template)
        } else if let selectedTemplateID,
                  store.updateReleaseNoteTemplate(id: selectedTemplateID, name: name, body: templateBody),
                  let template = store.releaseNoteTemplates.first(where: { $0.id == selectedTemplateID }) {
            select(template)
        }
    }

    private func templatePreview(_ body: String) -> String {
        let preview = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        return preview ?? "Add reusable release notes"
    }
}
